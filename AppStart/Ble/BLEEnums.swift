//
//  BleEnums.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  BLE 模块公共类型：状态枚举、发现结果、错误码。

import Foundation
import CoreBluetooth

public enum BleScanState {
    /// `startScanning` 已调用
    case started
    /// `stopScanning` 已调用（超时、手动 stop 或 stream 取消）
    case stopped
}

public enum BleDisconnectReason {
    case userInitiated
    case unexpected(Error)
}

/// GATT 通道就绪后的关键信息（服务已发现、Notify 已订阅、写特征已定位）
public struct BleChannelReadyInfo {
    public let peripheral: CBPeripheral
    public let service: CBService
}

/// 单设备连接状态机
public enum BlePeripheralState {
    case connecting       // 正在建立物理连接
    case connected        // 物理连接已建立，GATT 发现中
    case ready(BleChannelReadyInfo)  // 可读写
    case disconnected(BleDisconnectReason)
    case failed(Error?)
    case timedOut
}

public struct BlePeripheralData {
    /// CoreBluetooth 原始广播字典（含 LocalName、ManufacturerData 等）
    public var advertisementData: [String: Any]
    public var rssi: NSNumber
}

/// 扫描发现的一条记录，携带命中的协议配置与解析结果
public struct BleDiscovery {
    public let peripheral: CBPeripheral
    public let advertisement: BlePeripheralData
    public let parsedData: Any?
    /// 混扫/单产品扫描时命中的协议配置；临时扫描（无注册）时为 nil
    public let configuration: BleConfiguration?

    /// 展示名：广播 LocalName → peripheral.name（仅 UI / 日志，不参与 matching 与 yield 门禁）
    public var displayName: String? {
        if let localName = advertisement.advertisementData[CBAdvertisementDataLocalNameKey] as? String,
           !localName.isEmpty {
            return localName
        }
        if let name = peripheral.name, !name.isEmpty {
            return name
        }
        return nil
    }

    public init(
        peripheral: CBPeripheral,
        advertisement: BlePeripheralData,
        parsedData: Any? = nil,
        configuration: BleConfiguration? = nil
    ) {
        self.peripheral = peripheral
        self.advertisement = advertisement
        self.parsedData = parsedData
        self.configuration = configuration
    }
}

/// Notify 特征值变更；由 `characteristicUpdates()` 订阅，数据源为 `didUpdateValueFor`。
public struct BleCharacteristicUpdate {
    public let peripheral: CBPeripheral
    public let characteristic: CBCharacteristic
    public let data: Data
}

public enum BleReconnectResult {
    case success
    case exhausted
}

public enum BleReconnectPhase {
    case started
    case stopped(BleReconnectResult)
}

public enum BleError: Error {
    case bluetoothUnavailable(CBManagerState)
    case notConnected
    case writeCharacteristicNotFound
    case connectionTimeout
    case connectionFailed(Error?)
    case channelSetupFailed(Error)   // GATT 发现失败
    case writeTimeout                // 写队列 ACK 超时
    case writeFailed(Error)
    case cancelled
    case configurationNotResolved   // discovery 未携带命中的 configuration
}
