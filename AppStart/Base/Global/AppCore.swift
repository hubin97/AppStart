//
//  AppCore.swift
//  AppStart
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 hubin.h. All rights reserved.
//

import UIKit
// 全局导入, 若主工程没有混编生成.pch文件, 可以使用此方法
//@_exported import RxSwift

// MARK: - Scene Support

/// 判断当前应用是否启用了 Scene 模式（即使用 UIWindowScene 生命周期）
///
/// - iOS 13 及以上系统才可能启用 Scene；
/// - 当 `UIApplication.shared.connectedScenes` 中存在 UIWindowScene 类型时，
///   表示应用使用了多场景架构；（即 Info.plist 中配置了 UIApplicationSceneManifest）
///
/// - 对于旧项目或 App Extension，会返回 false。
@MainActor
public var isSceneEnabled: Bool {
    if #available(iOS 13.0, *) {
        return UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene }
    }
    return false
}

/// 当前前台的 UIWindowScene
///
/// 优先选择 `foregroundActive`，没有活跃场景时再选择 `foregroundInactive`。
@MainActor
public var activeWindowScene: UIWindowScene? {
    preferredWindowScenes.first
}

/// 按前台活跃程度排序的 UIWindowScene。
@MainActor
private var preferredWindowScenes: [UIWindowScene] {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    return [.foregroundActive, .foregroundInactive].flatMap { state in
        scenes.filter { $0.activationState == state }
    }
}

// MARK: - Window Access

/// 获取当前主窗口
///
/// - 按 `foregroundActive`、`foregroundInactive` 顺序遍历已连接的 UIWindowScene；
/// - 每个场景优先取 keyWindow，再取可见的普通层级窗口；
/// - 在 App Extension 环境下返回 nil（防止调用 UIApplication.shared 导致崩溃）。
///
@MainActor
public var kAppKeyWindow: UIWindow? {
#if APP_EXTENSION
    return nil
#else
    for scene in preferredWindowScenes {
        if let keyWindow = scene.windows.first(where: \.isKeyWindow) {
            return keyWindow
        }
        if let visibleWindow = scene.windows.first(where: { !$0.isHidden && $0.alpha > 0 && $0.windowLevel == .normal }) {
            return visibleWindow
        }
    }
    return nil
#endif
}

// MARK: - Lay out

/// 屏幕尺寸（动态）
@MainActor
public var kScreenBounds: CGRect {
    activeWindowScene?.screen.bounds ?? UIScreen.main.bounds
}

@MainActor
public var kScreenW: CGFloat { kScreenBounds.width }
@MainActor
public var kScreenH: CGFloat { kScreenBounds.height }

/// 以iPhone6屏幕为设计底稿的比例换算
//public let kScaleW = kScreenW/375.0
//public let kScaleH = kScreenH/667.0
//public func kScaleW(_ w: CGFloat) -> CGFloat { return kScaleW * w }
//public func kScaleH(_ h: CGFloat) -> CGFloat { return kScaleH * h }
@MainActor
public func kScaleW(_ value: CGFloat) -> CGFloat { value * kScreenW / 375.0 }
@MainActor
public func kScaleH(_ value: CGFloat) -> CGFloat { value * kScreenH / 667.0 }

/// 默认导航栏高度
public let kNavBarHeight: CGFloat = 44.0
/// 默认标签栏高度
public let kTabBarHeight: CGFloat = 49.0

/// 获取当前 SafeAreaInsets
@MainActor
public var kSafeAreaInsets: UIEdgeInsets { kAppKeyWindow?.safeAreaInsets ?? .zero }

/// 是否有前刘海  (iPhone X系统 iOS 11+)
// public let kIsHaveBangs = kStatusBarHeight > 20.0
@MainActor
public var kIsHaveBangs: Bool { kSafeAreaInsets.bottom > 0 }

/// 顶部安全区域高度
@MainActor
public var kTopSafeHeight: CGFloat { kSafeAreaInsets.top }

@available(*, deprecated, renamed: "kTopSafeHeight", message: "statusBarFrame 在 iOS 26 上与布局 safe area 易不一致，请改用 kTopSafeHeight。")
@MainActor
public var kStatusBarHeight: CGFloat { kTopSafeHeight }

/// 底部安全区域高度
@MainActor
public var kBottomSafeHeight: CGFloat { kSafeAreaInsets.bottom }

/// 状态栏和导航栏总高度（与 ViewController.naviBar 约束一致，优先 safeAreaInsets.top）
@MainActor
public var kNavBarAndSafeHeight: CGFloat { kTopSafeHeight + kNavBarHeight }

/// tabbar和底部安全区域总高度
@MainActor
public var kTabBarAndSafeHeight: CGFloat { kBottomSafeHeight + kTabBarHeight }

// MARK: - Info

public var kSystemVersion: Float { Float(UIDevice.current.systemVersion) ?? 0.0 }
public var kiOS13Later: Bool { kSystemVersion >= 13 }
public var kiOS14Later: Bool { kSystemVersion >= 14 }

/// 宿主 Info.plist `UIDesignRequiresCompatibility`。未配置视为 `false`。读 `Bundle.main`，不是 Pod bundle。
public var kUIDesignRequiresCompatibility: Bool {
    Bundle.main.object(forInfoDictionaryKey: "UIDesignRequiresCompatibility") as? Bool ?? false
}

/// Liquid Glass 是否生效。iOS 26 读 `UIDesignRequiresCompatibility`；更早为关，iOS 27 SDK 起为开。
public var isLiquidGlassEnabled: Bool {
    if #available(iOS 27.0, *) { return true }
    guard #available(iOS 26.0, *) else { return false }
    return !kUIDesignRequiresCompatibility
}

/// IDFVString
public var kIDFVString: String? { UIDevice.current.identifierForVendor?.uuidString }

/// info.plist
public var kInfoPlist: [String: Any] { Bundle.main.infoDictionary ?? Dictionary() }
/// 版本号（内部标示）
public var kAppVersion: String? { kInfoPlist["CFBundleShortVersionString"] as? String }
/// Build号
public var kAppBuildVersion: String? { kInfoPlist["CFBundleVersion"] as? String }

/// 获取当前最顶层显示的 UIViewController
/// - Parameter vc: 可选的起始 UIViewController，默认从主窗口 rootViewController 开始
/// - Returns: 当前屏幕上最顶层的 UIViewController（模态、Navigation、TabBar 都会展开）
@MainActor
public func stackTopViewController(from vc: UIViewController? = nil) -> UIViewController? {
    var current = vc ?? kAppKeyWindow?.rootViewController

    while let viewController = current {
        switch viewController {
        // 如果有模态控制器，优先处理
        case let presented where presented.presentedViewController != nil:
            current = presented.presentedViewController

        // UINavigationController，返回可见的控制器
        case let nav as UINavigationController:
            current = nav.visibleViewController

        // UITabBarController，返回选中的控制器
        case let tab as UITabBarController:
            current = tab.selectedViewController

        // 普通控制器，返回自己
        default:
            return viewController
        }
    }

    return nil
}

/// 根据字符串获取工程中的对应Swift类
/// \\ 使用 swiftClassFromString("xxx") as? UIViewController.Type
///
/// - Parameter aClassName: 类名字符串
/// - Returns: 类
public func swiftClassFromString(_ aClassName: String) -> AnyClass? {
    // 获取工程名
    guard let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String else { return nil }
    // 过滤无效字符 空格不转换的话 得不到准确类名
    let formattedAppName = appName.replacingOccurrences(of: " ", with: "_")
    // 拼接控制器名
    let classStringName = "\(formattedAppName).\(aClassName)"
    // 将控制名转换为类
    return NSClassFromString(classStringName)
}
