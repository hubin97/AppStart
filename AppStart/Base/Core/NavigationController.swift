//
//  NavigationController.swift
//  LuteExample
//
//  Created by hubin.h on 2023/11/10.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation
import UIKit

// MARK: - global var and methods
public struct BarAttributes {
    var barTintColor: UIColor = .white
    var shadowColor: UIColor?
    var titleColor: UIColor = .black
    var titleFont: UIFont = UIFont.systemFont(ofSize: 17.0, weight: .medium)
}

// MARK: - main class
open class NavigationController: UINavigationController {
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
        if NaviBar.usesSystemBar {
            Self.applySystemBarAppearance(to: navigationBar)
        } else {
            self.navigationBar.isTranslucent = false
        }
        self.delegate = self
        self.interactivePopGestureRecognizer?.delegate = self
        self.interactivePopGestureRecognizer?.addTarget(self, action: #selector(handlePopGesture(_:)))
        contentPopGestureRecognizer?.delegate = self
        self.updatePopGestureAvailability()

//        if responds(to: #selector(getter: interactivePopGestureRecognizer)) {
//            delegate = self
//        }        
    }
    
    open override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        self.setupTabBarHidden(animated: true)
    }
    
    //    override var preferredStatusBarStyle: UIStatusBarStyle {
    //        return self.topViewController?.preferredStatusBarStyle ?? .default
    //    }
      
    /// `官方推荐`的用于管理状态栏样式的机制
    open override var childForStatusBarStyle: UIViewController? {
        return topViewController
    }
    
    open override var childForStatusBarHidden: UIViewController? {
        return topViewController
    }
    
    /// 便捷初始化
    /// - Parameters:
    ///   - rootViewController: 根控制器
    ///   - barAttributes: 导航栏特性
    public convenience init(rootVc: UIViewController, barAttributes: BarAttributes? = nil) {
        self.init(rootViewController: rootVc)
        let attributes = barAttributes ?? BarAttributes()
        let titleTextAttributes = [NSAttributedString.Key.foregroundColor: attributes.titleColor, NSAttributedString.Key.font: attributes.titleFont]
        if NaviBar.usesSystemBar {
            Self.applySystemBarAppearance(to: navigationBar, titleTextAttributes: titleTextAttributes)
        } else if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.backgroundColor = attributes.barTintColor
            appearance.titleTextAttributes = titleTextAttributes
            appearance.shadowColor = attributes.shadowColor ?? attributes.barTintColor
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
        } else {
            navigationBar.barTintColor = attributes.barTintColor
            navigationBar.titleTextAttributes = titleTextAttributes
        }
    }
    
    // MARK: 
    open override var shouldAutorotate: Bool {
        return topViewController?.shouldAutorotate ?? false
    }
    
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return topViewController?.supportedInterfaceOrientations ?? .portrait
    }
    
    open override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }

    // MARK: - Back Gesture

    /// 返回手势由导航控制器统一管理，页面只声明是否允许并接收开始回调。
    func updatePopGestureAvailability() {
        let isRootViewController = viewControllers.count <= 1
        let isEnabledByTopViewController = (topViewController as? ViewController)?.enablePopGestureRecognizer ?? true
        let isEnabled = !isRootViewController && isEnabledByTopViewController
        interactivePopGestureRecognizer?.isEnabled = isEnabled
        contentPopGestureRecognizer?.isEnabled = isEnabled
    }

    /// iOS 26 玻璃栏的`内容区侧滑`这是26的新功能特性。边缘侧滑一直是 `interactivePopGestureRecognizer`（iOS 7 起默认开）。
    /// `#available` 只为过编译：`usesSystemBar` 是 `Bool`，编译器不能据此开放 iOS 26 API。
    private var contentPopGestureRecognizer: UIGestureRecognizer? {
        guard NaviBar.usesSystemBar else { return nil }
        if #available(iOS 26.0, *) {
            return interactiveContentPopGestureRecognizer
        }
        return nil
    }

    private func isContentPopGesture(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let contentPopGestureRecognizer else { return false }
        return gestureRecognizer === contentPopGestureRecognizer
    }

    @objc private func handlePopGesture(_ gestureRecognizer: UIGestureRecognizer) {
        guard gestureRecognizer.state == .began else { return }
        (topViewController as? ViewController)?.popGestureAction()
    }
}

// MARK: - Others
extension NavigationController {
    
    /// 设置导航栏
    /// - Parameters:
    ///   - barTintColor: 背景色
    ///   - titleFont: 文字大小
    ///   - titleColor: 文字颜色
    ///   - shadowColor: 导航栏底部下划线颜色, 默认同背景色
    public func setBarAppearance(barTintColor: UIColor = .white, titleFont: UIFont = UIFont.systemFont(ofSize: 17.0, weight: .medium), titleColor: UIColor = .black, shadowColor: UIColor? = nil) {
        let titleTextAttributes = [NSAttributedString.Key.foregroundColor: titleColor, NSAttributedString.Key.font: titleFont]
        if NaviBar.usesSystemBar {
            Self.applySystemBarAppearance(to: navigationBar, titleTextAttributes: titleTextAttributes)
        } else if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.backgroundColor = barTintColor
            appearance.titleTextAttributes = titleTextAttributes
            appearance.shadowColor = shadowColor ?? barTintColor
            navigationBar.standardAppearance = appearance
            navigationBar.scrollEdgeAppearance = appearance
        } else {
            navigationBar.barTintColor = barTintColor
            navigationBar.titleTextAttributes = titleTextAttributes
        }
    }
    
    /// iOS 26：透明系统导航栏，留给 Liquid Glass；勿设置不透明 backgroundColor。
    static func applySystemBarAppearance(
        to navigationBar: UINavigationBar,
        titleTextAttributes: [NSAttributedString.Key: Any]? = nil
    ) {
        navigationBar.isTranslucent = true
        
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .clear
        if let titleTextAttributes {
            appearance.titleTextAttributes = titleTextAttributes
        }
        
        navigationBar.standardAppearance = appearance
        navigationBar.scrollEdgeAppearance = appearance
        navigationBar.compactAppearance = appearance
    }
}

// MARK: - UINavigationControllerDelegate
extension NavigationController: UINavigationControllerDelegate {
    
    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
        updatePopGestureAvailability()
//        if responds(to: #selector(getter: interactivePopGestureRecognizer)) {
//            interactivePopGestureRecognizer?.isEnabled = true
//        }
//        
//        // if rootViewController, set delegate nil /
//        if children.count == 1 {
//            interactivePopGestureRecognizer?.isEnabled = false
//            interactivePopGestureRecognizer?.delegate = nil
//        }
    }
    
    // 自定义非根控制左侧返回按钮
    open override func pushViewController(_ viewController: UIViewController, animated: Bool) {
        defer { self.setupTabBarHidden(animated: animated) }
        // 适用 < iOS 18 版本
        let isHidden = viewControllers.count >= 1
        viewController.hidesBottomBarWhenPushed = isHidden
        super.pushViewController(viewController, animated: animated)
    }
    
    open override func popToViewController(_ viewController: UIViewController, animated: Bool) -> [UIViewController]? {
        defer { self.setupTabBarHidden(animated: animated) }
        return super.popToViewController(viewController, animated: animated)
    }
    
    open override func popToRootViewController(animated: Bool) -> [UIViewController]? {
        defer { self.setupTabBarHidden(animated: animated) }
        return super.popToRootViewController(animated: animated)
    }
    
    open override func popViewController(animated: Bool) -> UIViewController? {
        defer { self.setupTabBarHidden(animated: animated) }
        return super.popViewController(animated: animated)
    }
    
    /// FIXME: 仅适用iOS18+, (`iOS26`上无法规避手势滑动, 如果pop滑动又取消掉了, 仍存在问题)
    private func setupTabBarHidden(animated: Bool) {
        if #available(iOS 18.0, *) {
            let isHidden = viewControllers.count > 1
            tabBarController?.setTabBarHidden(isHidden, animated: false)
        }
    }
}

// MARK: - UIGestureRecognizerDelegate

extension NavigationController: UIGestureRecognizerDelegate {

    /// 自定义 leftBarButtonItem / hidesBackButton 后，系统会丢掉默认侧滑，这里补回。
    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer == interactivePopGestureRecognizer
                || isContentPopGesture(gestureRecognizer) else {
            return true
        }
        let isRootViewController = viewControllers.count <= 1
        let isEnabledByTopViewController = (topViewController as? ViewController)?.enablePopGestureRecognizer ?? true
        return !isRootViewController && isEnabledByTopViewController
    }
}
