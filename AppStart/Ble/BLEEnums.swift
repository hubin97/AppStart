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

/// BLE 模块错误。业务层可用 `catch BleError.xxx` 区分场景。
public enum BleError: Error {
    /// 蓝牙不可用。
    /// 场景：Central 未开机 / 未授权 / 不支持等（携带当时 `CBManagerState`）。
    case bluetoothUnavailable(CBManagerState)

    /// 当前无可用连接。
    /// 场景：在未建立连接或连接已断开时调用写/读等依赖通道的操作。
    case notConnected

    /// 未找到可写特征。
    /// 场景：GATT 发现完成但配置的 `writeCharUUID` 不存在；或尚未 ready 就调用 `write`。
    case writeCharacteristicNotFound

    /// 连接超时。 BLE 建连 + GATT ready 常见默认在 8～15 秒；
    /// 场景：`connect` 在默认 15s（或调用方传入的 `timeout`）内未进入 `.ready`。
    case connectionTimeout

    /// 物理连接失败。
    /// 场景：`centralManager(_:didFailToConnect:error:)`；可选附带系统 `Error`。
    case connectionFailed(Error?)

    /// GATT 通道建立失败。
    /// 场景：服务/特征发现出错，或 Notify 订阅等就绪流程失败。
    case channelSetupFailed(Error)

    /// 写指令 ACK 超时。
    /// 场景：`writeQueue == .serialized` 时，发出的写在 `timeout` 内未匹配到 Notify ACK。
    case writeTimeout

    /// 底层写失败。
    /// 场景：`didWriteValueFor` 回报错误，或写队列处理 in-flight 指令失败。
    case writeFailed(Error)

    /// 操作被取消。
    /// 场景：断开连接时清空写队列；或任务/continuation 被主动取消。
    case cancelled

    /// 无法解析产品配置。
    /// 场景：`BleSession.connect(discovery:)` 时 `discovery.configuration == nil`
    ///（未走 Session 扫描/未注册产品，或临时扫描未命中协议）。
    case configurationNotResolved
}
