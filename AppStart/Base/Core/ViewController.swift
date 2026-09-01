//
//  ViewController.swift
//  LuteExample
//
//  Created by hubin.h on 2023/11/10.
//  Copyright © 2025 hubin.h. All rights reserved.

import UIKit
import SnapKit

// MARK: - global var and methods

// MARK: - main class
@MainActor
open class ViewController: UIViewController, Navigatable, NaviBarDelegate {
        
    public var viewModel: ViewModel?
    // 不用 `= .default` 属性初值：`Navigator.default` 是 @MainActor，非隔离默认值在 Swift 6 宿主会报错。
    public var navigator: Navigator

    public init(viewModel: ViewModel?, navigator: Navigator? = nil) {
        self.viewModel = viewModel
        self.navigator = navigator ?? .default
        super.init(nibName: nil, bundle: nil)
    }
    
    public init() {
        self.navigator = .default
        super.init(nibName: nil, bundle: nil)
    }
    
    required public init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    /// 默认开启左滑导航手势
    public var enablePopGestureRecognizer = true {
        didSet {
            (navigationController as? NavigationController)?.updatePopGestureAvailability()
        }
    }
    
    public lazy var naviBar: NaviBar = {
        let _naviBar = NaviBar()
        _naviBar.delegate = self
        return _naviBar
    }()
    
    /// `isLiquidGlassEnabled` 时把 `NaviBar` 同步到系统栏；否则为 nil。
    private var naviBarAdapter: NaviBarAdapter?
    
    open override func viewDidLoad() {
        super.viewDidLoad()
        self.view.backgroundColor = .white
        self.view.addSubview(naviBar)
        
        if NaviBar.usesSystemBar {
            installSystemBarAdapter()
        } else {
            installLegacyNavigationOverlay()
        }

        self.setupLayout()
        self.bindViewModel()
    }
    
    /// 系统栏负责视觉；`naviBar` 高度 0 且内容已隐藏，旧页面仍可约束 `naviBar.snp.bottom`。
    private func installSystemBarAdapter() {
        naviBar.snp.makeConstraints { make in
            make.leading.trailing.equalToSuperview()
            make.top.equalTo(view.safeAreaLayoutGuide.snp.top)
            make.height.equalTo(0)
        }
        let adapter = NaviBarAdapter()
        adapter.attach(to: self, naviBar: naviBar)
        naviBarAdapter = adapter
    }
    
    /// 隐藏系统栏，使用自定义 `NaviBar`（含 iOS 26 兼容模式）。
    private func installLegacyNavigationOverlay() {
        edgesForExtendedLayout = [.left, .right, .bottom]
        extendedLayoutIncludesOpaqueBars = false
        
        naviBar.snp.makeConstraints { make in
            make.top.leading.trailing.equalToSuperview()
            make.bottom.equalTo(view.safeAreaLayoutGuide.snp.top).offset(kNavBarHeight)
        }
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        if NaviBar.usesSystemBar {
            navigationController?.setNavigationBarHidden(naviBar.isHidden, animated: animated)
            naviBarAdapter?.applyToSystemBar()
        } else {
            navigationController?.setNavigationBarHidden(true, animated: animated)
        }
    }
    
    deinit {
        print("\(String(describing: type(of: self))) deinit")
    }
    
    // MARK: 状态栏
    // 注意: 依赖
    // 1. Info.plist 设置 View controller-based status bar appearance = YES
    // 2. UINavigationController 重写了childForStatusBarStyle, childForStatusBarHidden方法
    private(set) var statusBarStyle: UIStatusBarStyle = .darkContent
    open override var preferredStatusBarStyle: UIStatusBarStyle {
        return statusBarStyle
    }
    
    /// 刷新状态栏样式
    public func updateStatusBar(with style: UIStatusBarStyle) {
        guard statusBarStyle != style else { return }
        self.statusBarStyle = style
        self.setNeedsStatusBarAppearanceUpdate()
    }
    
    open override var prefersStatusBarHidden: Bool {
        return hideStatusBar
    }
    
    /// 显示/隐藏状态栏
    public var hideStatusBar = false {
        didSet {
            if oldValue != hideStatusBar {
                self.setNeedsStatusBarAppearanceUpdate()
            }
        }
    }

    // MARK: 配置
    /// 设置布局
    open func setupLayout() {
    
    }
    
    /// viewModel绑定
    open func bindViewModel() {}
    
    // MARK: 导航栏事件
    open func backAction() {
        if self.presentingViewController != nil {
            self.dismiss(animated: true)
        } else {
            self.navigationController?.popViewController(animated: true)
        }
    }
    open func rightAction() {}
    
    open func popGestureAction() {}
    
    // MARK: 是否旋转
    open override var shouldAutorotate: Bool {
        return false
    }
    open override var supportedInterfaceOrientations: UIInterfaceOrientationMask {
        return .portrait
    }
    open override var preferredInterfaceOrientationForPresentation: UIInterfaceOrientation {
        return .portrait
    }
}
