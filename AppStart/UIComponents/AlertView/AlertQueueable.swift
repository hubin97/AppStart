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
    
    // 其实仅提供给 AlertQueueCoordinator 调用
    func _presentInWindow() {
        guard let window = kAppKeyWindow else { return }
        self.display(in: window)
    }
}
