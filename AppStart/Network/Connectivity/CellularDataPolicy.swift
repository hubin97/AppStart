//
//  CellularDataPolicy.swift
//  AppStart
//
//  无线数据策略（CTCellularData）与路径启发式提示。

import Foundation

/// App 无线数据策略（`CTCellularData`）。
///
/// 系统只提供 coarse 三态，**不能一一对应**设置页文案：
///
/// | 地区 | 设置表现 | 本枚举 |
/// |------|----------|--------|
/// | 中国大陆 | 无线数据：关闭 / 无线局域网 / 无线局域网与蜂窝数据 | 前两档均为 `.restricted`，第三档 `.unrestricted` |
/// | 海外等 | 多为蜂窝数据开/关 | 关 → `.restricted`，开 → `.unrestricted`（Wi‑Fi 通常仍可用） |
///
/// 区分大陆「关闭」与「仅无线局域网」时，请再结合路径与业务请求（或 L3），见 `WirelessDataAccessHint`。
public enum CellularDataPolicy: Sendable, Equatable {
    /// 未拿到系统回调前的初始态。
    case unknown
    /// 未受限（大陆「无线局域网与蜂窝数据」；海外允许蜂窝）。
    case unrestricted
    /// 受限（大陆「关闭」或「仅无线局域网」；海外多为禁止蜂窝）。
    case restricted

    public var isUnrestricted: Bool { self == .unrestricted }

    public var displayText: String {
        switch self {
        case .unknown: return "未知"
        case .unrestricted: return "未受限"
        case .restricted: return "已受限"
        }
    }
}

/// 结合「无线数据策略 + 当前路径」的启发式提示（非系统精确档位，仅供 UI 引导）。
public enum WirelessDataAccessHint: Sendable, Equatable {
    case unknown
    /// 策略未受限。
    case unrestricted
    /// 策略受限，但当前有 Wi‑Fi/有线路径 —— 大陆常对应「仅无线局域网」；海外常为「关蜂窝、用 Wi‑Fi」。
    /// 「关闭」时路径有时仍显示可用，最终以业务请求或 L3 探测为准。
    case restrictedNonCellularPath
    /// 策略受限，且路径不可用或当前主要为蜂窝 —— 大陆常对应「关闭」，或海外关蜂窝且未连 Wi‑Fi。
    case restrictedLikelyNoAccess

    public var displayText: String {
        switch self {
        case .unknown: return "未知"
        case .unrestricted: return "无线数据未受限"
        case .restrictedNonCellularPath: return "蜂窝受限（可用 Wi‑Fi 时多可联网）"
        case .restrictedLikelyNoAccess: return "无线数据可能已关闭"
        }
    }
}

public extension CellularDataPolicy {
    /// 结合当前路径给出 UI 提示；无法单独还原大陆三档，需业务请求兜底。
    func accessHint(with path: ConnectivitySnapshot) -> WirelessDataAccessHint {
        switch self {
        case .unknown:
            return .unknown
        case .unrestricted:
            return .unrestricted
        case .restricted:
            if path.canAttemptRequest, path.link == .wifi || path.link == .wired {
                return .restrictedNonCellularPath
            }
            return .restrictedLikelyNoAccess
        }
    }
}
