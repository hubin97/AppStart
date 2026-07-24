//
//  BleWriteCommandQueue.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  串行写指令队列：按优先级排队，通过 Notify ACK 或 write 确认推进下一条。
//  对应 BleWriteQueueConfiguration.serialized 模式。

import Foundation
import CoreBluetooth

//  状态机：enqueue → processNext（单条 in-flight）→ ACK/timeout/fail → 下一条
//  withoutResponse 等 Notify ACK；withResponse 可在 write 回调完成。

final class BleWriteCommandQueue {

    private let ackMatcher: any BleAckMatcher
    private let defaultTimeout: TimeInterval
    private let order: BlePriorityQueue<BleWriteCommand>.Order
    private var queue = BlePriorityQueue<BleWriteCommand>()
    /// 每条指令独立的超时 Task
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]
    /// requestId → 挂起等待 ACK 的 continuation
    private var pendingContinuations: [UUID: CheckedContinuation<Void, Error>] = [:]
    private let lock = NSLock()
    private let logger: BleLogger
    var onTimeout: ((BleWriteCommand) -> Void)?

    init(
        ackMatcher: any BleAckMatcher,
        defaultTimeout: TimeInterval,
        order: BlePriorityQueue<BleWriteCommand>.Order,
        logger: BleLogger
    ) {
        self.ackMatcher = ackMatcher
        self.defaultTimeout = defaultTimeout
        self.order = order
        self.queue = BlePriorityQueue(order: order)
        self.logger = logger
    }

    /// 入队并挂起，直到 ACK 确认或超时/失败。
    func enqueue(_ command: BleWriteCommand) async throws {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            queue.enqueue(command)
            pendingContinuations[command.requestId] = continuation
            lock.unlock()
            processNextIfNeeded()
        }
    }

    /// Notify 回包：用 ackMatcher 判断是否为队首指令的应答
    func handleCharacteristicUpdate(_ data: Data) {
        lock.lock()
        guard let head = queue.peek(), ackMatcher.matches(command: head.data, response: data) else {
            lock.unlock()
            return
        }
        completeHead(response: data, source: "notify")
        lock.unlock()
        processNextIfNeeded()
    }

    /// writeValue 回调：withResponse 模式在此完成；withoutResponse 仍等 Notify ACK
    func handleWriteConfirmation(for characteristic: CBCharacteristic, error: Error?) {
        lock.lock()
        guard let head = queue.peek(), head.writeChar.uuid == characteristic.uuid else {
            lock.unlock()
            return
        }
        if let error {
            failHead(with: BleError.writeFailed(error))
        } else if head.writeType == .withResponse {
            completeHead(source: "writeResponse")
        }
        lock.unlock()
        processNextIfNeeded()
    }

    /// 断开连接时清空队列并取消所有挂起 continuation
    func cancelAll() {
        lock.lock()
        timeoutTasks.values.forEach { $0.cancel() }
        timeoutTasks.removeAll()
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        queue = BlePriorityQueue(order: order)
        lock.unlock()
        continuations.values.forEach { $0.resume(throwing: BleError.cancelled) }
    }

    /// 发送队首指令（同一时刻仅一条 in-flight）
    private func processNextIfNeeded() {
        lock.lock()
        guard let command = queue.peek(), timeoutTasks[command.requestId] == nil else {
            lock.unlock()
            return
        }
        lock.unlock()

        let type: CBCharacteristicWriteType = command.writeType
        logger.log("写入指令 \(command.requestId): \(command.data.hexString)")
        command.peripheral.writeValue(command.data, for: command.writeChar, type: type)

        if type == .withoutResponse {
            // withoutResponse 依赖 notify ACK；超时兜底
            scheduleTimeout(for: command)
            return
        }

        scheduleTimeout(for: command)
    }

    private func scheduleTimeout(for command: BleWriteCommand) {
        let task = Task { [weak self] in
            let nanoseconds = UInt64(command.timeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.handleTimeout(command)
        }
        lock.lock()
        timeoutTasks[command.requestId] = task
        lock.unlock()
    }

    private func handleTimeout(_ command: BleWriteCommand) {
        lock.lock()
        guard let head = queue.peek(), head.requestId == command.requestId else {
            lock.unlock()
            return
        }
        timeoutTasks.removeValue(forKey: command.requestId)
        queue.dequeue()
        let continuation = pendingContinuations.removeValue(forKey: command.requestId)
        lock.unlock()

        logger.log("写入超时: \(command.requestId)")
        onTimeout?(command)
        continuation?.resume(throwing: BleError.writeTimeout)
        processNextIfNeeded()
    }

    private func completeHead(response: Data? = nil, source: String) {
        guard let head = queue.dequeue() else { return }
        timeoutTasks.removeValue(forKey: head.requestId)?.cancel()
        let continuation = pendingContinuations.removeValue(forKey: head.requestId)
        if let response {
            logger.log("指令 ACK(\(source)) \(head.requestId): \(response.hexString)")
        } else {
            logger.log("指令 ACK(\(source)) \(head.requestId)")
        }
        continuation?.resume()
    }

    private func failHead(with error: Error) {
        guard let head = queue.dequeue() else { return }
        timeoutTasks.removeValue(forKey: head.requestId)?.cancel()
        let continuation = pendingContinuations.removeValue(forKey: head.requestId)
        logger.log("指令失败 \(head.requestId): \(error.localizedDescription)")
        continuation?.resume(throwing: error)
    }
}

private extension Data {
    var hexString: String {
        map { String(format: "%02X", $0) }.joined(separator: " ")
    }
}
