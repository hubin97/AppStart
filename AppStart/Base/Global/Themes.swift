//
//  Themes.swift
//  AppStart
//
//  Created by hubin.h on 2023/12/6.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation

/// `Themes.font`
public typealias Fonts = Themes.font
/// `Themes.color`
public typealias Colors = Themes.color

// MARK: -
public enum FigmaWeight: Int {
    case w100 = 100
    case w200 = 200
    case w300 = 300
    case w400 = 400
    case w500 = 500
    case w600 = 600
    case w700 = 700
    case w800 = 800
    case w900 = 900

    public var weight: UIFont.Weight {
        switch self {
        case .w100: return .ultraLight
        case .w200: return .thin
        case .w300: return .light
        case .w400: return .regular
        case .w500: return .medium
        case .w600: return .semibold
        case .w700: return .bold
        case .w800: return .heavy
        case .w900: return .black
        }
    }
}

// 系统字号映射
extension UIFont.TextStyle {
    
    public static func from(size: CGFloat) -> UIFont.TextStyle {
        switch size {
        case 34...:    return .largeTitle     // 34pt+
        case 28...33:  return .title1         // 28pt
        case 22...27:  return .title2         // 22pt
        case 20...21:  return .title3         // 20pt
        case 18...19:  return .headline       // 17pt (语义上用于标题)
        case 16...17:  return .body           // 17pt
        case 15:       return .callout        // 15pt (新增关键项)
        case 14:       return .subheadline    // 14pt
        case 12...13:  return .footnote       // 13pt
        case 11:       return .caption1       // 11pt
        case 10:       return .caption2       // 10pt
        default:       return .caption2       // <10pt
        }
    }
}

// MARK: -
public enum Themes {

    public enum font {

        /// 动态字体 case 1
        public static func dynamicFont(ofSize size: CGFloat, weight: UIFont.Weight) -> UIFont {
            let font = UIFont.systemFont(ofSize: size, weight: weight)
            return UIFontMetrics.default.scaledFont(for: font)
        }
        /// 动态字体 case 2
        public static func dynamicFont(ofSize size: CGFloat, fweight: FigmaWeight) -> UIFont {
            let font = UIFont.systemFont(ofSize: size, weight: fweight.weight)
            return UIFontMetrics.default.scaledFont(for: font)
        }
        /// 常规字体
        public static func regular(_ size: CGFloat, autoScale: Bool = true) -> UIFont {
            dynamicFont(ofSize: autoScale ? kScaleW(size) : size, weight: .regular)
        }
        /// 中等字体
        public static func medium(_ size: CGFloat, autoScale: Bool = true) -> UIFont {
            dynamicFont(ofSize: autoScale ? kScaleW(size) : size, weight: .medium)
        }
        /// 加粗字体
        public static func semibold(_ size: CGFloat, autoScale: Bool = true) -> UIFont {
            dynamicFont(ofSize: autoScale ? kScaleW(size) : size, weight: .semibold)
        }
        /// 重粗字体
        public static func bold(_ size: CGFloat, autoScale: Bool = true) -> UIFont {
            dynamicFont(ofSize: autoScale ? kScaleW(size) : size, weight: .bold)
        }
        
        /// 适配figma动态字体
        /// Fonts.figma(size)(weight); Fonts.figma(.w500)(16)
        ///
        /// - Parameters:
        ///   - weight: `FigmaWeight` figma字体大小
        ///   - dynamic: 动态字体(跟随系统), 默认开启
        ///   - scale: 字体缩放(跟随屏幕大小, 默认6s大小375*667尺寸), 默认开启
        /// - Returns: 字体大小
        public static func figma(_ weight: FigmaWeight, dynamic: Bool = true, scale: Bool = true) -> (CGFloat) -> UIFont {
            if dynamic {
                return { size in
                    dynamicFont(ofSize: scale ? kScaleW(size) : size, weight: weight.weight)
                }
            }
            return { size in
                return UIFont.systemFont(ofSize: scale ? kScaleW(size): size, weight: weight.weight)
            }
        }
        
        /// 系统动态文本样式
        /// - Parameters:
        ///   - size: 大小
        ///   - weight: 字重
        ///   - style: 文本样式
        /// - Returns: UIFont
        public static func dynamicStyle(_ size: CGFloat, weight: UIFont.Weight, style: UIFont.TextStyle? = nil) -> UIFont {
            let baseSize = kScaleW(size)
            let textStyle = style ?? .from(size: size)
            let font = UIFont.systemFont(ofSize: baseSize, weight: weight)
            return UIFontMetrics(forTextStyle: textStyle).scaledFont(for: font)
        }
    }
    
    public enum color {}
}
