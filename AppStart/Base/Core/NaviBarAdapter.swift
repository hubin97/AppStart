//
//  NaviBarAdapter.swift
//  AppStart
//
//  Created by hubin.h on 2026/9/1.
//  Copyright © 2025 hubin.h. All rights reserved.

import UIKit

// MARK: - main class

/// 把 `NaviBar` 的状态同步到系统 `UINavigationItem` / `UINavigationBar`（iOS 26 Liquid Glass）。
@MainActor
final class NaviBarAdapter {

    private weak var viewController: UIViewController?
    private weak var naviBar: NaviBar?
    private var hiddenObservations: [NSKeyValueObservation] = []

    // MARK: Attach

    func attach(to viewController: UIViewController, naviBar: NaviBar) {
        self.viewController = viewController
        self.naviBar = naviBar
        naviBar.systemBarUpdater = self
        applyTransparentAppearance()
        observeSideViewVisibility()
        applyToSystemBar()
    }

    /// 以 `NaviBar` 为准，写到当前页的 `navigationItem` / `UINavigationBar`。
    /// `viewDidLoad` 时导航控制器可能还没挂上，所以 `viewWillAppear` 会再调一次。
    func applyToSystemBar() {
        guard let viewController, let naviBar else { return }

        applyTransparentAppearance()
        viewController.navigationItem.title = naviBar.title
        applyLeftItems(from: naviBar)
        viewController.navigationItem.rightBarButtonItems = barButtonItems(from: naviBar.rightView)
        applyTitleAppearance(textColor: naviBar.textColor)
    }

    // MARK: Appearance

    private func applyTransparentAppearance() {
        guard let navigationBar = viewController?.navigationController?.navigationBar else { return }
        NavigationController.applySystemBarAppearance(
            to: navigationBar,
            titleTextAttributes: titleTextAttributes(for: naviBar?.textColor ?? .label)
        )
        navigationBar.tintColor = naviBar?.textColor
    }

    private func applyTitleAppearance(textColor: UIColor) {
        let attributes = titleTextAttributes(for: textColor)
        let appearance = UINavigationBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.shadowColor = .clear
        appearance.titleTextAttributes = attributes

        viewController?.navigationItem.standardAppearance = appearance
        viewController?.navigationItem.scrollEdgeAppearance = appearance
        viewController?.navigationItem.compactAppearance = appearance
        viewController?.navigationController?.navigationBar.tintColor = textColor
    }

    private func titleTextAttributes(for textColor: UIColor) -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: textColor,
            .font: UIFont.systemFont(ofSize: 17, weight: .medium)
        ]
    }

    // MARK: Bar items

    /// 默认返回留给系统按钮，侧滑手势才不会被 `hidesBackButton` 掐掉。
    private func applyLeftItems(from naviBar: NaviBar) {
        guard let viewController else { return }

        let leftView = naviBar.leftView
        if leftView == nil || leftView?.isHidden == true {
            viewController.navigationItem.hidesBackButton = true
            viewController.navigationItem.leftBarButtonItems = nil
            return
        }

        if leftView === naviBar.backButton {
            viewController.navigationItem.hidesBackButton = false
            viewController.navigationItem.leftBarButtonItems = nil
            return
        }

        viewController.navigationItem.hidesBackButton = true
        viewController.navigationItem.leftBarButtonItems = barButtonItems(from: leftView)
    }

    /// 单图标按钮升级为 `UIBarButtonItem`，以拿到系统玻璃底与分组；复杂容器退回 customView。
    private func barButtonItems(from view: UIView?) -> [UIBarButtonItem] {
        guard let view, !view.isHidden else { return [] }

        if let button = view as? UIButton {
            return [makeBarButtonItem(from: button)]
        }

        let buttons = view.subviews.compactMap { $0 as? UIButton }
        if !buttons.isEmpty, buttons.count == view.subviews.count {
            return buttons.filter { !$0.isHidden }.map { makeBarButtonItem(from: $0) }
        }

        return [UIBarButtonItem(customView: view)]
    }

    private func makeBarButtonItem(from button: UIButton) -> UIBarButtonItem {
        let title = button.title(for: .normal) ?? ""
        let image = resolvedImage(from: button)?.withRenderingMode(.alwaysTemplate)

        if let image, title.isEmpty {
            let item = UIBarButtonItem(image: image, style: .plain, target: nil, action: nil)
            item.primaryAction = UIAction { [weak button] _ in
                button?.sendActions(for: .touchUpInside)
            }
            return item
        }

        return UIBarButtonItem(customView: button)
    }

    private func resolvedImage(from button: UIButton) -> UIImage? {
        if let image = button.image(for: .normal) { return image }
        if #available(iOS 15.0, *) {
            return button.configuration?.image
        }
        return nil
    }

    // MARK: Visibility

/// `isHidden` 不走 `NaviBar` 的 didSet，左右按钮显隐只能 KVO。
    private func observeSideViewVisibility() {
        hiddenObservations.removeAll()
        observeHidden(naviBar?.leftView)
        observeHidden(naviBar?.rightView)
    }

    private func observeHidden(_ view: UIView?) {
        guard let view else { return }
        let observation = view.observe(\.isHidden, options: [.new]) { [weak self] _, _ in
            Task { @MainActor in
                self?.applyToSystemBar()
            }
        }
        hiddenObservations.append(observation)
    }
}

// MARK: - NaviBarSyncing

extension NaviBarAdapter: NaviBarSyncing {

    func naviBarDidChange(_ naviBar: NaviBar) {
        observeSideViewVisibility()
        applyToSystemBar()
    }
}
