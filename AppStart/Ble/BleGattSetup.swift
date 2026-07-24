//
//  BleGattSetup.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  GATT 自动发现：Service → Characteristic → 订阅 Notify / 定位写特征。
//  所有目标 Service 的特征发现完成后，一次性回调 ready。

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

    /// 入口：按 configuration.serviceUUIDs 发现服务（空则发现全部）
    func beginServiceDiscovery(on peripheral: CBPeripheral) {
        pendingServiceCount = 0
        completedServiceCount = 0
        writeChar = nil
        readyService = nil
        setupError = nil
        didEmitReady = false
        let uuids = configuration.serviceUUIDs.isEmpty ? nil : configuration.serviceUUIDs
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
        pendingServiceCount = services.count
        let charUUIDs = [configuration.readCharUUID, configuration.writeCharUUID, configuration.notifyCharUUID].compactMap { $0 }
        for service in services {
            if charUUIDs.isEmpty {
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

    /// 遍历特征：read → setNotify → 记录 writeChar
    private func process(characteristics: [CBCharacteristic], peripheral: CBPeripheral, service: CBService) {
        for characteristic in characteristics {
            if characteristic.properties.contains(.read),
               configuration.readCharUUID == nil || characteristic.uuid == configuration.readCharUUID {
                logger.log("读取特征: \(characteristic.uuid)")
                peripheral.readValue(for: characteristic)
            }
            if characteristic.properties.contains(.notify),
               configuration.notifyCharUUID == nil || characteristic.uuid == configuration.notifyCharUUID {
                logger.log("订阅通知: \(characteristic.uuid)")
                peripheral.setNotifyValue(true, for: characteristic)
            }
            if characteristic.properties.contains(.write) || characteristic.properties.contains(.writeWithoutResponse),
               configuration.writeCharUUID == nil || characteristic.uuid == configuration.writeCharUUID {
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
        if configuration.writeCharUUID != nil, writeChar == nil {
            return Result(writeChar: nil, readyService: nil, error: BleError.writeCharacteristicNotFound)
        }
        return Result(writeChar: writeChar, readyService: readyService ?? peripheral.services?.first, error: nil)
    }
}
