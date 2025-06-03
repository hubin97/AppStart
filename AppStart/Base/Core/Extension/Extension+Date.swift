//
//  Extension+Date.swift
//  LuteBase
//
//  Created by hubin.h on 2023/11/9.
//  Copyright © 2025 Hubin_Huang. All rights reserved.
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

    /// 转指定格式字符串 (注意: 时区地区跟随系统)
    /// - Parameter format: 格式: yyyy-MM-dd HH:mm:ss / yyyy-MM-dd ...
    /// - Returns: 字符串
    public func format(with format: String = "yyyy-MM-dd HH:mm:ss") -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = format
        dateFormatter.timeZone = TimeZone.autoupdatingCurrent
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        return dateFormatter.string(from: self)
    }

    /// 转指定格式字符串
    ///    “GMT”：格林威治标准时间
    ///    “Asia/Shanghai”：北京时间  东8区
    ///    “America/New_York”：纽约时间  西5区
    ///    “Europe/London”：伦敦时间   0
    ///    “Australia/Sydney”：悉尼时间
    /// - Parameters:
    ///   - format: 格式
    ///   - identifier: 指定时区标识,
    /// - Returns: String
    public func format(with format: String = "yyyy-MM-dd HH:mm:ss", identifier: String) -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.timeZone = TimeZone.init(identifier: identifier)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
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
