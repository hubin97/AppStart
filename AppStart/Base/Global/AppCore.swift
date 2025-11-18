//
//  AppCore.swift
//  LuteBase
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 Hubin_Huang. All rights reserved.
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
public var isSceneEnabled: Bool {
    if #available(iOS 13.0, *) {
        return UIApplication.shared.connectedScenes.contains { $0 is UIWindowScene }
    }
    return false
}

/// 当前激活的 UIWindowScene
public var activeWindowScene: UIWindowScene? {
    return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .first { $0.activationState == .foregroundActive }
}


// MARK: - Window Access

/// 获取当前主窗口（兼容 SceneDelegate / 非 SceneDelegate 环境）
///
/// - 优先从当前前台激活的 Scene 中获取 keyWindow；
/// - 若未启用 SceneDelegate 或没有活跃 Scene，则回退至 AppDelegate.window；
/// - 若依然获取不到，则兜底从 UIApplication.windows 中查找；
/// - 在 App Extension 环境下返回 nil（防止调用 UIApplication.shared 导致崩溃）。
///
public var kAppKeyWindow: UIWindow? {
#if APP_EXTENSION
    return nil
#else
    activeWindowScene?.windows.first(where: \.isKeyWindow) ?? UIApplication.shared.windows.first(where: \.isKeyWindow)
#endif
}

// MARK: - Lay out

/// 状态栏高度 iPhone X (44.0) / iPhone 11 (48.0) / 20.0
//public let kStatusBarHeight: CGFloat = UIApplication.shared.statusBarFrame.size.height

/// 获取状态栏高度  (兼容 SceneDelegate / 非 SceneDelegate 环境)
public var kStatusBarHeight: CGFloat {
    // UIApplication.shared.statusBarFrame 在 iOS 13+ 已废弃，但在 未启用 SceneDelegate 的项目，没有官方替代 API 能获取状态栏高度
    activeWindowScene?.statusBarManager?.statusBarFrame.height ?? UIApplication.shared.statusBarFrame.height
}

/// 屏幕尺寸（动态）
public var kScreenBounds: CGRect {
    activeWindowScene?.screen.bounds ?? UIScreen.main.bounds
}

public var kScreenW: CGFloat { kScreenBounds.width }
public var kScreenH: CGFloat { kScreenBounds.height }

/// 以iPhone6屏幕为设计底稿的比例换算
//public let kScaleW = kScreenW/375.0
//public let kScaleH = kScreenH/667.0
//public func kScaleW(_ w: CGFloat) -> CGFloat { return kScaleW * w }
//public func kScaleH(_ h: CGFloat) -> CGFloat { return kScaleH * h }
public func kScaleW(_ value: CGFloat) -> CGFloat { value * kScreenW / 375.0 }
public func kScaleH(_ value: CGFloat) -> CGFloat { value * kScreenH / 667.0 }

/// 默认导航栏高度
public let kNavBarHeight: CGFloat = 44.0
/// 默认标签栏高度
public let kTabBarHeight: CGFloat = 49.0

/// 获取当前 SafeAreaInsets
public var kSafeAreaInsets: UIEdgeInsets { kAppKeyWindow?.safeAreaInsets ?? .zero }

/// 是否有前刘海  (iPhone X系统 iOS 11+)
// public let kIsHaveBangs = kStatusBarHeight > 20.0
public var kIsHaveBangs: Bool { kSafeAreaInsets.bottom > 0 }

/// 顶部安全区域高度
public var kTopSafeHeight: CGFloat { kSafeAreaInsets.top }

/// 底部安全区域高度
public var kBottomSafeHeight: CGFloat { kSafeAreaInsets.bottom }

/// 状态栏和导航栏总高度
public var kNavBarAndSafeHeight: CGFloat { kStatusBarHeight + kNavBarHeight }

/// tabbar和底部安全区域总高度
public var kTabBarAndSafeHeight: CGFloat { kBottomSafeHeight + kTabBarHeight }

// MARK: - Info

public let kSystemVersion = Float(UIDevice.current.systemVersion) ?? 0.0
public let kiOS13Later = (kSystemVersion >= 13)
public let kiOS14Later = (kSystemVersion >= 14)

/// IDFVString
public let kIDFVString = UIDevice.current.identifierForVendor?.uuidString

/// info.plist
public let kInfoPlist = Bundle.main.infoDictionary ?? Dictionary()
/// 版本号（内部标示）
public let kAppVersion = kInfoPlist["CFBundleShortVersionString"] as? String
/// Build号
public let kAppBuildVersion = kInfoPlist["CFBundleVersion"] as? String

/// 获取当前最顶层显示的 UIViewController
/// - Parameter vc: 可选的起始 UIViewController，默认从主窗口 rootViewController 开始
/// - Returns: 当前屏幕上最顶层的 UIViewController（模态、Navigation、TabBar 都会展开）
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
