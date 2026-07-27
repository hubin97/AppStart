//
//  NetworkValidator.swift
//  AppStart
//
//  L3 互联网探测（HTTP HEAD）。

import Foundation

enum NetworkValidator {

    /// 库内默认探测地址（未配置业务 health 时使用）。
    ///
    /// 选用 `captive.apple.com/hotspot-detect.html` 的原因：
    /// - 与 iOS 系统判断「是否需要 Wi‑Fi 登录 / 是否有网」使用同一探测页，行为稳定、响应体小
    /// - 不依赖 Google `generate_204`（国内网络环境下常不可用）
    /// - 不使用 `apple.com` 首页：页面大、CDN 策略复杂，且非专用探测端点
    ///
    /// 生产环境仍建议在 App 启动时覆盖为业务接口，例如：
    /// `ConnectivityCenter.shared.validationURL = URL(string: "https://api.example.com/health")!`
    ///
    /// 状态码约定（HEAD）：
    /// - 2xx / 204 → `.available`
    /// - 3xx → `.captivePortal`（常见于商场/酒店 Wi‑Fi 强制门户）
    /// - 其它 / 超时 → `.unavailable`（含「连上无网热点」「路由器未拨号」等）
    static let defaultURL = URL(string: "http://captive.apple.com/hotspot-detect.html")!

    /// - `url` 默认 `defaultURL`；`ConnectivityCenter` 在 `status(.validated)` 时传入已配置的 `validationURL`
    static func validate(
        url: URL = defaultURL,
        timeout: TimeInterval = 5
    ) async -> InternetValidation {
        var request = URLRequest(url: url)
        request.httpMethod = "HEAD"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = timeout

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return .unavailable }
            switch http.statusCode {
            case 200...299, 204:
                return .available
            case 300...399:
                return .captivePortal
            default:
                return .unavailable
            }
        } catch {
            return .unavailable
        }
    }
}
