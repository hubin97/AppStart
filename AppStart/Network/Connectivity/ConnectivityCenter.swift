//
//  ConnectivityCenter.swift
//  AppStart
//
//  网络连通性统一入口。

import CoreTelephony
import Foundation

// MARK: - 便捷全局流（对齐 `connectedToInternet()`，无 Rx）

/**
 监听网络路径变化（L1 链路 + L2 路径）。

 - 推送 Wi‑Fi / 蜂窝等路径是否可用，以及链路类型
 - **不会**发 HTTP；不含 L3 互联网探测
 - 无 Rx；对应旧 API：`connectedToInternet()`（`Network/Utils`，Alamofire + Rx）
 - 等价于：`ConnectivityCenter.shared.monitor()`

 ```swift
 // 旧（Rx）
 connectedToInternet().subscribe(onNext: { status in ... })

 // 新（AsyncStream）
 Task {
     for await snap in connectivityUpdates() {
         // snap.canAttemptRequest  — 路径是否可尝试请求
         // snap.link               — wifi / cellular / none …
         // snap.summaryText        — UI 文案
     }
 }
 ```

 若还需确认「真能上网」，在回调里按需：`await ConnectivityCenter.shared.status(.validated())`。
 */
public func connectivityUpdates() -> AsyncStream<ConnectivitySnapshot> {
    ConnectivityCenter.shared.monitor()
}

/**
 监听本 App 的无线数据策略变化（`CTCellularData`）。

 - 中国大陆设置多为「无线数据」三档：关闭 / 无线局域网 / 无线局域网与蜂窝数据
 - 海外设置多为蜂窝数据开/关；关蜂窝时 Wi‑Fi 通常仍可用
 - API 只能区分「未受限 / 受限 / 未知」：大陆前两档都会落在 `.restricted`
 - 等价于：`ConnectivityCenter.shared.monitorCellularDataPolicy()`

 ```swift
 Task {
     for await policy in cellularDataPolicyUpdates() {
         let hint = policy.accessHint(with: ConnectivityCenter.shared.status())
         // hint.displayText；「关闭」vs「仅 WLAN」最终以请求是否成功为准
     }
 }
 ```
 */
public func cellularDataPolicyUpdates() -> AsyncStream<CellularDataPolicy> {
    ConnectivityCenter.shared.monitorCellularDataPolicy()
}

// MARK: - ConnectivityCenter

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

 // 3. 路径变化监听（推荐用顶部全局函数）
 Task {
     for await snap in connectivityUpdates() {
         label.text = snap.summaryText
     }
 }

 // 4. 无线数据策略流（大陆三档 / 海外蜂窝开关；API 仅 coarse 三态）
 Task {
     for await policy in cellularDataPolicyUpdates() {
         let hint = policy.accessHint(with: ConnectivityCenter.shared.status())
         // policy.displayText / hint.displayText
     }
 }

 // 5. 策略 + 路径一次性联合读取（与上面对等，非流）
 let policy = ConnectivityCenter.shared.cellularDataPolicy()
 let hint = ConnectivityCenter.shared.wirelessDataAccessHint()
 // 等价于：policy.accessHint(with: ConnectivityCenter.shared.status())
 // hint → .unrestricted / .restrictedNonCellularPath / .restrictedLikelyNoAccess
 // 「关闭」vs「仅 WLAN」最终以业务请求或 status(.validated()) 为准

 // 6. 强制重新探测（**按需调用**，无后台轮询；上线前请替换 validationURL）
 ConnectivityCenter.shared.validationURL = URL(string: "https://api.example.com/health")!
 let forced = await ConnectivityCenter.shared.status(.validated(force: true))
 // forced.validation → .available / .unavailable / .captivePortal

 注意：`monitor()` / `connectivityUpdates()` 仅 L1+L2；快照中的 validation 为上次 `.validated` 缓存。
 若需在「网络恢复」时重新探测，请在回调里调用 `await status(.validated())`。

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

    /// 路径变化监听（L1+L2，**不含** L3）。业务侧更推荐 `connectivityUpdates()`。
    ///
    /// 回调中的 `validation` 为上次 `status(.validated)` 的缓存；路径切换不会自动重新探测。
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

    /// 无线数据策略变化流。业务侧更推荐 `cellularDataPolicyUpdates()`。
    ///
    /// 产出 `.unknown` / `.restricted` / `.unrestricted`；大陆「关闭」与「仅 WLAN」均可能为 `.restricted`。
    public func monitorCellularDataPolicy() -> AsyncStream<CellularDataPolicy> {
        AsyncStream { continuation in
            if cellularData == nil {
                cellularData = CTCellularData()
            }
            cellularData?.cellularDataRestrictionDidUpdateNotifier = { state in
                continuation.yield(Self.mapCellularRestrictedState(state))
            }
            // 首次同步推一次（新建实例时常为 unknown，以 notifier 为准）
            if let state = cellularData?.restrictedState {
                continuation.yield(Self.mapCellularRestrictedState(state))
            }
        }
    }

    /// 当前无线数据策略（一次性读取；新建后可能短暂为 `.unknown`，优先用监听流）。
    ///
    /// 与路径联合使用示例：
    /// ```swift
    /// let policy = ConnectivityCenter.shared.cellularDataPolicy()
    /// let hint = ConnectivityCenter.shared.wirelessDataAccessHint()
    /// // 或：policy.accessHint(with: ConnectivityCenter.shared.status())
    /// ```
    public func cellularDataPolicy() -> CellularDataPolicy {
        if cellularData == nil {
            cellularData = CTCellularData()
        }
        guard let state = cellularData?.restrictedState else { return .unknown }
        return Self.mapCellularRestrictedState(state)
    }

    /// 策略 + 当前路径的启发式提示（见 `WirelessDataAccessHint`）。
    ///
    /// 内部等价于 `cellularDataPolicy().accessHint(with: status())`。
    /// 大陆「关闭」与「仅无线局域网」均可能为 `.restricted`，本 hint 仅供 UI 引导，
    /// 最终以业务请求或 `status(.validated())` 是否成功为准。
    public func wirelessDataAccessHint() -> WirelessDataAccessHint {
        cellularDataPolicy().accessHint(with: status())
    }

    // MARK: - Private

    private static func mapCellularRestrictedState(_ state: CTCellularDataRestrictedState) -> CellularDataPolicy {
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
