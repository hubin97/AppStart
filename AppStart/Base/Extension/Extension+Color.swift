//
//  Extension+Color.swift
//  AppStart
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 hubin.h. All rights reserved.
//

//单元测试 ✅
import Foundation

//MARK: - global var and methods
fileprivate typealias Extension_Color = UIColor

//MARK: - main class

//MARK: - private mothods
extension Extension_Color {

    /// 获取随机色
    public static var random: UIColor {
        return UIColor(red: CGFloat(arc4random()%256)/255.0, green: CGFloat(arc4random()%256)/255.0, blue: CGFloat(arc4random()%256)/255.0, alpha: 1)
    }

    /// 整型(16进制)初始化
    /// - Parameters:
    ///   - hexValue: 0xFFFFFF
    ///   - alpha: 透明度, 默认1
    public convenience init(hexValue: Int, alpha: CGFloat = 1) {
        self.init(red: ((CGFloat)((hexValue & 0xFF0000) >> 16)) / 255.0, green: ((CGFloat)((hexValue & 0xFF00) >> 8)) / 255.0, blue: ((CGFloat)(hexValue & 0xFF)) / 255.0, alpha: alpha)
    }
    
    /// 字符串初始化
    /// - Parameters:
    ///   - hexStr: #0xFFFFFF
    ///   - alpha: 透明度, 默认1
    public convenience init(hexStr: String, alpha: CGFloat = 1) {
        self.init(hexValue: Self.strictHexValue(from: hexStr) ?? 0, alpha: alpha)
    }

    /// 严格字符串初始化，仅接受带可选 `#` / `0x` / `0X` 前缀的 6 位 RGB 十六进制字符串。
    /// - Parameters:
    ///   - strictHexStr: #FFFFFF、0xFFFFFF/0XFFFFFF 或 FFFFFF
    ///   - alpha: 透明度, 默认1
    public convenience init?(strictHexStr: String, alpha: CGFloat = 1) {
        guard let hexValue = Self.strictHexValue(from: strictHexStr) else { return nil }
        self.init(hexValue: hexValue, alpha: alpha)
    }

    /// 严格字符串初始化，仅接受带可选 `#` / `0x` / `0X` 前缀的 6 位 RGB 十六进制字符串。
    private static func strictHexValue(from hexStr: String) -> Int? {
        var value = hexStr.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.hasPrefix("#") {
            value.removeFirst()
        } else if value.hasPrefix("0x") || value.hasPrefix("0X") {
            value.removeFirst(2)
        }
        guard value.count == 6 else { return nil }
        return Int(value, radix: 16)
    }
}

//MARK: - call backs
extension Extension_Color {
    
}

//MARK: - delegate or data source
extension Extension_Color {
    
}

//MARK: - other classes
