//
//  ConnectivityCenter.swift
//  AppStart
//
//  网络连通性统一入口。

import CoreTelephony
import Foundation

/**
 网络连通性统一入口（L1 链路 / L2 路径 / L3 互联网探测 + 蜂窝数据策略）。

 调用示例：

 // 1. 路径状态（L1+L2，不发起 HTTP）
 let snap = ConnectivityCenter.shared.status()
 snap.canAttemptRequest   // 路径可用，可尝试请求
 snap.summaryText         // UI 文案

 // 2. 含 L3 探测（登录/支付等关键操作前）
 Task {
     let full = await ConnectivityCenter.shared.status(.validated())
     full.isInternetReady   // 路径 OK 且探测通过
 }

 // 3. 路径变化监听
 Task {
     for await snap in ConnectivityCenter.shared.monitor() {
         label.text = snap.summaryText
     }
 }

 // 4. 蜂窝/WLAN 数据策略（设置 → 蜂窝网络 → 本 App）
 Task {
     for await allowed in ConnectivityCenter.shared.monitorCellularDataPolicy() {
         // allowed == true 表示未受限
     }
 }

 // 5. 强制重新探测（**按需调用**，无后台轮询；上线前请替换 validationURL）
 ConnectivityCenter.shared.validationURL = URL(string: "https://api.example.com/health")!
 let forced = await ConnectivityCenter.shared.status(.validated(force: true))
 // forced.validation → .available / .unavailable / .captivePortal

 注意：`monitor()` 仅监听 L1+L2；快照中的 validation 为上次 `.validated` 缓存。
 若需在「网络恢复」时重新探测，请在 monitor 回调里调用 `await status(.validated())`。

 详细说明见 `CONNECTIVITY_README.md`
 */
public final class ConnectivityCenter: @unchecked Sendable {

    public static let shared = ConnectivityCenter()

    /// 互联网探测 URL。
    /// 默认与 iOS 一致使用 `captive.apple.com`；**上线前请改为业务 `/health` 等轻量接口**。
    public var validationURL = NetworkValidator.defaultURL

    /// 两次 L3 探测之间的最短间隔（秒），默认 30。
    ///
    /// **不是后台轮询间隔**——模块不会定时自动发 HTTP；仅当 `status(.validated)` 时才会探测。
    /// 此值用于限频：间隔内重复调用且 `force == false` 时返回缓存，避免频繁打探测 URL。
    public var validationDebounce: TimeInterval = 30

    private let pathMonitor = NetworkPathMonitor()
    private var cellularData: CTCellularData?
    private var lastValidation: InternetValidation = .notChecked
    private var lastValidationDate: Date?
    private let lock = NSLock()

    private init() {
        pathMonitor.startIfNeeded()
    }

    /// L1+L2 路径状态（同步，不发起 HTTP）。等价于 `await status(.path)`。
    public func status() -> ConnectivitySnapshot {
        pathStatus()
    }

    /// 连通性状态（统一入口）。
    ///
    /// - `.path`：L1+L2，不发起 HTTP（同步路径可用 `status()`）。
    /// - `.validated`：L1+L2+L3，按需 HTTP 探测；`force == false` 时受 debounce 限频。
    public func status(_ level: ConnectivityLevel) async -> ConnectivitySnapshot {
        switch level {
        case .path:
            return pathStatus()
        case .validated(let force):
            let validation = await performValidation(force: force)
            let snap = pathStatus()
            return ConnectivitySnapshot(
                link: snap.link,
                pathStatus: snap.pathStatus,
                isExpensive: snap.isExpensive,
                isConstrained: snap.isConstrained,
                validation: validation
            )
        }
    }

    /// 路径变化监听（L1+L2，**不含** L3 HTTP 探测）。
    ///
    /// 回调中的 `validation` 为上次 `status(.validated)` 的缓存；路径切换不会自动重新探测。
    /// 若需在 Wi‑Fi/蜂窝恢复时更新互联网状态，请在回调里按需调用 `await status(.validated())`。
    public func monitor() -> AsyncStream<ConnectivitySnapshot> {
        AsyncStream { continuation in
            let task = Task {
                for await path in pathMonitor.monitor() {
                    let snap = NetworkPathMonitor.snapshot(from: path, validation: self.cachedValidation())
                    continuation.yield(snap)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    /// 监听 App 蜂窝/WLAN 数据策略（`true` 表示未受限）。
    public func monitorCellularDataPolicy() -> AsyncStream<Bool> {
        AsyncStream { continuation in
            if cellularData == nil {
                cellularData = CTCellularData()
            }
            cellularData?.cellularDataRestrictionDidUpdateNotifier = { state in
                continuation.yield(state == .notRestricted)
            }
        }
    }

    /// 当前蜂窝/WLAN 数据策略。
    public func cellularDataPolicy() -> CellularDataPolicy {
        if cellularData == nil {
            cellularData = CTCellularData()
        }
        guard let state = cellularData?.restrictedState else { return .unknown }
        switch state {
        case .notRestricted:
            return .unrestricted
        case .restricted:
            return .restricted
        case .restrictedStateUnknown:
            return .unknown
        @unknown default:
            return .unknown
        }
    }

    // MARK: - Private

    private func pathStatus() -> ConnectivitySnapshot {
        pathMonitor.currentSnapshot()
    }

    /// L3 HTTP HEAD，**按需触发，无后台轮询**。
    private func performValidation(force: Bool) async -> InternetValidation {
        let current = pathStatus()
        guard current.canAttemptRequest else {
            storeValidation(.unavailable)
            return .unavailable
        }

        if !force, let cached = debouncedValidation() {
            return cached
        }

        let result = await NetworkValidator.validate(url: validationURL)
        storeValidation(result)
        return result
    }

    private func cachedValidation() -> InternetValidation {
        lock.lock()
        defer { lock.unlock() }
        return lastValidation
    }

    private func storeValidation(_ validation: InternetValidation) {
        lock.lock()
        lastValidation = validation
        lastValidationDate = Date()
        lock.unlock()
    }

    private func debouncedValidation() -> InternetValidation? {
        lock.lock()
        defer { lock.unlock() }
        guard lastValidation != .notChecked,
              let date = lastValidationDate,
              Date().timeIntervalSince(date) < validationDebounce else {
            return nil
        }
        return lastValidation
    }
}
