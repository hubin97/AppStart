//
//  BleGattProfile.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  连接阶段 GATT 覆盖：Parser 解析子型号后 merge 进 BleConfiguration 快照。

import Foundation
import CoreBluetooth

/// 连接时 GATT 目标；字段为 nil 表示「不指定 / 保留原值」（merge 时）。
public struct BleGattProfile {
    public var serviceUUIDs: [CBUUID]?
    public var readCharUUID: CBUUID?
    public var writeCharUUID: CBUUID?
    public var notifyCharUUID: CBUUID?

    public static let empty = BleGattProfile()

    public init(
        serviceUUIDs: [CBUUID]? = nil,
        readCharUUID: CBUUID? = nil,
        writeCharUUID: CBUUID? = nil,
        notifyCharUUID: CBUUID? = nil
    ) {
        self.serviceUUIDs = serviceUUIDs
        self.readCharUUID = readCharUUID
        self.writeCharUUID = writeCharUUID
        self.notifyCharUUID = notifyCharUUID
    }

    /// 将 overlay 中非空字段覆盖到当前 profile（connect 时 parser 覆盖 config）。
    public func merged(with overlay: BleGattProfile) -> BleGattProfile {
        var result = self
        if let serviceUUIDs = overlay.serviceUUIDs, !serviceUUIDs.isEmpty {
            result.serviceUUIDs = serviceUUIDs
        }
        if let readCharUUID = overlay.readCharUUID {
            result.readCharUUID = readCharUUID
        }
        if let writeCharUUID = overlay.writeCharUUID {
            result.writeCharUUID = writeCharUUID
        }
        if let notifyCharUUID = overlay.notifyCharUUID {
            result.notifyCharUUID = notifyCharUUID
        }
        return result
    }
}

/// App 层解析结果实现此协议，供 `connect` 时 merge GATT 快照。
public protocol BleProvidesGattProfile {
    var bleGattProfile: BleGattProfile { get }
}

extension BleConfiguration {

    /// 将 profile 中非 nil 字段覆盖到配置副本（用于 connect 快照）。
    public func merged(with profile: BleGattProfile?) -> BleConfiguration {
        guard let profile else { return self }
        var copy = self
        copy.gattProfile = gattProfile.merged(with: profile)
        return copy
    }

    /// 从 `parsedData` 提取 `BleProvidesGattProfile` 并 merge。
    public func merged(withParsedData parsedData: Any?) -> BleConfiguration {
        guard let provider = parsedData as? BleProvidesGattProfile else { return self }
        return merged(with: provider.bleGattProfile)
    }
}

extension BleDiscovery {

    /// 混扫 resolve 后的 configuration 与广播解析 GATT 合并结果（连接前应使用此配置）。
    public var effectiveConfiguration: BleConfiguration? {
        configuration?.merged(withParsedData: parsedData)
    }
}
