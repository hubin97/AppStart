//
//  Extension+Date.swift
//  AppStart
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 hubin.h. All rights reserved.
//

import Foundation

//MARK: - global var and methods
fileprivate typealias Extension_Date = Date

//MARK: - main class
extension Extension_Date {

    // 跟随用户所选日历变动
    //public static let calendar = Calendar.autoupdatingCurrent

    /// 当前是哪年
    public var year: Int {
        Calendar.autoupdatingCurrent.component(.year, from: self)
    }
    
    /// 当前是几月
    public var month: Int {
        Calendar.autoupdatingCurrent.component(.month, from: self)
    }

    /// 当前是几号
    public var day: Int {
        Calendar.autoupdatingCurrent.component(.day, from: self)
    }
    
    /// 当前是星期几, 从周日开始
    public var week: Int {
        return Calendar.autoupdatingCurrent.dateComponents([.year, .month, .day, .weekday], from: self).weekday! - 1
    }
    
    /// 上个月
    public var lastMonth: Date {
        return Calendar.autoupdatingCurrent.date(byAdding: .month, value: -1, to: self)!
    }
    
    /// 下个月
    public var nextMonth: Date {
        return Calendar.autoupdatingCurrent.date(byAdding: .month, value: 1, to: self)!
    }
    
    /// 上一周
    public var lastWeek: Date {
        return Calendar.autoupdatingCurrent.date(byAdding: .day, value: -7, to: self)!
    }
    
    /// 下一周
    public var nextWeek: Date {
        return Calendar.autoupdatingCurrent.date(byAdding: .day, value: 7, to: self)!
    }
    
    /// 后一天
    public var nextDay: Date {
        return Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: self)!
    }
    
    /// 前一天
    public var lastDay: Date {
        return Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: self)!
    }
}

//MARK: - private mothods
extension Extension_Date {

    /// 获取当前 秒级 时间戳
    public var timeStamp: Int {
        return Int(self.timeIntervalSince1970)
    }

    /// 获取当前 毫秒级 时间戳 - 13位
    public var milliStamp: Int {
        return Int(CLongLong(round(self.timeIntervalSince1970 * 1000)))
    }

    /// 按自定义 format 转字符串；`timeZone` 跟随系统。
    ///
    /// - Parameter locale: 默认 `.autoupdatingCurrent`，适合 UI / 业务展示。
    ///   仅在以下场景显式传 `Locale(identifier: "en_US_POSIX")`：
    ///   - 与服务端约定的固定格式（序列化 / 反序列化、签名字段）
    ///   - 日志、文件名、埋点等需跨用户 locale 稳定输出
    ///   - format 虽为数字模板，但仍需排除 locale 对符号的干扰时
    public func format(
        with format: String = "yyyy-MM-dd HH:mm:ss",
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        formatted(with: format, timeZone: .autoupdatingCurrent, locale: locale)
    }

    /// 按指定时区与 format 转字符串；`locale` 语义同 `format(with:locale:)`。
    ///
    /// 时区示例：`Asia/Shanghai`、`America/New_York`、`GMT`
    public func format(
        with format: String = "yyyy-MM-dd HH:mm:ss",
        identifier: String,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        formatted(
            with: format,
            timeZone: TimeZone(identifier: identifier) ?? .autoupdatingCurrent,
            locale: locale
        )
    }

    private func formatted(with format: String, timeZone: TimeZone, locale: Locale) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        dateFormatter.timeZone = timeZone
        dateFormatter.locale = locale
        return dateFormatter.string(from: self)
    }
}

//MARK: - call backs
extension Extension_Date {
    
}

//MARK: - delegate or data source
extension Extension_Date {
    
}

//MARK: - other classes
