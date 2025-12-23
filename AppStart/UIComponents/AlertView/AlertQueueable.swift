//
//  AlertQueueable.swift
//  AppTemplate
//
//  Created by hubin.h on 2025/12/8.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation

// MARK: - Global Variables & Functions (if necessary)
public enum AlertPriority: Int, Comparable {
    case normal      = 0     // 普通优先级
    case high        = 1     // 较高优先级
    case higher      = 2     // 更高优先级
    case force       = 3     // 强制优先级, 插队显示, 但不清空队列
    case fatal       = 9999  // 致命优先级, 插队显示, 清空队列(< fatal级别的), 仅推荐在用户态丢失, 或者其它具有破坏性等场景下使用
    
    // Comparable 协议实现
    public static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

// MARK: - Main Class
public protocol AlertQueueable {
    var priority: AlertPriority { get }
}

// MARK: - Utilities & Helpers
// !!!!: 注意. 这个`AlertContainable`的扩展[只作用于同时遵循 AlertQueueable 和 UIView 的类型]。
extension AlertContainable where Self: AlertQueueable & UIView {
    public func show(in parentView: UIView? = nil) {
        AlertQueueCoordinator.shared.enqueue(self)
    }
 
    // FIXME: 后续把 AlertContainable的 show 动画部分抽离复用
    public func _presentInWindow() {
        guard let window = kAppKeyWindow else { return }
        // 布局基础视图
        setupBaseViews(in: window)
        // 布局额外视图
        setupAdditionalViews()
        
        window.addSubview(self)

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
}
