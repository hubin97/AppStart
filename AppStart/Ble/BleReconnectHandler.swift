//
//  BleReconnectHandler.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  自动重连处理器：意外断开 / 连接失败时按策略轮询 connect（非 UI Controller）。

import Foundation
final class BleReconnectHandler {

    private let policy: BleReconnectPolicy
    private let logger: BleLogger
    private var task: Task<Void, Never>?
    private var attempts = 0
    /// 用户主动断开时不触发重连
    private var userInitiatedDisconnect = false

    var onPhaseChange: ((BleReconnectPhase) -> Void)?
    /// 执行一次完整重连（physical connect → GATT → Notify ready），成功返回 true。
    /// 参数为当前次数和最大次数，供连接状态向业务层公开重连进度。
    var reconnect: ((_ attempt: Int, _ maximumAttempts: Int) async -> Bool)?

    init(policy: BleReconnectPolicy, logger: BleLogger) {
        self.policy = policy
        self.logger = logger
    }

    func notifyUserDisconnect() {
        userInitiatedDisconnect = true
        stop()
    }

    /// 用户后续明确发起新连接时，恢复自动重连资格并清理上一轮计数。
    func prepareForManualConnection() {
        stop()
        userInitiatedDisconnect = false
        attempts = 0
    }

    func notifyConnected() {
        stop()
        attempts = 0
        onPhaseChange?(.stopped(.success))
    }

    /// 意外断开时启动重连循环
    func notifyUnexpectedDisconnect() {
        guard policy.enabled, !userInitiatedDisconnect else { return }
        startIfNeeded()
    }

    func notifyConnectFailed() {
        guard policy.enabled, !userInitiatedDisconnect else { return }
        startIfNeeded()
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func startIfNeeded() {
        guard task == nil else { return }
        attempts = 0
        onPhaseChange?(.started)
        task = Task { [weak self] in
            await self?.runLoop()
        }
    }

    /// 单次失败后等待 retryDelay，再开始下一次重连。
    private func runLoop() async {
        while attempts < policy.maxAttempts, !Task.isCancelled {
            attempts += 1
            logger.log("重连尝试 \(attempts)/\(policy.maxAttempts)")
            if await reconnect?(attempts, policy.maxAttempts) == true {
                notifyConnected()
                return
            }
            guard !Task.isCancelled, attempts < policy.maxAttempts else { break }
            let nanoseconds = UInt64(policy.retryDelay * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
        guard !Task.isCancelled else { return }
        logger.log("达到最大重连次数")
        onPhaseChange?(.stopped(.exhausted))
        task = nil
    }
}
