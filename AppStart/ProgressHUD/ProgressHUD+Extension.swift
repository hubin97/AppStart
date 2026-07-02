//
//  Extension+ProgressHUD.swift
//  AppStart
//
//  Created by hubin.h on 2024/11/7.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation

// MARK: - 外部集成 Lottie 示例
//
// 本库不内置 Lottie 依赖。业务工程自行 `pod 'lottie-ios'` 后，
// 新建 `ProgressHUD+Lottie.swift`，在 extension 里封装即可：
//
// ```swift
// import UIKit
// import Lottie
// import AppStart
//
// // 简易：LottieAnimationView 直接交给 ProgressHUD.custom
// ProgressHUD.showSimpleLottieLoading(named: "loading")
//
// // 卡片：自定义 LottieLoadingCardView（白底圆角 + 文案）
// ProgressHUD.showLottieLoading(named: "loading", message: "加载中...")
// ProgressHUD.dismiss()
// ```

/// ProgressHUD扩展
extension ProgressHUD {
    /// 计算显示时长
    private static func duration(_ content: String, minDuration: TimeInterval = 1.0) -> TimeInterval {
        return max(Double(content.count) * 0.06 + 0.5, 1)
    }

    /// 显示加载中
    /// - Parameters:
    ///   - status: 文本
    ///   - interaction: 是否允许交互
    ///   - delayDismss: 延时隐藏
    ///   - completion: 完成回调
    public static func showLoading(_ status: String? = nil, interaction: Bool = false, delayDismss: TimeInterval? = nil, completion: (() -> Void)? = nil) {
        ProgressHUD.animate(status, interaction: interaction)
        
        if let delay = delayDismss {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ProgressHUD.dismiss()
                completion?()
            }
        }
    }

    /// 显示进度
    /// - Parameters:
    ///   - text: 文本
    ///   - value: 进度值 0.0-1.0
    ///   - interaction: 是否允许交互
    ///   - completion: 完成回调
    public static func showProgress(_ text: String? = nil, _ value: CGFloat, interaction: Bool = false, completion: (() -> Void)? = nil) {
        ProgressHUD.progress(text, value, interaction: interaction)
        
        if value >= 1 {
            completion?()
        }
    }

    /// 显示成功提示
    /// - Parameters:
    ///   - status: 文本
    ///   - delay: 延时隐藏
    ///   - completion: 完成回调
    public static func showSuccess(_ status: String?, interaction: Bool = false, delay: TimeInterval? = nil, completion: (() -> Void)? = nil) {
        let delay = delay ?? duration(status ?? "")
        ProgressHUD.success(status, interaction: interaction, delay: delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completion?()
        }
    }
    
    /// 显示失败提示
    /// - Parameters:
    ///   - status: 文本
    ///   - delay: 延时隐藏
    ///   - completion: 完成回调
    public static func showError(_ status: String?, interaction: Bool = false, delay: TimeInterval? = nil, completion: (() -> Void)? = nil) {
        let delay = delay ?? duration(status ?? "")
        ProgressHUD.error(status, interaction: interaction, delay: delay)
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            completion?()
        }
    }
    
    /// 隐藏提示
    /// - Parameters:
    ///   - delay: 延时隐藏
    ///   - completion: 隐藏回调
    public static func dismiss(delay: TimeInterval? = nil, completion: (() -> Void)? = nil) {
        if let delay = delay {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                ProgressHUD.dismiss()
                completion?()
            }
            return
        }
        ProgressHUD.dismiss()
    }
}
