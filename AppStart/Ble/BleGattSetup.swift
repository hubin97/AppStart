//
//  BleGattSetup.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  GATT 自动发现：Service → Characteristic → 订阅 Notify / 定位写特征。
//  所有目标 Service 的特征发现完成后，一次性回调 ready。
//  主 Profile + supplementaryGattProfiles 一并发现；ready 仅绑定主 write。

import Foundation
import CoreBluetooth

final class BleGattSetup {

    struct Result {
        let writeChar: CBCharacteristic?
        let readyService: CBService?
        let error: Error?
    }

    private let configuration: BleConfiguration
    private let logger: BleLogger
    /// 待发现特征的服务数量（用于判断全部完成）
    private var pendingServiceCount = 0
    /// 已完成特征发现的服务数量（与 pendingServiceCount 配对，用于 finalize）
    private var completedServiceCount = 0
    private var writeChar: CBCharacteristic?
    private var readyService: CBService?
    private var setupError: Error?
    /// 防止多个 service 回调重复触发 ready
    private var didEmitReady = false

    init(configuration: BleConfiguration, logger: BleLogger) {
        self.configuration = configuration
        self.logger = logger
    }

    /// 入口：合并主/附加 serviceUUIDs 发现服务（皆空则发现全部）
    func beginServiceDiscovery(on peripheral: CBPeripheral) {
        pendingServiceCount = 0
        completedServiceCount = 0
        writeChar = nil
        readyService = nil
        setupError = nil
        didEmitReady = false
        let uuids = mergedServiceUUIDs.isEmpty ? nil : mergedServiceUUIDs
        peripheral.discoverServices(uuids)
    }

    /// 服务发现回调：为每个 service 发起特征发现
    func handleDiscoveredServices(_ peripheral: CBPeripheral, error: Error?) -> Result? {
        if let error {
            return Result(writeChar: nil, readyService: nil, error: error)
        }
        guard let services = peripheral.services, !services.isEmpty else {
            return Result(writeChar: nil, readyService: nil, error: BleError.channelSetupFailed(
                NSError(domain: "BleGattSetup", code: 1, userInfo: [NSLocalizedDescriptionKey: "未发现服务"])
            ))
        }
        let targetServices = filterServices(services)
        guard !targetServices.isEmpty else {
            return Result(writeChar: nil, readyService: nil, error: BleError.channelSetupFailed(
                NSError(domain: "BleGattSetup", code: 2, userInfo: [NSLocalizedDescriptionKey: "未匹配到目标服务"])
            ))
        }
        pendingServiceCount = targetServices.count
        for service in targetServices {
            let charUUIDs = characteristicsToDiscover(for: service)
            if charUUIDs?.isEmpty != false {
                peripheral.discoverCharacteristics(nil, for: service)
            } else {
                peripheral.discoverCharacteristics(charUUIDs, for: service)
            }
        }
        return nil
    }

    /// 特征发现回调：读/订阅/记录写特征，全部 service 完成后 finalize
    func handleDiscoveredCharacteristics(
        peripheral: CBPeripheral,
        service: CBService,
        error: Error?
    ) -> Result? {
        if let error {
            setupError = error
        } else if let characteristics = service.characteristics {
            process(characteristics: characteristics, peripheral: peripheral, service: service)
        }
        completedServiceCount += 1
        return finalizeIfNeeded(peripheral: peripheral)
    }

    // MARK: - Private

    /// 主 Profile 与 supplementaryGattProfiles 合并后的 Service UUID 列表（空表示未配置，discover 全部）
    private var mergedServiceUUIDs: [CBUUID] {
        var combined: [CBUUID] = []
        if let primary = configuration.gattProfile.serviceUUIDs, !primary.isEmpty {
            combined.append(contentsOf: primary)
        }
        for profile in configuration.supplementaryGattProfiles {
            if let uuids = profile.serviceUUIDs, !uuids.isEmpty {
                combined.append(contentsOf: uuids)
            }
        }
        return combined
    }

    /// 按 mergedServiceUUIDs 过滤；未配置 UUID 时保留 peripheral 返回的全部 Service。
    private func filterServices(_ services: [CBService]) -> [CBService] {
        guard !mergedServiceUUIDs.isEmpty else { return services }
        return services.filter { service in
            mergedServiceUUIDs.contains { BleUUID.matches(service.uuid, $0) }
        }
    }

    /// 按 Service UUID 匹配 supplementary，否则回落主 gattProfile（决定 read/notify/write 目标）。
    private func profile(for service: CBService) -> BleGattProfile {
        for supplementary in configuration.supplementaryGattProfiles {
            guard let serviceUUIDs = supplementary.serviceUUIDs, !serviceUUIDs.isEmpty else { continue }
            if serviceUUIDs.contains(where: { BleUUID.matches(service.uuid, $0) }) {
                return supplementary
            }
        }
        return configuration.gattProfile
    }

    /// 是否主 Profile 所属 Service；仅主 Service 记录 writeChar（附加通道不参与 ready / 写队列）。
    private func isPrimaryService(_ service: CBService) -> Bool {
        guard let serviceUUIDs = configuration.gattProfile.serviceUUIDs, !serviceUUIDs.isEmpty else {
            return configuration.supplementaryGattProfiles.isEmpty
        }
        return serviceUUIDs.contains { BleUUID.matches(service.uuid, $0) }
    }

    /// 该 Service 对应 profile 下需发现的特征 UUID；nil 表示 discoverCharacteristics(nil) 发现全部。
    private func characteristicsToDiscover(for service: CBService) -> [CBUUID]? {
        let profile = profile(for: service)
        let charUUIDs = [profile.readCharUUID, profile.writeCharUUID, profile.notifyCharUUID].compactMap { $0 }
        return charUUIDs.isEmpty ? nil : charUUIDs
    }

    /// 遍历特征：read → setNotify → 记录 writeChar（write 仅主 Profile）
    private func process(characteristics: [CBCharacteristic], peripheral: CBPeripheral, service: CBService) {
        let profile = profile(for: service)
        let isPrimary = isPrimaryService(service)
        for characteristic in characteristics {
            if characteristic.properties.contains(.read),
               BleUUID.matches(characteristic.uuid, configured: profile.readCharUUID) {
                logger.log("读取特征: \(characteristic.uuid)")
                peripheral.readValue(for: characteristic)
            }
            if characteristic.properties.contains(.notify),
               BleUUID.matches(characteristic.uuid, configured: profile.notifyCharUUID) {
                logger.log("订阅通知: \(characteristic.uuid)")
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if isPrimary,
               characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse),
               BleUUID.matches(characteristic.uuid, configured: profile.writeCharUUID) {
                logger.log("记录写特征: \(characteristic.uuid)")
                writeChar = characteristic
                readyService = service
            }
            if configuration.discoverDescriptors {
                peripheral.discoverDescriptors(for: characteristic)
            }
        }
    }

    /// 所有 service 特征发现完毕，产出 ready 或 error（仅触发一次）
    private func finalizeIfNeeded(peripheral: CBPeripheral) -> Result? {
        guard completedServiceCount >= pendingServiceCount, !didEmitReady else { return nil }
        didEmitReady = true
        if let setupError {
            return Result(writeChar: nil, readyService: nil, error: setupError)
        }
        if configuration.gattProfile.writeCharUUID != nil, writeChar == nil {
            return Result(writeChar: nil, readyService: nil, error: BleError.writeCharacteristicNotFound)
        }
        return Result(writeChar: writeChar, readyService: readyService ?? peripheral.services?.first, error: nil)
    }
}
