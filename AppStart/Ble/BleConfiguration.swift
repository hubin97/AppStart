//
//  BleConfiguration.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  单款产品的完整蓝牙协议配置：匹配、GATT、写队列、重连、广播解析。

import Foundation
import CoreBluetooth

/// 自动重连策略（意外断开 / 连接失败时由 BleReconnectHandler 执行）
public struct BleReconnectPolicy {
    public var enabled: Bool
    public var maxAttempts: Int
    public var interval: TimeInterval

    public init(enabled: Bool, maxAttempts: Int = 3, interval: TimeInterval = 5) {
        self.enabled = enabled
        self.maxAttempts = maxAttempts
        self.interval = interval
    }

    public static let disabled = BleReconnectPolicy(enabled: false)
}

/// ACK 匹配器：判断 Notify 回包是否为当前写指令的应答。
public protocol BleAckMatcher {
    func matches(command: Data, response: Data) -> Bool
}

/// 按指定字节下标逐位比对 command 与 response。
public struct BleByteAckMatcher: BleAckMatcher {
    public let indices: [Int]

    public init(indices: [Int] = [0, 1, 3]) {
        self.indices = indices
    }

    public func matches(command: Data, response: Data) -> Bool {
        indices.allSatisfy { index in
            index < command.count && index < response.count && command[index] == response[index]
        }
    }
}

/// 写指令派发模式
public enum BleWriteQueueConfiguration {
    /// 直接 writeValue，不等待 ACK
    case direct
    /// 串行写队列：按优先级排队，通过 Notify ACK 确认后发送下一条
    case serialized(
        ackMatcher: any BleAckMatcher,
        defaultTimeout: TimeInterval,
        order: BlePriorityQueue<BleWriteCommand>.Order
    )
}

/// 单款产品的完整协议配置（匹配 + GATT + 写队列 + 重连 + 广播解析）。
public struct BleConfiguration {
    /// 扫描阶段过滤外设的匹配策略
    public var matching: any BlePeripheralMatching
    /// 连接后发现的目标 Service UUID 列表（仅 GATT 阶段使用，不用于系统扫描过滤）
    public var serviceUUIDs: [CBUUID]
    /// GATT 读特征；发现后自动 readValue
    public var readCharUUID: CBUUID?
    /// GATT 写特征；`write(_:)` 目标
    public var writeCharUUID: CBUUID?
    /// GATT Notify 特征；发现后 setNotifyValue(true)
    public var notifyCharUUID: CBUUID?
    public var reconnect: BleReconnectPolicy
    public var writeQueue: BleWriteQueueConfiguration
    public var discoverDescriptors: Bool
    /// 扫描阶段解析广播（MAC 等）；混扫时在 resolve 后调用对应产品的 parser
    public var advParser: AnyBleAdvDataParser?
    public var debugLog: Bool
    public var logTag: String

    public init(
        matching: any BlePeripheralMatching = BleDefaultMatchingStrategy(),
        serviceUUIDs: [CBUUID] = [],
        readCharUUID: CBUUID? = nil,
        writeCharUUID: CBUUID? = nil,
        notifyCharUUID: CBUUID? = nil,
        reconnect: BleReconnectPolicy = .disabled,
        writeQueue: BleWriteQueueConfiguration = .direct,
        discoverDescriptors: Bool = false,
        advParser: AnyBleAdvDataParser? = nil,
        debugLog: Bool = false,
        logTag: String = "[Ble] "
    ) {
        self.matching = matching
        self.serviceUUIDs = serviceUUIDs
        self.readCharUUID = readCharUUID
        self.writeCharUUID = writeCharUUID
        self.notifyCharUUID = notifyCharUUID
        self.reconnect = reconnect
        self.writeQueue = writeQueue
        self.discoverDescriptors = discoverDescriptors
        self.advParser = advParser
        self.debugLog = debugLog
        self.logTag = logTag
    }

    public init<P: BleAdvDataParser>(
        matching: any BlePeripheralMatching = BleDefaultMatchingStrategy(),
        serviceUUIDs: [CBUUID] = [],
        readCharUUID: CBUUID? = nil,
        writeCharUUID: CBUUID? = nil,
        notifyCharUUID: CBUUID? = nil,
        reconnect: BleReconnectPolicy = .disabled,
        writeQueue: BleWriteQueueConfiguration = .direct,
        discoverDescriptors: Bool = false,
        parser: P,
        debugLog: Bool = false,
        logTag: String = "[Ble] "
    ) {
        self.init(
            matching: matching,
            serviceUUIDs: serviceUUIDs,
            readCharUUID: readCharUUID,
            writeCharUUID: writeCharUUID,
            notifyCharUUID: notifyCharUUID,
            reconnect: reconnect,
            writeQueue: writeQueue,
            discoverDescriptors: discoverDescriptors,
            advParser: AnyBleAdvDataParser(parser),
            debugLog: debugLog,
            logTag: logTag
        )
    }

    public func matches(peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        matching.shouldConnect(to: peripheral, advertisementData: advertisementData)
    }

    public func parseAdvertisement(_ advertisementData: [String: Any]) -> Any? {
        advParser?.parse(advertisementData: advertisementData)
    }
}
