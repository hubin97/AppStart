//
//  AuthStatusConfiguration.swift
//  AppStart
//
//  权限模块宿主配置；在 App 启动时通过 `AuthorizationStatus.configure { }` 注入。

import Foundation

/// 权限模块宿主配置；在 App 启动时通过 `AuthorizationStatus.configure { }` 一次性注入。
public struct AuthStatusConfiguration: Sendable {

    /// 是否在 Xcode 中启用 Siri capability（默认 `false` → snapshot 服务不可用；读 authorization 层为 `.restricted`）。
    /// 若设为 `true` 但 Xcode 未开启 capability，运行时会崩溃。
    public var isSiriCapabilityEnabled = false

    /// 本地网络相关配置（须 plist `NSLocalNetworkUsageDescription` + `NSBonjourServices`）。
    public var localNetwork = LocalNetwork()

    public init() {}

    /// 本地网络（无系统授权回调，NWBrowser 推断，见 `LocalNetworkAuthorizationCoordinator`）
    public struct LocalNetwork: Sendable {

        /// Bonjour 类型，须与 plist `NSBonjourServices` 一致；空数组时默认 `["_http._tcp"]`
        public var bonjourServiceTypes: [String] = []

        /// 首次 request 时，判定 `.granted` 前的确认等待（秒，默认 **15**，下限 **5**）。
        ///
        /// iOS 无本地网络授权回调，结果由 NWBrowser 状态推断（TN3179）：
        /// - **拒绝**：`PolicyDenied` 时尽快返回 `.denied`，通常不必等满
        /// - **允许**：无点击回调；`.ready` 后再等满此值才返回 `.granted`
        /// - **未点击**：弹框期间可能提前 `.ready`，约此值后或被推断为 granted；**越大越不易误判**
        ///
        /// 探测总超时模块内固定为 `grantConfirmationWait + 10s`；静默刷新用 1s/5s。
        public var grantConfirmationWait: TimeInterval = 15

        public init() {}

        var resolvedBonjourServiceTypes: [String] {
            bonjourServiceTypes.isEmpty ? ["_http._tcp"] : bonjourServiceTypes
        }
    }
}
