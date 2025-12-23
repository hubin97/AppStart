//
//  NaviBar.swift
//  AppStart
//
//  Created by hubin.h on 2024/3/11.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation
import SnapKit

// MARK: - global var and methods
protocol NaviBarDelegate: AnyObject {
    func backAction()
    func rightAction()
}

extension NaviBarDelegate {
    func rightAction() {}
    func backAction() {}
}

// MARK: - main class
public class NaviBar: UIView {
    
    public var title: String? {
        didSet {
            titleView.title = title
        }
    }
    
    public var textColor: UIColor = .black {
        didSet {
            titleView.titleLabel.textColor = textColor
        }
    }
    
    /// 是否启用高斯模糊背景
    public var isBlurEnabled: Bool {
        get { !blurView.isHidden }
        set {
            blurView.isHidden = !newValue
            backgroundColor = newValue ? .clear: .white
        }
    }

    weak var delegate: NaviBarDelegate?
        
    public var leftView: UIView?
    public var rightView: UIView?

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
        view.frame = CGRect(x: 0, y: 0, width: kScreenW, height: kNavBarAndSafeHeight)
        view.isHidden = true // 默认不开启
        return view
    }()

    override init(frame: CGRect) {
        super.init(frame: CGRect(x: 0, y: 0, width: kScreenW, height: kNavBarAndSafeHeight))
        self.backgroundColor = .white
        self.addSubview(blurView)
        self.addSubview(backButton)
        self.addSubview(titleView)
        self.leftView = backButton
        self.setupConstraints()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupConstraints() {
        backButton.snp.makeConstraints { make in
            make.leading.equalToSuperview()
            make.top.equalToSuperview().offset(kStatusBarHeight)
            make.width.height.equalTo(kNavBarHeight)
        }
        
        titleView.snp.makeConstraints { make in
            make.top.equalToSuperview().offset(kStatusBarHeight)
            make.leading.equalTo(backButton.snp.trailing).offset(10)
            make.centerX.equalToSuperview()
            make.height.equalTo(kNavBarHeight)
        }
    }
    
    @objc func backAction(_ sender: UIButton) {
        delegate?.backAction()
    }
    
    @objc func rightAction(_ sender: UIButton) {
        delegate?.rightAction()
    }
    
    func setBackButton() {}
    
    //
    public func setLeftView(_ tmpView: UIView) {
        self.leftView?.removeFromSuperview()
        self.addSubview(tmpView)
        
        let sizeH = tmpView.height
        let oX = tmpView.origin.x == 0 ? 10 : tmpView.origin.x
        let oY = kStatusBarHeight + (kNavBarHeight - sizeH)/2
        
        tmpView.snp.makeConstraints { make in
            make.leading.equalToSuperview().offset(oX)
            make.top.equalToSuperview().offset(oY)
            make.size.equalTo(tmpView.frame.size)
        }
        
        titleView.snp.remakeConstraints { make in
            make.top.equalToSuperview().offset(kStatusBarHeight)
            make.leading.equalTo(tmpView.snp.trailing).offset(10)
            make.centerX.equalToSuperview()
            make.height.equalTo(kNavBarHeight)
        }
        
        self.leftView = tmpView
    }
    
    public func setRightView(_ tmpView: UIView?) {
        self.rightView?.removeFromSuperview()
        guard let tmpView = tmpView else {
            self.rightView = nil
            return
        }
        self.addSubview(tmpView)
        
        let sizeH = tmpView.height
        let oX = tmpView.origin.x == 0 ? 10 : tmpView.origin.x
        let oY = kStatusBarHeight + (kNavBarHeight - sizeH)/2

        tmpView.snp.makeConstraints { make in
            make.trailing.equalToSuperview().inset(oX)
            make.top.equalToSuperview().offset(oY)
            make.size.equalTo(tmpView.frame.size)
        }
        
        self.rightView = tmpView
    }
    
    public override func layoutSubviews() {
        super.layoutSubviews()
        
        // FIXME: 保证titleView对称居中, (仅当左右视图都存在时 才需要调整)
        if let leftView = leftView, let rightView = rightView {
            let marign_left = leftView.frame.minX + leftView.width
            let marign_right = bounds.width - rightView.frame.minX
            let margin_max = max(marign_left, marign_right)
            let offsetX = margin_max - marign_left + 5
            // print("marign_left: \(marign_left) marign_right: \(marign_right)")
            
            titleView.snp.remakeConstraints { make in
                make.top.equalToSuperview().offset(kStatusBarHeight)
                make.leading.equalTo(leftView.snp.trailing).offset(offsetX)
                make.centerX.equalToSuperview()
                make.height.equalTo(kNavBarHeight)
            }
        }
    }
}

// MARK: - private mothods
extension NaviBar {
    
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
            _titleLabel.frame = bounds
            _titleLabel.textColor = .black
            _titleLabel.textAlignment = .center
            _titleLabel.font = UIFont.systemFont(ofSize: 17, weight: .medium)
            return _titleLabel
        }()
        
        override init(frame: CGRect) {
            super.init(frame: frame)
            self.addSubview(titleLabel)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        override func layoutSubviews() {
            super.layoutSubviews()
            self.titleLabel.frame = bounds
        }
    }
}

// MARK: - other classes
