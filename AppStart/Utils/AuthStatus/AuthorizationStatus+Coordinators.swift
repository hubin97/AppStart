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
final class LocationAuthorizationCoordinator: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<PermissionStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func authorizationStatus() -> PermissionStatus {
        AuthPermissionMapping.location(manager.authorizationStatus)
    }

    func request(_ level: LocationAuthLevel) async -> PermissionStatus {
        let current = authorizationStatus()
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch level {
            case .whenInUse:
                manager.requestWhenInUseAuthorization()
            case .always:
                manager.requestAlwaysAuthorization()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        finishIfNeeded(for: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        finishIfNeeded(for: status)
    }

    private func finishIfNeeded(for status: CLAuthorizationStatus) {
        guard continuation != nil else { return }
        let mapped = AuthPermissionMapping.location(status)
        guard mapped != .notDetermined else { return }
        continuation?.resume(returning: mapped)
        continuation = nil
    }
}

// MARK: - Local Network

/// 本地网络无同步授权 API；通过 `NWBrowser` 探测并缓存结果（见 TN3179）。
///
/// ### 两条探测路径（结论）
///
/// | | 首次 request `probe(silent: false)` | 静默 re-probe `probe(silent: true)` |
/// |--|--|--|
/// | 触发 | 缓存 `nil` / `.notDetermined`，`request()` | 缓存已 `.granted` / `.denied`，`authorizationStatus()` |
/// | grant 确认 | `grantConfirmationWait`（默认 **15s**，下限 **5s**） | **1s**（`silentGrantConfirmationWait`） |
/// | 探测总超时 | `grantConfirmationWait + 10s`（默认 **25s**） | **5s**（`silentProbeTimeout`） |
/// | 系统弹框 | 可能弹出 | **不再弹出** |
///
/// **拒绝**：`PolicyDenied` → 尽快 `.denied`，两路径均不必等满 grant 时长。
/// **允许**：无点按回调；`.ready` 后再等 grant 时长 → `.granted`（首次慢、刷新快）。
/// **未点击**（仅首次）：弹框期间可能提前 `.ready`，约 grant 时长后或被推断已授权 → 故首次 grant 偏长。
///
/// 首次弹框后用户在 Demo / 设置里再查，走静默路径，故更新明显更快。
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

            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) {
                finish(self.cachedStatus ?? .notDetermined)
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
