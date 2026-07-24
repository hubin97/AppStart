//
//  BleProductRegistry.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  多产品混扫：compositeMatching（OR 过滤）与 resolve（定案，register 顺序）职责不同。

import Foundation
import CoreBluetooth

/// 多款产品 OR 匹配：任一 configuration 命中即视为「可能是自家设备」（第一道关）。
public struct BleCompositeMatchingStrategy: BlePeripheralMatching {
    private let configurations: [BleConfiguration]

    public init(configurations: [BleConfiguration]) {
        self.configurations = configurations
    }

    public func shouldConnect(to peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        configurations.contains { $0.matches(peripheral: peripheral, advertisementData: advertisementData) }
    }
}

extension Array where Element == BleConfiguration {

    /// 混扫 matching 合并为 OR（`scan(products:)` 时写入 activeScanConfiguration）
    public var compositeMatching: BleCompositeMatchingStrategy {
        BleCompositeMatchingStrategy(configurations: self)
    }

    /// 定案：按 register 顺序取首个命中的 configuration（决定 advParser 与 connect 协议）
    public func resolve(
        peripheral: CBPeripheral,
        advertisementData: [String: Any]
    ) -> BleConfiguration? {
        first { $0.matches(peripheral: peripheral, advertisementData: advertisementData) }
    }
}
