//
//  AlertContainable.swift
//  AppStart
//
//  Created by hubin.h on 2025/6/5.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation

// MARK: - Global Variables & Functions (if necessary)

// 状态声明
public enum AlertState {
    case willShow       // 将要展示
    case didShow        // 完全展示
    case willHide       // 将要关闭
    case didHide        // 完全关闭
}

private struct AlertContainableKeys {
    // ✅ chatgpt建议使用静态变量更安全 // UnsafeRawPointer(bitPattern: "onStateChange".hashValue)
    static var onStateChange = 0
    static var isMaskEnabled = 0
    static var usingSpringWithDamping = 0
}

public protocol AlertContainable: AnyObject {
    
    /// 弹窗内容视图，承载自定义内容
    var containerView: UIView { get }

    /// 是否显示背景蒙层，默认 true
    var isMaskEnabled: Bool { get }

    /// 使用阻尼动效, 默认开启
    var usingSpringWithDamping: Bool { get }
    
    /// 显示弹窗
    func show(in parentView: UIView?)

    /// 隐藏弹窗
    func hide(completion: (() -> Void)?)
    
    /// 设置基础视图元素
    func setupBaseViews(in parentView: UIView?)

    /// 设置额外视图元素
    func setupAdditionalViews()
    
    /// 补充一个状态回调, 需要埋点弹框页面访问
    var onStateChange: ((AlertState) -> Void)? { get set }
    func stateDidChange(to state: AlertState)
}

extension AlertContainable where Self: UIView {

    public var onStateChange: ((AlertState) -> Void)? {
        get {
            objc_getAssociatedObject(self, &AlertContainableKeys.onStateChange) as? ((AlertState) -> Void)
        }
        set {
            objc_setAssociatedObject(self, &AlertContainableKeys.onStateChange, newValue, .OBJC_ASSOCIATION_COPY_NONATOMIC)
        }
    }
    
    public var isMaskEnabled: Bool {
        get {
            objc_getAssociatedObject(self, &AlertContainableKeys.isMaskEnabled) as? Bool ?? true
        }
        set {
            objc_setAssociatedObject(self, &AlertContainableKeys.isMaskEnabled, newValue, .OBJC_ASSOCIATION_ASSIGN)
        }
    }
    
    public var usingSpringWithDamping: Bool {
        get {
            objc_getAssociatedObject(self, &AlertContainableKeys.usingSpringWithDamping) as? Bool ?? true
        }
        set {
            objc_setAssociatedObject(self, &AlertContainableKeys.usingSpringWithDamping, newValue, .OBJC_ASSOCIATION_ASSIGN)
        }
    }
    
    public func setupBaseViews(in parentView: UIView? = nil) {
        guard let superview = parentView ?? UIApplication.shared.windows.first(where: \.isKeyWindow) else { return }

        self.frame = superview.bounds
        self.alpha = 0

        if isMaskEnabled {
            let maskView = UIView()
            maskView.backgroundColor = UIColor.black.withAlphaComponent(0.5)
            maskView.frame = self.bounds
            maskView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            addSubview(maskView)
        }

        addSubview(containerView)
        containerView.center = center
        containerView.autoresizingMask = [
            .flexibleTopMargin,
            .flexibleBottomMargin,
            .flexibleLeftMargin,
            .flexibleRightMargin
        ]
    }
    
    // 默认实现为空
    public func setupAdditionalViews() {}

    // 展示
    public func show(in parentView: UIView? = nil) {
        guard let superview = parentView ?? UIApplication.shared.windows.first(where: \.isKeyWindow) else { return }
        self.display(in: superview)
    }
    
    func display(in parentView: UIView) {
        // 布局基础视图
        setupBaseViews(in: parentView)
        // 布局额外视图
        setupAdditionalViews()
        
        parentView.addSubview(self)

        self.onStateChange?(.willShow)
        self.stateDidChange(to: .willShow)

        // 使用阻尼动效
        if usingSpringWithDamping {
            self.alpha = 1
            self.containerView.transform = CGAffineTransform(scaleX: 1.2, y: 1.2)
            // usingSpringWithDamping 阻尼越小弹性越大
            UIView.animate(withDuration: 0.3, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 1.0, options: [.curveEaseInOut]) {
                self.containerView.transform = .identity
            } completion: { _ in
                self.onStateChange?(.didShow)
                self.stateDidChange(to: .didShow)
            }
        } else {
            UIView.animate(withDuration: 0.25) {
                self.alpha = 1
            } completion: { _ in
                self.onStateChange?(.didShow)
                self.stateDidChange(to: .didShow)
            }
        }
    }
    
    // 关闭
    public func hide(completion: (() -> Void)? = nil) {
        self.onStateChange?(.willHide)
        self.stateDidChange(to: .willHide)
        
        UIView.animate(withDuration: 0.25) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            self.onStateChange?(.didHide)
            self.stateDidChange(to: .didHide)

            completion?()
        }
    }
    
    // 默认空实现，子类 override
    public func stateDidChange(to state: AlertState) {}
}
