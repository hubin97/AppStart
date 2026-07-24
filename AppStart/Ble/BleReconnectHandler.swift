//
//  BleReconnectHandler.swift
//  AppStart
//
//  Copyright © 2025 hubin.h. All rights reserved.
//
//  自动重连处理器：意外断开 / 连接失败时按策略轮询 connect（非 UI Controller）。

import Foundation
import CoreBluetooth

final class BleReconnectHandler {

    private let policy: BleReconnectPolicy
    private let logger: BleLogger
    private var task: Task<Void, Never>?
    private var attempts = 0
    /// 用户主动断开时不触发重连
    private var userInitiatedDisconnect = false

    var onPhaseChange: ((BleReconnectPhase) -> Void)?
    var connect: (() -> Void)?
    var isConnected: (() -> Bool)?

    init(policy: BleReconnectPolicy, logger: BleLogger) {
        self.policy = policy
        self.logger = logger
    }

    func notifyUserDisconnect() {
        userInitiatedDisconnect = true
        stop()
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

    func notifyConnectFailed(peripheral: CBPeripheral) {
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

    /// 按 interval 间隔重试 connect，直到成功或达到 maxAttempts
    private func runLoop() async {
        while !Task.isCancelled {
            if isConnected?() == true {
                notifyConnected()
                return
            }
            guard attempts < policy.maxAttempts else {
                logger.log("达到最大重连次数")
                onPhaseChange?(.stopped(.exhausted))
                task = nil
                return
            }
            attempts += 1
            logger.log("重连尝试 \(attempts)/\(policy.maxAttempts)")
            await MainActor.run {
                self.connect?()
            }
            let nanoseconds = UInt64(policy.interval * 1_000_000_000)
            try? await Task.sleep(nanoseconds: nanoseconds)
        }
    }
}
