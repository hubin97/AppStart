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
    /// 单次失败后，发起下一次重连前的等待时间
    public var retryDelay: TimeInterval
    /// 单次重连等待连接和 GATT 就绪的最长时间
    public var attemptTimeout: TimeInterval

    public init(
        enabled: Bool,
        maxAttempts: Int = 3,
        retryDelay: TimeInterval = 5,
        attemptTimeout: TimeInterval = 15
    ) {
        self.enabled = enabled
        self.maxAttempts = maxAttempts
        self.retryDelay = retryDelay
        self.attemptTimeout = attemptTimeout
    }

    public static let disabled = BleReconnectPolicy(enabled: false)
}

/// ACK 匹配器：判断 Notify 回包是否为当前写指令的应答。
/// 产品协议差异（REQ/ACK、CID、序列号等）应在此实现，写队列不做额外 heuristic。
public protocol BleAckMatcher {
    func matches(command: Data, response: Data) -> Bool
}

/// 按指定字节下标逐位比对 command 与 response。
/// 默认下标 `[0, 1, 3]` 仅作示例；生产环境请在 App 层实现产品专属 `BleAckMatcher`
///（如 Pump 要求 CT=ACK，见 AppTemplate `BlePumpProtocol.swift`）。
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
    /// GATT 发现目标（Service / 特征 UUID）；空 profile 表示发现全部 Service
    public var gattProfile: BleGattProfile
    /// 附加 GATT（多 Service 发现 / 额外 Notify）；附加 Notify / `write(_:to:)` 非主 write 不参与主 ACK 队列
    public var supplementaryGattProfiles: [BleGattProfile]
    public var reconnect: BleReconnectPolicy
    public var writeQueue: BleWriteQueueConfiguration
    public var discoverDescriptors: Bool
    /// 扫描阶段解析广播（MAC 等）；混扫时在 resolve 后调用对应产品的 parser
    public var advParser: AnyBleAdvDataParser?
    public var debugLog: Bool
    public var logTag: String

    public init(
        matching: any BlePeripheralMatching = BleDefaultMatchingStrategy(),
        gattProfile: BleGattProfile = .empty,
        supplementaryGattProfiles: [BleGattProfile] = [],
        reconnect: BleReconnectPolicy = .disabled,
        writeQueue: BleWriteQueueConfiguration = .direct,
        discoverDescriptors: Bool = false,
        advParser: AnyBleAdvDataParser? = nil,
        debugLog: Bool = false,
        logTag: String = "[Ble] "
    ) {
        self.matching = matching
        self.gattProfile = gattProfile
        self.supplementaryGattProfiles = supplementaryGattProfiles
        self.reconnect = reconnect
        self.writeQueue = writeQueue
        self.discoverDescriptors = discoverDescriptors
        self.advParser = advParser
        self.debugLog = debugLog
        self.logTag = logTag
    }

    public init<P: BleAdvDataParser>(
        matching: any BlePeripheralMatching = BleDefaultMatchingStrategy(),
        gattProfile: BleGattProfile = .empty,
        supplementaryGattProfiles: [BleGattProfile] = [],
        reconnect: BleReconnectPolicy = .disabled,
        writeQueue: BleWriteQueueConfiguration = .direct,
        discoverDescriptors: Bool = false,
        parser: P,
        debugLog: Bool = false,
        logTag: String = "[Ble] "
    ) {
        self.init(
            matching: matching,
            gattProfile: gattProfile,
            supplementaryGattProfiles: supplementaryGattProfiles,
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
