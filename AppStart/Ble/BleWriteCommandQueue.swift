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
    /// 传输细节由 Connection 注入：队列只负责顺序/ACK，MTU 与背压由统一发送路径处理。
    private let send: (BleWriteCommand) async throws -> Void
    private var queue = BlePriorityQueue<BleWriteCommand>()
    /// 每条指令独立的超时 Task
    private var timeoutTasks: [UUID: Task<Void, Never>] = [:]
    /// requestId → 挂起等待 ACK 的 continuation
    private var pendingContinuations: [UUID: CheckedContinuation<BleWriteAck?, Error>] = [:]
    private let lock = NSLock()
    /// 正在等待传输层获得发送许可的指令；此阶段尚未启动 ACK timeout。
    private var sendingRequestID: UUID?
    private let logger: BleLogger
    var onTimeout: ((BleWriteCommand) -> Void)?

    init(
        ackMatcher: any BleAckMatcher,
        defaultTimeout: TimeInterval,
        order: BlePriorityQueue<BleWriteCommand>.Order,
        logger: BleLogger,
        send: @escaping (BleWriteCommand) async throws -> Void
    ) {
        self.ackMatcher = ackMatcher
        self.defaultTimeout = defaultTimeout
        self.order = order
        self.queue = BlePriorityQueue(order: order)
        self.logger = logger
        self.send = send
    }

    /// 入队并挂起，直到 ACK 确认或超时/失败；返回匹配到的 Notify ACK  payload。
    @discardableResult
    func enqueue(_ command: BleWriteCommand) async throws -> BleWriteAck? {
        try await withCheckedThrowingContinuation { continuation in
            lock.lock()
            queue.enqueue(command)
            pendingContinuations[command.requestId] = continuation
            lock.unlock()
            processNextIfNeeded()
        }
    }

    /// Notify 回包：仅当 `ackMatcher` 判定为队首指令应答时完成该条写。
    func handleCharacteristicUpdate(_ data: Data) {
        lock.lock()
        guard let head = queue.peek() else {
            lock.unlock()
            return
        }
        guard ackMatcher.matches(command: head.data, response: data) else {
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
        guard let head = queue.peek(), BleUUID.matches(characteristic.uuid, head.writeChar.uuid) else {
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
        sendingRequestID = nil
        let continuations = pendingContinuations
        pendingContinuations.removeAll()
        queue = BlePriorityQueue(order: order)
        lock.unlock()
        continuations.values.forEach { $0.resume(throwing: BleError.cancelled) }
    }

    /// 发送队首指令（同一时刻仅一条 in-flight）
    private func processNextIfNeeded() {
        lock.lock()
        guard let command = queue.peek(),
              timeoutTasks[command.requestId] == nil,
              sendingRequestID == nil else {
            lock.unlock()
            return
        }
        sendingRequestID = command.requestId
        lock.unlock()

        Task { [weak self] in
            guard let self else { return }
            do {
                try await send(command)
            } catch {
                handleSendFailure(command, error: error)
                return
            }
            handleDidSend(command)
        }
    }

    /// 背压等待不计入协议 ACK timeout；真正交给 CoreBluetooth 后才开始计时。
    private func handleDidSend(_ command: BleWriteCommand) {
        lock.lock()
        guard sendingRequestID == command.requestId else {
            lock.unlock()
            return
        }
        sendingRequestID = nil
        let isStillHead = queue.peek()?.requestId == command.requestId
        lock.unlock()
        if isStillHead {
            scheduleTimeout(for: command)
        }
    }

    private func handleSendFailure(_ command: BleWriteCommand, error: Error) {
        lock.lock()
        guard sendingRequestID == command.requestId,
              queue.peek()?.requestId == command.requestId else {
            lock.unlock()
            return
        }
        sendingRequestID = nil
        failHead(with: error)
        lock.unlock()
        processNextIfNeeded()
    }

    private func scheduleTimeout(for command: BleWriteCommand) {
        let task = Task { [weak self] in
            let nanoseconds = UInt64(command.timeout * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
            guard !Task.isCancelled else { return }
            self?.handleTimeout(command)
        }
        lock.lock()
        guard queue.peek()?.requestId == command.requestId,
              timeoutTasks[command.requestId] == nil else {
            lock.unlock()
            task.cancel()
            return
        }
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
        continuation?.resume(returning: BleWriteAck(request: head.data, response: response ?? Data()))
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
