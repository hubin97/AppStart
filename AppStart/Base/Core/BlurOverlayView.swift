//
//  BlurOverlayView.swift
//  Momcozy
//
//  Created by hubin.h on 2025/9/11.
//  Copyright © 2025 路特创新. All rights reserved.

import Foundation

/// 一个带半透明覆盖层的模糊背景视图
public final class BlurOverlayView: UIVisualEffectView {
    
    /// 半透明覆盖层
    private let overlay = UIView()
    
    /// 设置覆盖层透明度（0 ~ 1，默认 0.2）
    public var overlayAlpha: CGFloat {
        get { overlay.alpha }
        set { overlay.alpha = newValue }
    }
    
    /// 设置覆盖层颜色（默认白色）
    public var overlayColor: UIColor {
        get { overlay.backgroundColor ?? .clear }
        set { overlay.backgroundColor = newValue }
    }
    
    /// 初始化方法
    public init(style: UIBlurEffect.Style = .light,
                overlayColor: UIColor = .white,
                overlayAlpha: CGFloat = 0.2) {
        super.init(effect: UIBlurEffect(style: style))
        
        self.overlay.backgroundColor = overlayColor
        self.overlay.alpha = overlayAlpha
        self.overlay.frame = bounds
        self.overlay.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        contentView.addSubview(overlay)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
