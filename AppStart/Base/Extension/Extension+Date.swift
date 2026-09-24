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
        Calendar.autoupdatingCurrent.component(.weekday, from: self) - 1
    }
    
    /// 上个月。日历无法计算时返回 `nil`。
    public var lastMonth: Date? {
        Calendar.autoupdatingCurrent.date(byAdding: .month, value: -1, to: self)
    }
    
    /// 下个月。日历无法计算时返回 `nil`。
    public var nextMonth: Date? {
        Calendar.autoupdatingCurrent.date(byAdding: .month, value: 1, to: self)
    }
    
    /// 上一周。日历无法计算时返回 `nil`。
    public var lastWeek: Date? {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: -7, to: self)
    }
    
    /// 下一周。日历无法计算时返回 `nil`。
    public var nextWeek: Date? {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: 7, to: self)
    }
    
    /// 后一天。日历无法计算时返回 `nil`。
    public var nextDay: Date? {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: 1, to: self)
    }
    
    /// 前一天。日历无法计算时返回 `nil`。
    public var lastDay: Date? {
        Calendar.autoupdatingCurrent.date(byAdding: .day, value: -1, to: self)
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

    /// 按指定格式与时区转为字符串。
    ///
    /// - Parameters:
    ///   - format: 日期格式。
    ///   - timeZone: 输出时区，默认跟随系统。
    ///   - locale: 输出地区规则，默认跟随系统，适合 UI / 业务展示。
    ///     与服务端约定固定格式时，可显式传入 `Locale(identifier: "en_US_POSIX")`。
    public func format(
        with format: String = "yyyy-MM-dd HH:mm:ss",
        timeZone: TimeZone = .autoupdatingCurrent,
        locale: Locale = .autoupdatingCurrent
    ) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = locale
        dateFormatter.timeZone = timeZone
        dateFormatter.dateFormat = format
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
