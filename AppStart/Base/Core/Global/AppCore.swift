//
//  AppCore.swift
//  LuteBase
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 Hubin_Huang. All rights reserved.
//

import UIKit
import Foundation
// 全局导入, 若主工程没有混编生成.pch文件, 可以使用此方法
//@_exported import RxSwift

// MARK: - Lay out
/// 屏幕宽高
public let kScreenW = UIScreen.main.bounds.size.width
public let kScreenH = UIScreen.main.bounds.size.height

/// 以iPhone6屏幕为设计底稿的比例换算
public let kScaleW = kScreenW/375.0
public let kScaleH = kScreenH/667.0
public func kScaleW(_ w: CGFloat) -> CGFloat { return kScaleW * w }
public func kScaleH(_ h: CGFloat) -> CGFloat { return kScaleH * h }

/// 默认导航栏高度
public let kNavBarHeight: CGFloat = 44.0
/// 默认标签栏高度
public let kTabBarHeight: CGFloat = 49.0

/// 是否有前刘海  (iPhone X系统 iOS 11+)
public let kIsHaveBangs = kStatusBarHeight > 20.0

/// 顶部安全区域高度
public let kTopSafeHeight: CGFloat = kIsHaveBangs ? kStatusBarHeight : 0

/// 底部安全区域高度
public let kBottomSafeHeight: CGFloat = kIsHaveBangs ? 34: 0.0

/// 状态栏和导航栏总高度
public let kNavBarAndSafeHeight: CGFloat = kStatusBarHeight + kNavBarHeight

/// tabbar和底部安全区域总高度
public let kTabBarAndSafeHeight: CGFloat = kBottomSafeHeight + kTabBarHeight

// MARK: - Info

public let kSystemVersion = Float(UIDevice.current.systemVersion) ?? 0.0
public let kiOS9Later  = (kSystemVersion >= 9)
public let kiOS10Later = (kSystemVersion >= 10)
public let kiOS11Later = (kSystemVersion >= 11)
public let kiOS12Later = (kSystemVersion >= 12)
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

/// 判断当前应用是否启用了 SceneDelegate（即使用 UIScene 生命周期）
///
/// 当 Info.plist 中存在键 `UIApplicationSceneManifest` 时，
/// 表示项目采用了多场景（Scene）架构；
/// 否则依旧使用传统的 AppDelegate 生命周期。
///
/// - Returns: 如果启用了 SceneDelegate 返回 true，否则返回 false。
private var isSceneEnabled: Bool {
    return Bundle.main.object(forInfoDictionaryKey: "UIApplicationSceneManifest") != nil
}

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
    if isSceneEnabled {
        return UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap { $0.windows }
            .first { $0.isKeyWindow }
    }
    // 非 SceneDelegate 模式 或无活跃 Scene 时
    return UIApplication.shared.delegate?.window
        ?? UIApplication.shared.windows.first(where: { $0.isKeyWindow })
#endif
}

/// 状态栏高度 iPhone X (44.0) / iPhone 11 (48.0) / 20.0
//public let kStatusBarHeight: CGFloat = UIApplication.shared.statusBarFrame.size.height

/// 获取状态栏高度  (兼容 SceneDelegate / 非 SceneDelegate 环境)
public let kStatusBarHeight: CGFloat = {
    if isSceneEnabled {
        let activeScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
        
        if let scene = activeScenes.first,
           let statusBarManager = scene.statusBarManager {
            return statusBarManager.statusBarFrame.height
        }
    }
    
    // 非 Scene 模式或没有活跃 Scene 时
    // UIApplication.shared.statusBarFrame 在 iOS 13+ 已废弃，但在 未启用 SceneDelegate 的项目，没有官方替代 API 能获取状态栏高度
    return UIApplication.shared.statusBarFrame.height
}()

/// 获取当前最顶层显示的 UIViewController
/// - Parameter vc: 可选的起始 UIViewController，默认从主窗口 rootViewController 开始
/// - Returns: 当前屏幕上最顶层的 UIViewController（模态、Navigation、TabBar 都会展开）
public func stackTopViewController(_ vc: UIViewController? = nil) -> UIViewController? {
    // 从传入 VC 或主窗口 rootViewController 开始
    var rootVc = vc ?? kAppKeyWindow?.rootViewController
    guard let root = rootVc else { return nil }

    // 1️⃣ 模态遍历，找到最顶层 presentedViewController
    while let presented = rootVc?.presentedViewController {
        rootVc = presented
    }

    // 2️⃣ 递归展开 TabBar / Navigation 容器
    if let tab = rootVc as? UITabBarController, let selected = tab.selectedViewController {
        return stackTopViewController(selected)
    } else if let nav = rootVc as? UINavigationController, let visible = nav.visibleViewController {
        return stackTopViewController(visible)
    }

    // 3️⃣ 普通控制器，返回自己
    return rootVc
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
