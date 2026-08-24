//
//  BleUUID.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  Bluetooth UUID 等价比较（16-bit 短 UUID 与 128-bit Base UUID 互认）。

import Foundation
import CoreBluetooth

public enum BleUUID {

    /// 判断两个 `CBUUID` 是否表示同一蓝牙 UUID。
    /// 优先使用 CoreBluetooth 的 `==`；不等时再比较提取的 16-bit 短 UUID。
    public static func matches(_ lhs: CBUUID, _ rhs: CBUUID) -> Bool {
        if lhs == rhs { return true }
        guard let left = short16BitKey(from: lhs), let right = short16BitKey(from: rhs) else {
            return false
        }
        return left == right
    }

    /// 判断 characteristic / service 是否匹配配置 UUID（`nil` 表示不限制）。
    public static func matches(_ actual: CBUUID, configured: CBUUID?) -> Bool {
        guard let configured else { return true }
        return matches(actual, configured)
    }

    /// 从 128-bit Base UUID 字符串提取 16-bit 短 UUID（大写 hex，如 `AF01`）。
    public static func short16BitKey(from uuid: CBUUID) -> String? {
        let value = uuid.uuidString.uppercased()

        // 0000AF01-0000-1000-8000-00805F9B34FB
        if value.hasPrefix("0000"),
           value.hasSuffix("-0000-1000-8000-00805F9B34FB"),
           value.count >= 8 {
            let start = value.index(value.startIndex, offsetBy: 4)
            let end = value.index(start, offsetBy: 4)
            return String(value[start..<end])
        }

        // 00000000-AF01-1000-8000-00805F9B34FB
        if value.hasPrefix("00000000-"),
           value.hasSuffix("-1000-8000-00805F9B34FB"),
           value.count >= 13 {
            let start = value.index(value.startIndex, offsetBy: 9)
            let end = value.index(start, offsetBy: 4)
            return String(value[start..<end])
        }

        return nil
    }
}
