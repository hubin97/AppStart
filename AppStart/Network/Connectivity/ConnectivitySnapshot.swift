//
//  ConnectivitySnapshot.swift
//  AppStart
//
//  网络连通性分层快照模型。

import Foundation

/// 链路类型（L1）。
public enum NetworkLinkKind: Sendable, Equatable {
    case none
    case wifi
    case cellular
    case wired
    case other
    case unknown
}

/// 系统路径状态（L2，`NWPathMonitor`）。
public enum NetworkPathStatus: Sendable, Equatable {
    case satisfied
    case unsatisfied
    case requiresConnection

    public var isSatisfied: Bool { self == .satisfied }
}

/// 互联网探测结果（L3，可选 HTTP 探测）。
public enum InternetValidation: Sendable, Equatable {
    case notChecked
    case available
    case unavailable
    case captivePortal
}

/// 查询深度：`path` 仅 L1+L2（本地、无 HTTP）；`validated` 含 L3 互联网探测（async、按需）。
public enum ConnectivityLevel: Sendable {
    /// L1 链路 + L2 路径（`NWPathMonitor`，同步可读）。
    case path
    /// L1+L2+L3；`force == false` 时受 `validationDebounce` 限频。
    case validated(force: Bool = false)
}

/// 网络连通性快照。
public struct ConnectivitySnapshot: Sendable {
    public let link: NetworkLinkKind
    public let pathStatus: NetworkPathStatus
    public let isExpensive: Bool
    public let isConstrained: Bool
    public let validation: InternetValidation

    public init(
        link: NetworkLinkKind,
        pathStatus: NetworkPathStatus,
        isExpensive: Bool = false,
        isConstrained: Bool = false,
        validation: InternetValidation = .notChecked
    ) {
        self.link = link
        self.pathStatus = pathStatus
        self.isExpensive = isExpensive
        self.isConstrained = isConstrained
        self.validation = validation
    }

    /// 路径可用，可尝试发起请求（不保证业务 API 成功）。
    public var canAttemptRequest: Bool {
        pathStatus.isSatisfied && link != .none
    }

    /// 路径可用且互联网探测通过（需 `status(.validated)` 或上次探测缓存）。
    public var isInternetReady: Bool {
        guard canAttemptRequest else { return false }
        return validation == .available
    }

    public var summaryText: String {
        guard canAttemptRequest else { return "路径：不可用" }
        var parts = ["路径：\(pathStatus.displayText)", "链路：\(link.displayText)"]
        if isExpensive { parts.append("计费网络") }
        if isConstrained { parts.append("低数据模式") }
        if validation != .notChecked {
            parts.append("探测：\(validation.displayText)")
        }
        return parts.joined(separator: " · ")
    }
}

public extension NetworkPathStatus {
    var displayText: String {
        switch self {
        case .satisfied: return "可用"
        case .unsatisfied: return "不可用"
        case .requiresConnection: return "需连接"
        }
    }
}

public extension NetworkLinkKind {
    var displayText: String {
        switch self {
        case .none: return "无"
        case .wifi: return "Wi‑Fi"
        case .cellular: return "蜂窝"
        case .wired: return "有线"
        case .other: return "其他"
        case .unknown: return "未知"
        }
    }
}

public extension InternetValidation {
    var displayText: String {
        switch self {
        case .notChecked: return "未探测"
        case .available: return "可用"
        case .unavailable: return "不可用"
        case .captivePortal: return "需登录网络"
        }
    }
}
