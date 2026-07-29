//
//  AuthStatusConfiguration.swift
//  AppStart
//
//  权限模块宿主配置；在 App 启动时通过 `AuthorizationStatus.configure { }` 注入。

import Foundation

/// 权限模块宿主配置；在 App 启动时通过 `AuthorizationStatus.configure { }` 一次性注入。
public struct AuthStatusConfiguration: Sendable {

    /// Siri capability 是否已在 Xcode 开启并启用（默认 `false` → `.siri` service 为「未开启」）。
    /// 注意：若开启该选项但 Xcode 未启用 Siri capability，会导致应用闪退。
    public var isSiriCapabilityEnabled = false

    /// 本地网络相关配置（须 plist `NSLocalNetworkUsageDescription` + `NSBonjourServices`）。
    public var localNetwork = LocalNetwork()

    public init() {}

    /// 本地网络（iOS 无授权回调，仅能 Bonjour 探测推断；实现见 `LocalNetworkAuthorizationCoordinator`）。
    public struct LocalNetwork: Sendable {

        /// Bonjour 类型，须与 plist `NSBonjourServices` 一致；空数组时使用 `["_http._tcp"]`。
        public var bonjourServiceTypes: [String] = []

        /// 首次 `request` / `resolve(..., requestIfNeeded: true)` 时，判定「已授权」前的确认等待（秒，默认 **15**，有效值不低于 **5**）。
        ///
        /// iOS 无本地网络授权回调，结果由 `NWBrowser` 状态推断（见 TN3179）：
        /// - **拒绝**：出现 `PolicyDenied` 时尽快返回 `.denied`，一般无需等满此时长。
        /// - **允许**：无「点允许」回调；须在 `.ready` 后再等满此时长才返回 `.granted`，所以等待时长 =`.ready` + `grantConfirmationWait`。
        /// - **未点击**：用户未点弹框时，探测仍可能提前进入 `.ready`，约此时长后仍可能被推断为已授权；**越大越不易误报**。
        ///
        /// 探测总超时由模块内收为 `grantConfirmationWait + 10s`（超时 → `.notDetermined`）。仅影响首次 request，静默刷新使用内收 1s/5s。
        public var grantConfirmationWait: TimeInterval = 15

        public init() {}

        var resolvedBonjourServiceTypes: [String] {
            bonjourServiceTypes.isEmpty ? ["_http._tcp"] : bonjourServiceTypes
        }
    }
}
