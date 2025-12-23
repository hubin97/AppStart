//
//  AlertQueueCoordinator.swift
//  AppTemplate
//
//  Created by hubin.h on 2025/12/8.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation

// MARK: - Global Variables & Functions (if necessary)

// MARK: - Main Class
final class AlertQueueCoordinator {

    static let shared = AlertQueueCoordinator()

    private init() {}

    /// 队列存储
    private var queue: [AlertContainable & AlertQueueable & UIView] = []

    /// 当前展示弹窗
    private weak var presenting: (AlertContainable & AlertQueueable & UIView)?

    /// 当前是否有正在展示或等待展示的 fatal alert
    private var hasFatalPending: Bool {
        return presenting?.priority == .fatal || queue.contains(where: { $0.priority == .fatal })
    }
    
    /// 入队
    func enqueue(_ alert: (AlertContainable & AlertQueueable & UIView)) {

        switch alert.priority {

        case .fatal:
            if hasFatalPending {
                // 当前就是 fatal，新的 fatal 直接入队
                queue.removeAll(where: { $0.priority != .fatal })
                queue.append(alert)
                return
            }
            
            // 到这里说明当前没有在展示 fatal：
            // 1) 删除队列中所有非-fatal；保留已有的 fatal（如果有）
            queue.removeAll(where: { $0.priority != .fatal })
            
            // 2) 新的 fatal 直接入队
            queue.append(alert)

            // 3) 打断当前正在展示的（可能是 normal/high/force），并触发下一步展示
            presenting?.removeFromSuperview()
            presenting = nil
            
            // 4) 尝试展示（show 逻辑在 tryShowNext / showAlert 中）
            tryShowNext()

        case .force:
            // 如果当前是 fatal，force 不能打断，直接丢弃
            if hasFatalPending {
                print("⚠️ force ignored: fatal is presenting")
                return
            }

            // 当前展示的是普通/high/higher → 打断并重新入队
            if let p = presenting, p.priority < .force {
                queue.insert(p, at: 0)
                queue.sort { $0.priority.rawValue > $1.priority.rawValue }
                presenting?.removeFromSuperview()
                presenting = nil
            }
     
            // 插入队列：所有普通/high/higher 前面，保持 FIFO
            if let firstNonForceIndex = queue.firstIndex(where: { $0.priority < .force }) {
                queue.insert(alert, at: firstNonForceIndex)
            } else {
                queue.append(alert) // 队列中没有普通/high/higher，直接排在末尾
            }
            
            tryShowNext()
            
        default:
            // 如果当前有 fatal 在展示，所有非 fatal 直接忽略
            if hasFatalPending {
                print("⚠️ normal/high ignored: fatal is presenting")
                return
            }

            queue.append(alert)
            queue.sort { $0.priority.rawValue > $1.priority.rawValue }

            tryShowNext()
        }
    }
}

// MARK: - Private Methods
extension AlertQueueCoordinator {
    
    /**
     // 延迟0.3是为了规避多个force/fatal弹出情况, 稳定性可以进一步优化 ?
     并非多个弹出问题, 而是因为调用了下面的 hide()方法, 触发了onStateChange回调, 而回调里面又调用了 tryShowNext 方法, 导致了重叠
     所以前面入队时的
     presenting?.hide()
     presenting = nil
     改为
     presenting?.removeFromSuperview()
     presenting = nil
     */
    private func tryShowNext() {
        if presenting != nil { return }
        
        guard let next = self.queue.first else { return }
        
        self.queue.removeFirst()
        self.presenting = next
        
        self.showAlert(next)
    }

    private func showAlert(_ alert: (AlertContainable & AlertQueueable & UIView)) {
        alert.onStateChange = { [weak self] state in
            guard let self = self else { return }
            if state == .didHide {
                self.presenting = nil
                self.tryShowNext()
            }
        }
        // ❌ alert.show(in: nil) 会 enqueue -死循环
        // 改为内部显示，不经过队列：
        alert._presentInWindow()
    }
}

// MARK: - Callbacks
extension AlertQueueCoordinator {
}

// MARK: - Utilities & Helpers
extension AlertQueueCoordinator {
}

// MARK: - Delegate & Data Source
extension AlertQueueCoordinator {
}
