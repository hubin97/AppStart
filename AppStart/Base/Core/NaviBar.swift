//
//  NaviBar.swift
//  AppStart
//
//  Created by hubin.h on 2024/3/11.
//  Copyright © 2025 hubin.h. All rights reserved.

import UIKit
import SnapKit

// MARK: - global var and methods
@MainActor
protocol NaviBarDelegate: AnyObject {
    func backAction()
    func rightAction()
}

extension NaviBarDelegate {
    func rightAction() {}
    func backAction() {}
}

/// 玻璃模式下 `NaviBar` 仍是业务入口，画面在系统 `UINavigationBar` 上。
/// 标题 / 左右按钮 / 颜色变化时通知适配器去改 `navigationItem`。
@MainActor
protocol NaviBarSyncing: AnyObject {
    /// `setLeftView` / `setRightView` 会换掉子视图，适配器要重绑 `isHidden` 观察后再写系统栏。
    func naviBarDidChange(_ naviBar: NaviBar)
}

// MARK: - main class
@MainActor
public class NaviBar: UIView {
    
    /// 是否改用系统 `UINavigationBar`。见 `isLiquidGlassEnabled`。
    public static var usesSystemBar: Bool { isLiquidGlassEnabled }
    
    /// 仅玻璃模式由 `NaviBarAdapter` 赋值。
    weak var systemBarUpdater: NaviBarSyncing?
    
    public var title: String? {
        didSet {
            titleView.title = title
            notifySystemBarIfNeeded()
        }
    }
    
    public var textColor: UIColor = .black {
        didSet {
            titleView.titleLabel.textColor = textColor
            notifySystemBarIfNeeded()
        }
    }
    
    /// 是否启用高斯模糊背景
    public var isBlurEnabled: Bool {
        get { !blurView.isHidden }
        set {
            blurView.isHidden = !newValue
            backgroundColor = newValue ? .clear : .white
        }
    }

    weak var delegate: NaviBarDelegate?
        
    public private(set) var leftView: UIView?
    public private(set) var rightView: UIView?

    public lazy var backButton: UIButton = {
        let _backButton = UIButton(type: .custom)
        _backButton.setImage(Asset.iconLeftBlack.image.adaptRTL, for: .normal)
        _backButton.addTarget(self, action: #selector(backAction(_:)), for: .touchUpInside)
        return _backButton
    }()

    lazy var titleView: LTTitleView = {
        let _titleView = LTTitleView()
        return _titleView
    }()
    
    lazy var blurView: BlurOverlayView = {
        let view = BlurOverlayView()
        view.isHidden = true // 默认不开启
        return view
    }()

    private let contentView = UIView()
    /// 避免 layoutSubviews 中重复 remake 标题约束
    private var titleLeadingOffset: CGFloat?

    override init(frame: CGRect) {
        super.init(frame: frame)
        self.backgroundColor = .white
        self.addSubview(blurView)
        self.addSubview(contentView)
        self.contentView.addSubview(backButton)
        self.contentView.addSubview(titleView)
        self.leftView = backButton
        
        self.setupConstraints()
        self.hideContentIfUsingSystemBar()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public override var isHidden: Bool {
        get { super.isHidden }
        set {
            super.isHidden = newValue
            notifySystemBarIfNeeded()
        }
    }
    
    private func setupConstraints() {
        blurView.snp.makeConstraints { make in
            make.edges.equalToSuperview()
        }

        // 外层已把 NaviBar 拉到 safeArea.top + 44；这里的 safeArea.top 常为 0，再钉一层会把内容区拉成整栏高。
        contentView.snp.makeConstraints { make in
            make.leading.trailing.bottom.equalToSuperview()
            make.height.equalTo(kNavBarHeight)
        }

        backButton.snp.makeConstraints { make in
            make.leading.top.bottom.equalToSuperview()
            make.width.height.equalTo(kNavBarHeight)
        }
        
        titleView.snp.makeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalTo(backButton.snp.trailing).offset(10)
            make.centerX.equalToSuperview()
        }
    }
    
    @objc func backAction(_ sender: UIButton) {
        delegate?.backAction()
    }
    
    @objc func rightAction(_ sender: UIButton) {
        delegate?.rightAction()
    }
    
    func setBackButton() {}
    
    /// 玻璃模式只当布局锚点（高度 0）。`contentView` 仍是 44pt 且默认不裁剪，会溢到系统栏上叠出双标题 / 双返回。
    private func hideContentIfUsingSystemBar() {
        guard Self.usesSystemBar else { return }
        backgroundColor = .clear
        clipsToBounds = true
        isUserInteractionEnabled = false
        contentView.isHidden = true
        blurView.isHidden = true
    }
    
    /// overlay 自己会画，不必通知。
    private func notifySystemBarIfNeeded() {
        guard Self.usesSystemBar else { return }
        systemBarUpdater?.naviBarDidChange(self)
    }
    
    //
    public func setLeftView(_ tmpView: UIView) {
        self.leftView?.removeFromSuperview()
        titleLeadingOffset = nil
        self.leftView = tmpView
        
        if Self.usesSystemBar {
            notifySystemBarIfNeeded()
            return
        }
        
        contentView.addSubview(tmpView)
        
        let oX = tmpView.origin.x == 0 ? 10 : tmpView.origin.x
        let size = sideViewPreferredSize(for: tmpView)
        
        tmpView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(oX)
            make.centerY.equalToSuperview()
            make.width.equalTo(size.width)
            make.height.equalTo(size.height)
        }
        
        titleView.snp.remakeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalTo(tmpView.snp.trailing).offset(10)
            make.centerX.equalToSuperview()
        }
    }
    
    public func setRightView(_ tmpView: UIView?) {
        self.rightView?.removeFromSuperview()
        titleLeadingOffset = nil
        guard let tmpView = tmpView else {
            self.rightView = nil
            notifySystemBarIfNeeded()
            return
        }
        
        self.rightView = tmpView
        
        if Self.usesSystemBar {
            notifySystemBarIfNeeded()
            return
        }
        
        contentView.addSubview(tmpView)
        
        let oX = tmpView.origin.x == 0 ? 10 : tmpView.origin.x
        let size = sideViewPreferredSize(for: tmpView)

        tmpView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(oX)
            make.centerY.equalToSuperview()
            make.width.equalTo(size.width)
            make.height.equalTo(size.height)
        }
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        guard !Self.usesSystemBar else { return }
        
        // FIXME: 保证titleView对称居中, (仅当左右视图都存在时 才需要调整)
        guard let leftView = leftView, let rightView = rightView else { return }
        let marign_left = leftView.frame.minX + leftView.bounds.width
        let marign_right = bounds.width - rightView.frame.minX
        guard marign_left > 0, marign_right > 0 else { return }
        
        let margin_max = max(marign_left, marign_right)
        let offsetX = margin_max - marign_left + 5
        guard titleLeadingOffset != offsetX else { return }
        titleLeadingOffset = offsetX
        // print("marign_left: \(marign_left) marign_right: \(marign_right)")
        
        titleView.snp.remakeConstraints { make in
            make.top.bottom.equalToSuperview()
            make.leading.equalTo(leftView.snp.trailing).offset(offsetX)
            make.centerX.equalToSuperview()
        }
    }
}

// MARK: - private mothods
extension NaviBar {
    
    /// Auto Layout 完成前 frame 常为 .zero，直接用 frame.size 会把左右按钮约束成 0。
    private func sideViewPreferredSize(for view: UIView) -> CGSize {
        let frameSize = view.frame.size
        if frameSize.width > 0, frameSize.height > 0 { return frameSize }
        
        let boundsSize = view.bounds.size
        if boundsSize.width > 0, boundsSize.height > 0 { return boundsSize }
        
        if !view.subviews.isEmpty {
            view.layoutIfNeeded()
            let width = view.subviews.map(\.frame.maxX).max() ?? 0
            let height = view.subviews.map(\.frame.height).max() ?? 0
            if width > 0, height > 0 {
                return CGSize(width: width, height: max(height, kNavBarHeight))
            }
        }
        
        return CGSize(width: kNavBarHeight, height: kNavBarHeight)
    }
    
    /// 更新返回按钮图标
    /// - Parameter isDark: 是否为深色主题
    private func updateBackButtonIcon(isDark: Bool) {
        // 优先处理被设置到 leftView 上的按钮（例如 WKWebController 的 backButton 或 naviLeftView 内的按钮）
        if let leftContainer = leftView {
            // 如果 leftView 本身是按钮
            if let leftButton = leftContainer as? UIButton {
                let iconImage: UIImage? = isDark
                    ? Asset.iconLeftWhite.image.adaptRTL
                    : Asset.iconLeftBlack.image.adaptRTL
                leftButton.setImage(iconImage, for: .normal)
                leftButton.tintColor = nil
                return
            }

            // 如果 leftView 是一个容器视图（例如 WKWebController.naviLeftView），遍历其中的按钮
            for sub in leftContainer.subviews {
                if let button = sub as? UIButton,
                   let image = button.image(for: .normal) {
                    if image == Asset.iconLeftBlack.image.adaptRTL || image == Asset.iconLeftWhite.image.adaptRTL {
                        // 返回按钮：黑/白互切
                        let icon = isDark ? Asset.iconLeftWhite.image.adaptRTL : Asset.iconLeftBlack.image.adaptRTL
                        button.setImage(icon, for: .normal)
                        button.tintColor = nil
                    } else if image == Asset.iconCloseBlack.image.adaptRTL || image == Asset.iconCloseWhite.image.adaptRTL {
                        // 关闭按钮：黑/白互切
                        let icon = isDark ? Asset.iconCloseWhite.image.adaptRTL : Asset.iconCloseBlack.image.adaptRTL
                        button.setImage(icon, for: .normal)
                        button.tintColor = nil
                    }
                }
            }
            // 已处理完 leftView 容器中的按钮
        }

        // 兜底：如果还在用 NaviBar 自己的 backButton
        if backButton === leftView {
            let iconImage: UIImage? = isDark
                ? Asset.iconLeftWhite.image.adaptRTL
                : Asset.iconLeftBlack.image.adaptRTL
            backButton.setImage(iconImage, for: .normal)
            backButton.tintColor = nil // 确保使用原始图标颜色
        }
    }
    
    /// 递归更新视图中的按钮图标（主要用于其它自定义按钮，使用 template 渲染）
    private func updateButtonIconsInView(_ view: UIView?, textColor: UIColor) {
        guard let view = view else { return }
        
        // 跳过 NaviBar 自己的 backButton（已在 updateBackButtonIcon 处理）
        if view === backButton { return }
        
        if let button = view as? UIButton,
           let image = button.image(for: .normal),
           image.renderingMode == .alwaysTemplate {
            button.tintColor = textColor
        }
        
        for subview in view.subviews {
            updateButtonIconsInView(subview, textColor: textColor)
        }
    }
}

// MARK: - call backs
extension NaviBar {
    
    /// 更新导航栏按钮图标以适配主题
    /// - Parameters:
    ///   - isDark: 是否为深色主题
    ///   - textColor: 文本颜色（用于 template 模式的图标）
    public func updateIcons(isDark: Bool, textColor: UIColor) {
        // 更新返回 / 关闭 等左侧按钮图标
        updateBackButtonIcon(isDark: isDark)
        
        // 更新自定义左右视图中的其它按钮图标
        updateButtonIconsInView(leftView, textColor: textColor)
        updateButtonIconsInView(rightView, textColor: textColor)
        
        notifySystemBarIfNeeded()
    }
}

// MARK: - delegate or data source
extension NaviBar {
    
    class LTTitleView: UIView {
        
        var title: String? {
            didSet {
                titleLabel.text = title
            }
        }
        
        lazy var titleLabel: UILabel = {
            let _titleLabel = UILabel()
            _titleLabel.textColor = .black
            _titleLabel.textAlignment = .center
            _titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .medium)
            return _titleLabel
        }()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            self.addSubview(titleLabel)
            titleLabel.snp.makeConstraints { make in
                make.edges.equalToSuperview()
            }
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
    }
}

// MARK: - other classes
