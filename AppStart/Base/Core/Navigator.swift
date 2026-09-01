//
//  Navigator.swift
//  Petcozy
//
//  Created by hubin.h on 2024/5/28.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation
import AVKit

/// 用于视图控制器导航
/// 推荐使用`枚举`来实现
@MainActor
public protocol SceneProvider {
    /// 获取视图控制器
    var getSegue: UIViewController? { get }
}

// MARK: - 路由协议
@MainActor
public protocol Navigatable {
    var navigator: Navigator { get set }
}

// MARK: - Navigator
@MainActor
public class Navigator {
    public static let `default` = Navigator()
    
    public enum Transition {
        case root(in: UIWindow)
        case navigation
        case modal(type: UIModalPresentationStyle)
        case detail
        case alert(type: UIModalPresentationStyle)
        case custom
    }
    
    public func pop(sender: UIViewController?, toRoot: Bool = false) {
        if toRoot {
            sender?.navigationController?.popToRootViewController(animated: true)
        } else {
            sender?.navigationController?.popViewController(animated: true)
        }
    }
    
    public func dismiss(sender: UIViewController?) {
        sender?.dismiss(animated: true, completion: nil)
    }
    
    @discardableResult
    public func show(provider: SceneProvider, sender: UIViewController?, transition: Transition = .navigation, animated: Bool = true) -> UIViewController? {
        guard let target = provider.getSegue else { return nil }
        self.show(target: target, sender: sender, transition: transition, animated: animated)
        return target
    }
    
    private func show(target: UIViewController, sender: UIViewController?, transition: Transition, animated: Bool = true) {
        switch transition {
        case .root(in: let window):
            window.rootViewController = target
            return
        case .custom: return
        default: break
        }
        
        guard let sender = sender else {
            fatalError("You need to pass in a sender for .navigation or .modal transitions")
        }

        switch transition {
        case .navigation:
            guard let navigationController = sender as? UINavigationController ?? sender.navigationController else {
                preconditionFailure("A navigation transition requires the sender to belong to a UINavigationController")
            }
            navigationController.pushViewController(target, animated: animated)
        case .modal(let type):
            let nav = NavigationController(rootViewController: target)
            nav.modalPresentationStyle = type
            sender.present(nav, animated: animated, completion: nil)
        case .detail:
            let nav = NavigationController(rootViewController: target)
            sender.showDetailViewController(nav, sender: nil)
        case .alert(let type):
            target.modalPresentationStyle = type
            sender.present(target, animated: animated, completion: nil)
        default: break
        }
    }
}
