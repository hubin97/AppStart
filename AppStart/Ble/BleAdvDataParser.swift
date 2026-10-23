//
//  BleAdvDataParser.swift
//  AppStart
//
//  Created by hubin.h on 2024/11/26.
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  广播解析：advertisementData → 业务模型，绑定在 BleConfiguration.advParser。

import Foundation
import CoreBluetooth

// MARK: - 协议

/// 广播解析协议；不匹配或字段不全时返回 nil。
public protocol BleAdvDataParser {
    associatedtype ParsedData
    func parse(advertisementData: [String: Any]) -> ParsedData?
}

/// 类型擦除，便于 BleConfiguration 存储异构解析器。
public struct AnyBleAdvDataParser {
    private let _parse: ([String: Any]) -> Any?

    public init<P: BleAdvDataParser>(_ parser: P) {
        _parse = { parser.parse(advertisementData: $0) as Any? }
    }

    public func parse(advertisementData: [String: Any]) -> Any? {
        _parse(advertisementData)
    }
}

// MARK: - 扫描匹配

/// 扫描匹配：parser 解析成功即命中；names 非 nil 时先做 LocalName 全等过滤。
/// LocalName 优先读广播，peripheral.name 仅兜底。
public struct BleParserValidatedMatchingStrategy: BlePeripheralMatching {
    public let names: Set<String>?
    public let parser: AnyBleAdvDataParser

    public init(names: Set<String>? = nil, parser: AnyBleAdvDataParser) {
        self.names = names
        self.parser = parser
    }

    public init<P: BleAdvDataParser>(names: Set<String>? = nil, parser: P) {
        self.init(names: names, parser: AnyBleAdvDataParser(parser))
    }

    public func shouldConnect(to peripheral: CBPeripheral, advertisementData: [String: Any]) -> Bool {
        if let names {
            let name = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? peripheral.name
            guard let name, names.contains(name) else { return false }
        }
        return parser.parse(advertisementData: advertisementData) != nil
    }
}

// MARK: - 内置解析器

/// 解析广播 LocalName。
public struct BlePeripheralNameParser: BleAdvDataParser {
    public typealias ParsedData = String
    public func parse(advertisementData: [String: Any]) -> String? {
        advertisementData[CBAdvertisementDataLocalNameKey] as? String
    }
    public init() {}
}

/// 解析厂商数据为字节数组。
public struct BleManufacturerDataParser: BleAdvDataParser {
    public typealias ParsedData = [UInt8]
    public func parse(advertisementData: [String: Any]) -> [UInt8]? {
        guard let data = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else { return nil }
        return [UInt8](data)
    }
    public init() {}
}

// MARK: - 示例

/// 示例：厂商数据 bytes[3...8] 倒序格式化为 MAC。
public struct BleMACParser: BleAdvDataParser {
    public typealias ParsedData = String
    public func parse(advertisementData: [String: Any]) -> String? {
        guard let bytes = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data,
              bytes.count >= 8 else { return nil }
        let macData = bytes[3...8]
        return [UInt8](macData).reversed().map { String(format: "%02x", $0).uppercased() }.joined(separator: ":")
    }
    public init() {}
}
