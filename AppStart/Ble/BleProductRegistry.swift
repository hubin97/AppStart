//
//  BleProductRegistry.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  多产品混扫：按配置顺序匹配并确定具体产品配置。

import Foundation
import CoreBluetooth

extension Array where Element == BleConfiguration {

    /// 定案：按数组顺序取首个命中的 configuration（决定 advParser 与 connect 协议）
    public func resolve(
        peripheral: CBPeripheral,
        advertisementData: [String: Any]
    ) -> BleConfiguration? {
        first { $0.matches(peripheral: peripheral, advertisementData: advertisementData) }
    }
}
