//
//  AlertContainable.swift
//  Momcozy
//
//  Created by hubin.h on 2025/6/5.
//  Copyright © 2025 路特创新. All rights reserved.

import Foundation

// MARK: - Global Variables & Functions (if necessary)

// 状态声明
public enum AlertState {
    case show    // 已展示
    case hide    // 已关闭
}

private struct AlertContainableKeys {
    // ✅ chatgpt建议使用静态变量更安全 // UnsafeRawPointer(bitPattern: "onStateChange".hashValue)
    static var onStateChange = 0
}

public protocol AlertContainable: AnyObject {
    
    /// 弹窗内容视图，承载自定义内容
    var containerView: UIView { get }

    /// 是否显示背景蒙层，默认 true
    var isMaskEnabled: Bool { get }

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
    
    public func setupBaseViews(in parentView: UIView? = nil) {
        guard let superview = parentView ?? UIApplication.shared.windows.first(where: \.isKeyWindow) else { return }

        self.frame = superview.bounds
        self.alpha = 0

        if isMaskEnabled {
            let maskView = UIView()
            maskView.backgroundColor = UIColor.black.withAlphaComponent(0.2)
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
        
        // 布局基础视图
        setupBaseViews(in: parentView)
        // 布局额外视图
        setupAdditionalViews()
        
        superview.addSubview(self)

        UIView.animate(withDuration: 0.25) {
            self.alpha = 1
        } completion: { _ in
            self.onStateChange?(.show)
            self.stateDidChange(to: .show)
        }
    }
    
    // 关闭
    public func hide(completion: (() -> Void)? = nil) {
        UIView.animate(withDuration: 0.25) {
            self.alpha = 0
        } completion: { _ in
            self.removeFromSuperview()
            self.onStateChange?(.hide)
            self.stateDidChange(to: .hide)
            completion?()
        }
    }
    
    // 默认空实现，子类 override
    public func stateDidChange(to state: AlertState) {}
}
