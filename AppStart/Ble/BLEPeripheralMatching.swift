//
//  BlePeripheralMatching.swift
//  AppStart
//
//  Created by hubin.h on 2024/11/26.
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  扫描阶段外设过滤；全量扫描后由 matching 决定是否纳入结果。

import Foundation
import CoreBluetooth

// MARK: - 协议

/// 扫描回调中的第一道过滤。
public protocol BlePeripheralMatching {
    func shouldConnect(to peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool
}

extension BlePeripheralMatching {
    func shouldConnect(to peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        true
    }
}

// MARK: - 内置策略

/// 不过滤，接受所有外设。
public struct BleDefaultMatchingStrategy: BlePeripheralMatching {
    public init() {}
    public func shouldConnect(to peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        true
    }
}

/// 名称前缀或厂商数据前缀匹配；不做完整协议校验（多产品推荐 `BleParserValidatedMatchingStrategy`）。
public struct BlePrefixMatchingStrategy: BlePeripheralMatching {
    public enum Mode {
        /// 名称前缀匹配
        case namePrefix(String)
        /// 厂商数据（Manufacturer Data）前缀匹配
        case manufacturerDataPrefix([UInt8])
    }
    private var mode: Mode
    public init(mode: Mode) {
        self.mode = mode
    }
    public func shouldConnect(to peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        switch mode {
        case .namePrefix(let prefix):
            return (peripheral.name ?? "").hasPrefix(prefix)
        case .manufacturerDataPrefix(let bytes):
            guard let manufacturerData = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return false }
            guard bytes.count <= manufacturerData.count else { return false }
            return manufacturerData.starts(with: bytes)
        }
    }
}
