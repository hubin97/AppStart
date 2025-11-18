//
//  NavigationController.swift
//  LuteExample
//
//  Created by hubin.h on 2023/11/10.
//  Copyright © 2025 Hubin_Huang. All rights reserved.

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
        self.navigationBar.isTranslucent = false
        self.delegate = self

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
        if #available(iOS 13.0, *) {
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
        if #available(iOS 13.0, *) {
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
}

// MARK: - UINavigationControllerDelegate
extension NavigationController: UINavigationControllerDelegate {
    
    public func navigationController(_ navigationController: UINavigationController, willShow viewController: UIViewController, animated: Bool) {
        let rooVc = navigationController.viewControllers[0]
        if rooVc != viewController {
            navigationBar.backIndicatorImage = UIImage()
            navigationBar.backIndicatorTransitionMaskImage = UIImage()
            // 设置系统自带的右滑手势返回
//            interactivePopGestureRecognizer?.delegate = nil
        }
    }
    
    public func navigationController(_ navigationController: UINavigationController, didShow viewController: UIViewController, animated: Bool) {
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
