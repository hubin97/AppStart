//
//  AuthorizationStatus+Coordinators.swift
//  AppStart
//
//  系统 delegate 协调：定位授权、本地网络、蓝牙硬件状态。

import CoreBluetooth
import CoreLocation
import Network

// MARK: - Location

/// 内部持有 `CLLocationManager`，避免外部 delegate 协议 + 全局强引用。
///
/// 状态（continuation / pendingLevel）需在主线程串行维护；`CLLocationManager` 与 request 也应在主线程使用。
/// `CLLocationManagerDelegate` 在类型上非 MainActor，故 delegate 方法标 `nonisolated`，内部 `Task { @MainActor in }` 跳回，避免 Swift 6 data race。
/// 本地网络 Coordinator 只在 `NWBrowser` 回调里切到 main queue，蓝牙 delegate 在 `AuthorizationStatus` 上，模式不同。
@MainActor
final class LocationAuthorizationCoordinator: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<PermissionStatus, Never>?
    private var pendingLevel: LocationAuthLevel?
    private var timeoutTask: Task<Void, Never>?
    /// 同一时刻只允许一个 request，避免覆盖 continuation 导致泄漏。
    private var activeRequest: Task<PermissionStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    /// 按 `LocationAuthLevel` 解读授权：
    /// - whenInUse：`.authorizedWhenInUse` / `.authorizedAlways` → `.granted`
    /// - always：仅 `.authorizedAlways` → `.granted`；仅有 whenInUse 时 → `.notDetermined`（可再 request 升级）
    func authorizationStatus(for level: LocationAuthLevel) -> PermissionStatus {
        switch manager.authorizationStatus {
        case .authorizedAlways:
            return .granted
        case .authorizedWhenInUse:
            return level == .whenInUse ? .granted : .notDetermined
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    func request(_ level: LocationAuthLevel) async -> PermissionStatus {
        let current = authorizationStatus(for: level)
        guard current == .notDetermined else { return current }

        if let activeRequest {
            return await activeRequest.value
        }

        let task = Task { await self.performRequest(level) }
        activeRequest = task
        defer { activeRequest = nil }
        return await task.value
    }

    private func performRequest(_ level: LocationAuthLevel) async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            beginPendingRequest(level: level, continuation: continuation)

            switch level {
            case .whenInUse:
                manager.requestWhenInUseAuthorization()
            case .always:
                manager.requestAlwaysAuthorization()
            }

            // 部分场景系统不回调 delegate（如 always 升级被拒绝/无弹窗）；短延迟兜底，避免 continuation 泄漏。
            scheduleDeferredCompletion(for: level)
        }
    }

    private func scheduleDeferredCompletion(for level: LocationAuthLevel) {
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 800_000_000)
            self?.finishIfNeededDeferred(expecting: level)
        }
    }

    private func beginPendingRequest(
        level: LocationAuthLevel,
        continuation: CheckedContinuation<PermissionStatus, Never>
    ) {
        cancelPendingRequest(resumingWith: authorizationStatus(for: pendingLevel ?? level))
        self.continuation = continuation
        pendingLevel = level

        timeoutTask?.cancel()
        timeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 30_000_000_000)
            self?.timeoutPendingRequest(expecting: level)
        }
    }

    private func cancelPendingRequest(resumingWith result: PermissionStatus) {
        timeoutTask?.cancel()
        timeoutTask = nil
        guard let continuation else { return }
        continuation.resume(returning: result)
        self.continuation = nil
        pendingLevel = nil
    }

    private func completePendingRequest() {
        guard let level = pendingLevel, let continuation else { return }
        timeoutTask?.cancel()
        timeoutTask = nil
        continuation.resume(returning: authorizationStatus(for: level))
        self.continuation = nil
        pendingLevel = nil
    }

    private func timeoutPendingRequest(expecting level: LocationAuthLevel) {
        guard pendingLevel == level, continuation != nil else { return }
        completePendingRequest()
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor [weak self] in
            self?.finishIfNeeded()
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        Task { @MainActor [weak self] in
            self?.finishIfNeeded()
        }
    }

    /// delegate 回调且 OS 已脱离 notDetermined 时结束 pending。
    private func finishIfNeeded() {
        guard continuation != nil else { return }
        guard manager.authorizationStatus != .notDetermined else { return }
        completePendingRequest()
    }

    /// 无 delegate 时的兜底：仅在 OS 已脱离 notDetermined 时结束，避免抢在用户操作前完成。
    private func finishIfNeededDeferred(expecting level: LocationAuthLevel) {
        guard pendingLevel == level, continuation != nil else { return }
        guard manager.authorizationStatus != .notDetermined else { return }
        completePendingRequest()
    }
}

// MARK: - Local Network

/// 本地网络无同步授权 API；NWBrowser 探测并缓存结果（TN3179）。
///
/// 两条探测路径：
/// - **首次 request**（可能弹框）：grant 等待 `grantConfirmationWait`（默认 15s），总超时 +10s（默认 25s）
/// - **静默刷新**（不弹框，如从设置返回）：模块内固定 1s / 5s，响应更快
///
/// 拒绝走 PolicyDenied 较快返回；允许无回调需等待；未点击也可能被推断为 granted，故首次 grant 默认偏长。
private enum LocalNetworkProbeTiming {
    /// 业务可配 `grantConfirmationWait` 的下限（低于此值易在弹框未操作时误报已授权）。
    static let minimumGrantConfirmationWait: TimeInterval = 5
    /// 首次 request 探测总超时相对 `grantConfirmationWait` 的内收缓冲（秒）。
    static let requestProbeTimeoutBuffer: TimeInterval = 10
    /// 静默刷新（不弹框）：判定「已授权」前的确认等待（秒）。
    static let silentGrantConfirmationWait: TimeInterval = 1
    /// 静默刷新（不弹框）：单次探测最长等待（秒）；超时保留上次结果。
    static let silentProbeTimeout: TimeInterval = 5
}

final class LocalNetworkAuthorizationCoordinator {

    /// 须与 Info.plist `NSBonjourServices` 一致；未由业务赋值时由 `AuthorizationStatus` 注入默认 `["_http._tcp"]`。
    var bonjourServiceTypes: [String] = ["_http._tcp"]

    /// 首次 request 时判定「已授权」前的确认等待（秒，默认 15）。
    var grantConfirmationWait: TimeInterval = 15

    private var cachedStatus: PermissionStatus?
    private var browser: NWBrowser?
    private var readyDebounceWorkItem: DispatchWorkItem?
    private var activeProbe: Task<PermissionStatus, Never>?

    func apply(_ config: AuthStatusConfiguration.LocalNetwork) {
        bonjourServiceTypes = config.resolvedBonjourServiceTypes
        grantConfirmationWait = max(
            LocalNetworkProbeTiming.minimumGrantConfirmationWait,
            config.grantConfirmationWait
        )
    }

    /// 只读当前结论；若此前已探测过（非 `.notDetermined`），会静默 re-probe 以同步系统设置变更，**不会**再次弹框。
    func authorizationStatus() async -> PermissionStatus {
        guard let cached = cachedStatus, cached != .notDetermined else {
            return cachedStatus ?? .notDetermined
        }
        return await probe(silent: true)
    }

    func request() async -> PermissionStatus {
        if cachedStatus == nil || cachedStatus == .notDetermined {
            return await probe(silent: false)
        }
        return await authorizationStatus()
    }

    /// - Parameter silent: `true` = 同步设置 / 不弹框；`false` = 首次 request，使用 `grantConfirmationWait` 与内收 probe 超时。
    private func probe(silent: Bool) async -> PermissionStatus {
        /// 探测超时时长
        let timeout: TimeInterval
        let grantWait: TimeInterval
        if silent {
            timeout = LocalNetworkProbeTiming.silentProbeTimeout
            grantWait = LocalNetworkProbeTiming.silentGrantConfirmationWait
        } else {
            grantWait = grantConfirmationWait
            timeout = grantWait + LocalNetworkProbeTiming.requestProbeTimeoutBuffer
        }
        return await performProbe(timeout: timeout, grantDebounce: grantWait)
    }

    private func performProbe(timeout: TimeInterval, grantDebounce: TimeInterval) async -> PermissionStatus {
        if let activeProbe { return await activeProbe.value }

        let task = Task { await runProbe(timeout: timeout, grantDebounce: grantDebounce) }
        activeProbe = task
        defer { activeProbe = nil }
        return await task.value
    }

    private func runProbe(timeout: TimeInterval, grantDebounce: TimeInterval) async -> PermissionStatus {
        guard let serviceType = bonjourServiceTypes.first, !serviceType.isEmpty else {
            cachedStatus = .restricted
            return .restricted
        }

        return await withCheckedContinuation { continuation in
            var didResume = false
            let finish: (PermissionStatus) -> Void = { status in
                guard !didResume else { return }
                didResume = true
                self.readyDebounceWorkItem?.cancel()
                self.readyDebounceWorkItem = nil
                self.browser?.cancel()
                self.browser = nil
                self.cachedStatus = status
                continuation.resume(returning: status)
            }

            let parameters = NWParameters.tcp
            parameters.includePeerToPeer = true
            let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: parameters)
            self.browser = browser

            browser.stateUpdateHandler = { state in
                switch state {
                case .waiting(let error):
                    // 任意 .waiting 都先取消 grant 计时；拒绝时会出现 PolicyDenied（TN3179）
                    self.readyDebounceWorkItem?.cancel()
                    self.readyDebounceWorkItem = nil
                    if Self.isPolicyDenied(error) {
                        finish(.denied)
                    }
                case .ready:
                    // 首次 .ready 常为假阳性；仅在持续 ready 且未出现 PolicyDenied 后再判 granted
                    self.readyDebounceWorkItem?.cancel()
                    let work = DispatchWorkItem { finish(.granted) }
                    self.readyDebounceWorkItem = work
                    DispatchQueue.main.asyncAfter(deadline: .now() + grantDebounce, execute: work)
                case .failed:
                    self.readyDebounceWorkItem?.cancel()
                    self.readyDebounceWorkItem = nil
                    finish(.denied)
                default:
                    break
                }
            }

            browser.start(queue: .main)

            let fallbackStatus = self.cachedStatus
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                finish(fallbackStatus ?? .notDetermined)
            }
        }
    }

    private static func isPolicyDenied(_ error: NWError) -> Bool {
        if case .dns(let code) = error, code == kDNSServiceErr_PolicyDenied {
            return true
        }
        let description = String(describing: error)
        return description.contains("PolicyDenied") || description.contains("-65570")
    }
}

// MARK: - Bluetooth

/// 蓝牙权限
/**
 <!-- 蓝牙 -->
 <key>NSBluetoothPeripheralUsageDescription</key>
 <string>App需要您的同意,才能访问蓝牙</string>
 <!-- 上面权限 官方 API 提示 iOS13 已废弃 -->
 <key>NSBluetoothAlwaysUsageDescription</key>
 <string>App需要您的同意,才能访问蓝牙</string>
 */

extension AuthorizationStatus: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if let continuation = bluetoothStateContinuation {
            bluetoothStateContinuation = nil
            continuation.resume(returning: central.state)
        }
    }
}
