//
//  BleWriteCommand.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  写队列中的单条指令模型，支持优先级排序。

import Foundation
import CoreBluetooth

/// 一条待发送的 BLE 写指令，由 BleWriteCommandQueue 串行调度。
public struct BleWriteCommand: Comparable, Equatable {
    public static func < (lhs: BleWriteCommand, rhs: BleWriteCommand) -> Bool {
        lhs.priority < rhs.priority
    }

    public let peripheral: CBPeripheral
    public let writeChar: CBCharacteristic
    public let data: Data
    public let timeout: TimeInterval
    /// 优先级，数值越大越优先（配合 BlePriorityQueue.Order 排序）
    public let priority: Int
    public let writeType: CBCharacteristicWriteType
    public let requestId: UUID

    public init(
        peripheral: CBPeripheral,
        writeChar: CBCharacteristic,
        data: Data,
        writeType: CBCharacteristicWriteType,
        timeout: TimeInterval,
        priority: Int = 0
    ) {
        self.requestId = UUID()
        self.peripheral = peripheral
        self.writeChar = writeChar
        self.data = data
        self.writeType = writeType
        self.timeout = timeout
        self.priority = priority
    }

    public static func == (lhs: BleWriteCommand, rhs: BleWriteCommand) -> Bool {
        lhs.requestId == rhs.requestId
    }
}
