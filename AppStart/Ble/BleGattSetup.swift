//
//  BleGattSetup.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  GATT 自动发现：Service → Characteristic → 订阅 Notify / 定位写特征。
//  所有目标 Service 的特征发现完成后，若配置了 Notify 则等待 `didUpdateNotificationStateFor` 确认，
//  再一次性回调 ready。主 Profile + supplementaryGattProfiles 一并发现；ready 仅绑定主 write。

import Foundation
import CoreBluetooth

final class BleGattSetup {

    /// GATT 建链只允许两种终态，避免 optional 组合出「无 error、也无 readyService」的非法成功。
    enum Result {
        case ready(writeChar: CBCharacteristic?, service: CBService)
        case failure(Error)
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
    /// 已调用 `setNotifyValue(true)`、等待 `didUpdateNotificationStateFor` 确认的特征
    private var pendingNotifyCharacteristics: Set<ObjectIdentifier> = []
    /// 已成功发起订阅的 Notify UUID（用于校验配置项是否命中）
    private var subscribedNotifyUUIDs: [CBUUID] = []
    /// 特征发现阶段已结束，仅剩 Notify 确认 barrier
    private var characteristicsDiscoveryFinished = false

    init(configuration: BleConfiguration, logger: BleLogger) {
        self.configuration = configuration
        self.logger = logger
    }

    // MARK: - Discovery

    /// 入口：合并主/附加 serviceUUIDs 发现服务（皆空则发现全部）
    func beginServiceDiscovery(on peripheral: CBPeripheral) {
        pendingServiceCount = 0
        completedServiceCount = 0
        writeChar = nil
        readyService = nil
        setupError = nil
        didEmitReady = false
        pendingNotifyCharacteristics = []
        subscribedNotifyUUIDs = []
        characteristicsDiscoveryFinished = false
        let uuids = mergedServiceUUIDs.isEmpty ? nil : mergedServiceUUIDs
        peripheral.discoverServices(uuids)
    }

    /// 服务发现回调：为每个 service 发起特征发现
    func handleDiscoveredServices(_ peripheral: CBPeripheral, error: Error?) -> Result? {
        if let error {
            didEmitReady = true
            return .failure(error)
        }
        guard let services = peripheral.services, !services.isEmpty else {
            didEmitReady = true
            return .failure(setupError(code: 1, message: "未发现服务"))
        }
        let targetServices = filterServices(services)
        guard !targetServices.isEmpty else {
            didEmitReady = true
            return .failure(setupError(code: 2, message: "未匹配到目标服务"))
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

    /// Notify 订阅状态回调；全部目标 Notify 确认后才产出 ready。
    func handleUpdatedNotificationState(
        peripheral: CBPeripheral,
        for characteristic: CBCharacteristic,
        error: Error?
    ) -> Result? {
        guard !didEmitReady else { return nil }
        let key = ObjectIdentifier(characteristic)
        guard pendingNotifyCharacteristics.contains(key) else { return nil }

        if let error {
            didEmitReady = true
            return .failure(error)
        }
        guard characteristic.isNotifying else {
            didEmitReady = true
            return .failure(setupError(code: 3, message: "Notify 订阅未启用: \(characteristic.uuid)"))
        }
        pendingNotifyCharacteristics.remove(key)
        // 多 Service 并行发现时，某个 Notify 确认可能早于其他 Service 的特征发现回调。
        // 此时只记录该确认；必须同时满足「特征发现全部结束 + pending Notify 为空」才 ready。
        guard characteristicsDiscoveryFinished, pendingNotifyCharacteristics.isEmpty else { return nil }
        didEmitReady = true
        return successResult(peripheral: peripheral)
    }

    // MARK: - Profile

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

    /// 主 Service 才绑定 ready 的 `writeChar`。未配主 serviceUUIDs 时：非附加 Service 都算主，避免「有 supplementary 则谁都不是 primary」。
    private func isPrimaryService(_ service: CBService) -> Bool {
        for supplementary in configuration.supplementaryGattProfiles {
            guard let uuids = supplementary.serviceUUIDs, !uuids.isEmpty else { continue }
            if uuids.contains(where: { BleUUID.matches(service.uuid, $0) }) {
                return false
            }
        }
        guard let serviceUUIDs = configuration.gattProfile.serviceUUIDs, !serviceUUIDs.isEmpty else {
            return true
        }
        return serviceUUIDs.contains { BleUUID.matches(service.uuid, $0) }
    }

    /// 该 Service 对应 profile 下需发现的特征 UUID；nil 表示 discoverCharacteristics(nil) 发现全部。
    private func characteristicsToDiscover(for service: CBService) -> [CBUUID]? {
        let profile = profile(for: service)
        let charUUIDs = [profile.readCharUUID, profile.writeCharUUID, profile.notifyCharUUID].compactMap { $0 }
        return charUUIDs.isEmpty ? nil : charUUIDs
    }

    private var requiredNotifyUUIDs: [CBUUID] {
        var uuids: [CBUUID] = []
        if let primary = configuration.gattProfile.notifyCharUUID {
            uuids.append(primary)
        }
        for profile in configuration.supplementaryGattProfiles {
            if let notify = profile.notifyCharUUID {
                uuids.append(notify)
            }
        }
        return uuids
    }

    // MARK: - Process

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
                pendingNotifyCharacteristics.insert(ObjectIdentifier(characteristic))
                subscribedNotifyUUIDs.append(characteristic.uuid)
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

    /// 所有 service 特征发现完毕，产出 ready 或 error（仅触发一次）；有 pending Notify 时延迟 ready。
    private func finalizeIfNeeded(peripheral: CBPeripheral) -> Result? {
        guard completedServiceCount >= pendingServiceCount, !didEmitReady else { return nil }

        if let setupError {
            didEmitReady = true
            return .failure(setupError)
        }
        if let missingNotifyError = missingRequiredNotifyError() {
            didEmitReady = true
            return .failure(missingNotifyError)
        }
        if configuration.gattProfile.writeCharUUID != nil, writeChar == nil {
            didEmitReady = true
            return .failure(BleError.writeCharacteristicNotFound)
        }

        characteristicsDiscoveryFinished = true

        if pendingNotifyCharacteristics.isEmpty {
            didEmitReady = true
            return successResult(peripheral: peripheral)
        }
        return nil
    }

    private func missingRequiredNotifyError() -> Error? {
        for required in requiredNotifyUUIDs {
            let subscribed = subscribedNotifyUUIDs.contains { BleUUID.matches($0, required) }
            if !subscribed {
                return setupError(code: 4, message: "未找到 Notify 特征: \(required)")
            }
        }
        return nil
    }

    private func successResult(peripheral: CBPeripheral) -> Result {
        guard let service = readyService ?? peripheral.services?.first else {
            return .failure(setupError(code: 5, message: "GATT 就绪时缺少可用 Service"))
        }
        return .ready(writeChar: writeChar, service: service)
    }

    private func setupError(code: Int, message: String) -> NSError {
        NSError(
            domain: "BleGattSetup",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: message]
        )
    }
}
