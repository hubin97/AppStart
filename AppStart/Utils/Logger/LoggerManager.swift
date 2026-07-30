//
//  LoggerManager.swift
//  AppStart
//
//  Created by hubin.h on 2021/9/30.
//  Copyright © 2025 hubin.h. All rights reserved.

import Foundation
import CocoaLumberjack

// MARK: - global var and methods
//private let KdateFormatString = "yyyy/MM/dd HH:mm:ss"

/// 使用示例:
/// LogM.shared.launch(logLevel, logMode: .detail).entrance(R.image.lanuch_logo())
/// LogM.shared.setup(level: logLevel, consoleMode: .easy, fileMode: .detail).entrance(R.image.lanuch_logo())
public typealias LogM = LoggerManager

// MARK: - main class
open class LoggerManager {

    public static let shared = LoggerManager()
    
    // 定义Log等级 *  Error, warning, info, debug and verbose logs
    internal var logLevel: DDLogLevel = .all
    
    private var consoleMode: LoggerFormatter.LogMode = .easy
    private var fileMode: LoggerFormatter.LogMode = .detail
    private var customFileLogger: DDFileLogger?
    private var storagePolicy: LogStoragePolicy = .default
    private var _defaultFileLogger: DDFileLogger?

    private let logDirectoryPath = (QuickPaths.documentPath ?? "") + "/Logs"

    private var defaultFileLogger: DDFileLogger {
        if let logger = _defaultFileLogger { return logger }
        let logger = Self.makeFileLogger(logsDirectory: logDirectoryPath, policy: storagePolicy)
        _defaultFileLogger = logger
        return logger
    }

    private static func makeFileLogger(logsDirectory: String, policy: LogStoragePolicy) -> DDFileLogger {
        let fileLogger = DDFileLogger(logFileManager: DDLogFileManagerDefault(logsDirectory: logsDirectory))
        fileLogger.doNotReuseLogFiles = !policy.reuseLogFilesOnLaunch
        fileLogger.maximumFileSize = policy.maxFileSize
        fileLogger.rollingFrequency = policy.rollingFrequency
        fileLogger.logFileManager.maximumNumberOfLogFiles = policy.maxFileCount
        fileLogger.logFileManager.logFilesDiskQuota = policy.diskQuota
        return fileLogger
    }
    
    // 对外提供路径只读访问
    public var logPath: String {
        if let customFileLogger = customFileLogger,
           let logsDirectory = (customFileLogger.logFileManager as? DDLogFileManagerDefault)?.logsDirectory {
            return logsDirectory
        }
        return logDirectoryPath
    }

    // MARK: - 链式配置
    @discardableResult
    public func level(_ level: DDLogLevel) -> Self {
        self.logLevel = level
        return self
    }
    
    @discardableResult
    public func console(_ mode: LoggerFormatter.LogMode) -> Self {
        self.consoleMode = mode
        return self
    }
    
    @discardableResult
    public func file(_ mode: LoggerFormatter.LogMode) -> Self {
        self.fileMode = mode
        return self
    }

    /// 文件日志存储策略（需在 `launch()` 前调用；自定义 `fileLogger` 时无效）
    @discardableResult
    public func storage(_ policy: LogStoragePolicy) -> Self {
        storagePolicy = policy
        if customFileLogger == nil {
            _defaultFileLogger = Self.makeFileLogger(logsDirectory: logDirectoryPath, policy: policy)
        }
        return self
    }

    public var currentStoragePolicy: LogStoragePolicy {
        storagePolicy
    }

    /// 外部传入 fileLogger
    @discardableResult
    public func fileLogger(_ logger: DDFileLogger) -> Self {
        self.customFileLogger = logger
        return self
    }
    
    /// 快速启动（一次性配置）
    @discardableResult
    public func setup(level: DDLogLevel = .all,
                      consoleMode: LoggerFormatter.LogMode = .easy,
                      fileMode: LoggerFormatter.LogMode = .detail,
                      storagePolicy: LogStoragePolicy = .default,
                      fileLogger: DDFileLogger? = nil) -> Self {
        self.logLevel = level
        self.consoleMode = consoleMode
        self.fileMode = fileMode
        self.customFileLogger = fileLogger
        if fileLogger == nil {
            storage(storagePolicy)
        }
        return launch()
    }
    
    /// 当前使用的文件日志
    public var currentFileLogger: DDFileLogger {
        return customFileLogger ?? defaultFileLogger
    }
    
    /// 启动日志系统
    @discardableResult
    public func launch() -> Self {
        // 控制台日志
        let ddosLogger = DDOSLogger.sharedInstance
        ddosLogger.logFormatter = LoggerFormatter(mode: consoleMode)
        DDLog.add(ddosLogger, with: logLevel)
        
        // 文件日志（优先用外部传入的）
        let fileLogger = currentFileLogger
        fileLogger.logFormatter = LoggerFormatter(mode: fileMode)
        DDLog.add(fileLogger, with: logLevel)
        return self
    }
        
    /// 缓存设置图标
    private var cacheIcon: UIImage?
    /// 初始化日志入口
    public func entrance(_ icon: UIImage? = nil) {
        self.removeEntrance()
        
        let aIcon = cacheIcon ?? icon ?? Asset.iconLogger.image
        self.cacheIcon = aIcon

        LoggerAssistant(icon: aIcon) {
            stackTopViewController()?.navigationController?.pushViewController(LoggerListController(), animated: true)
        }.show()
    }
    
    /// 移除日志入口
    public func removeEntrance() {
        kAppKeyWindow?.subviews.compactMap({ $0 as? LoggerAssistant }).forEach({ $0.removeFromSuperview() })
    }

    /// 是否已展示入口
    public func hasEntrance() -> Bool {
        if let isOn = UserDefaults.standard.object(forKey: "LoggerAssistant") as? Bool {
            return isOn
        }
        return false
    }

    /// 更新入口状态
    /// - Parameter state: 开启/关闭
    public func updateEntrance(_ state: Bool) {
        UserDefaults.standard.set(state, forKey: "LoggerAssistant")
        UserDefaults.standard.synchronize()
    }
}

extension LoggerManager {
    
//    public static func error(_ message: String,
//                             file: StaticString = #file,
//                             function: StaticString = #function,
//                             line: UInt = #line) {
//        DDLogError("\(message)", file: file, function: function, line: line)
//    }
//    
//    public static func warn(_ message: String,
//                            file: StaticString = #file,
//                            function: StaticString = #function,
//                            line: UInt = #line) {
//        DDLogWarn("\(message)", file: file, function: function, line: line)
//    }
//    
//    public static func info(_ message: String,
//                            file: StaticString = #file,
//                            function: StaticString = #function,
//                            line: UInt = #line) {
//        DDLogInfo("\(message)", file: file, function: function, line: line)
//    }
//    
//    public static func debug(_ message: String,
//                             file: StaticString = #file,
//                             function: StaticString = #function,
//                             line: UInt = #line) {
//        DDLogDebug("\(message)", file: file, function: function, line: line)
//    }
//    
//    public static func verbose(_ message: String,
//                               file: StaticString = #file,
//                               function: StaticString = #function,
//                               line: UInt = #line) {
//        DDLogVerbose("\(message)", file: file, function: function, line: line)
//    }
    
    // MARK: - 修复宏定义不支持问题
//    CocoaLumberjack/Sources/CocoaLumberjack/include/CocoaLumberjack/DDLogMacros.h:91:9: note: macro 'DDLogError' unavailable: function like macros not supported
//    CocoaLumberjack/Sources/CocoaLumberjack/include/CocoaLumberjack/DDLogMacros.h:92:9: note: macro 'DDLogWarn' unavailable: function like macros not supported
//    CocoaLumberjack/Sources/CocoaLumberjack/include/CocoaLumberjack/DDLogMacros.h:93:9: note: macro 'DDLogInfo' unavailable: function like macros not supported
//    CocoaLumberjack/Sources/CocoaLumberjack/include/CocoaLumberjack/DDLogMacros.h:94:9: note: macro 'DDLogDebug' unavailable: function like macros not supported

    // 通用log方法
    private static func log(_ message: String, level: DDLogLevel, flag: DDLogFlag, file: String = #file, function: String = #function, line: UInt = #line) {
        // 如果日志级别为 off，则不记录日志
        guard level != .off else { return }
        //DDLog.log(asynchronous: true, level: level, flag: flag, context: 0, file: #file, function: #function, line: #line, tag: nil, format: message, arguments: getVaList([]))
        // FIXME: 修正 `日志内容格式异常` 兼容问题
        DDLog.log(asynchronous: true, level: level, flag: flag, context: 0, file: file, function: function, line: line, tag: nil,
                  format: "%@", arguments: getVaList([message]))
    }
    
    /// 当 DDLogLevel 为 .off; 这意味着所有日志都被禁用。在这种情况下，设置什么样的 DDLogFlag，日志都不会被记录
    public static func off() {
        log("", level: .off, flag: .info)
    }
    
    public static func error(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        log(message, level: .error, flag: .error, file: file, function: function, line: line)
    }
    
    public static func warn(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        log(message, level: .warning, flag: .warning, file: file, function: function, line: line)
    }
    
    public static func info(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        log(message, level: .info, flag: .info, file: file, function: function, line: line)
    }
    
    public static func debug(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        log(message, level: .debug, flag: .debug, file: file, function: function, line: line)
    }
    
    public static func verbose(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        log(message, level: .verbose, flag: .verbose, file: file, function: function, line: line)
    }
    
    /// 当 DDLogLevel 为 .all; 这意味着所有级别的日志都将被记录。在这种情况下，可以根据需要设置 DDLogFlag。
    /// 例如，如果你想记录所有类型的日志，可以使用 .verbose 标志。
    public static func all(_ message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        log(message, level: .all, flag: .verbose, file: file, function: function, line: line)
    }
    
    /// 通用log方法 (汇总)
    /// - Parameters:
    ///   - level: 级别
    ///   - message: 内容
    ///   修正 日志写入本地格式异常
    public static func log(level: DDLogLevel, message: String, file: String = #file, function: String = #function, line: UInt = #line) {
        switch level {
        case .off:
            off()
        case .error:
            error(message, file: file, function: function, line: line)
        case .warning:
            warn(message, file: file, function: function, line: line)
        case .info:
            info(message, file: file, function: function, line: line)
        case .debug:
            debug(message, file: file, function: function, line: line)
        case .verbose:
            verbose(message, file: file, function: function, line: line)
        case .all:
            all(message, file: file, function: function, line: line)
        @unknown default:
            off()
        }
    }
}

///注意: 使用logResourcesCount的`RxSwift.Resources.total` 需要在Podfile中启用资源跟踪 (主工程配置)
/**
 # Enable tracing resources
 installer.pods_project.targets.each do |target|
   if target.name == 'RxSwift'
     target.build_configurations.each do |config|
       if config.name == 'Debug'
         config.build_settings['OTHER_SWIFT_FLAGS'] ||= ['-D', 'TRACE_RESOURCES']
       end
     end
   end
 end
 */
import RxSwift
public func logResourcesCount(enable: Bool = false) {
    #if DEBUG
    if enable {
        LogM.debug("RxSwift resources count: \(RxSwift.Resources.total)")
        
    }
    #endif
}

// MARK: - other classes

open class LoggerFormatter: NSObject, DDLogFormatter {

    /// 日志模式
    public enum LogMode {
        /// 简易日志
        case easy
        /// 日志详情
        case detail
    }
    
    private(set) var logMode: LogMode = .detail
    convenience init(mode: LogMode) {
        self.init()
        self.logMode = mode
    }
    
    open func format(message logMessage: DDLogMessage) -> String? {
        guard logMessage.flag.rawValue <= LoggerManager.shared.logLevel.rawValue else { return nil }

        var flag = ""
        switch logMessage.flag {
        case .error:
            flag = "E❌"
            break
        case .warning:
            flag = "W⚠️"
            break
        case .info:
            flag = "I📝"
            break
        case .debug:
            flag = "D🛠"
            break
        default:
            flag = "🧩"
            break
        }
        let time = logMessage.timestamp.format(
            with: "yyyy-MM-dd HH:mm:ss.SSS",
            locale: Locale(identifier: "en_US_POSIX")
        )
        let message = logMessage.message
        
        switch logMode {
        case .easy:
            return "[\(time)] [\(flag)]" + " " + message
        case .detail:
            // 📌 如果传空 文件名, 且行默认0, 标记为 简易日志 输出
            if logMessage.fileName.isEmpty && logMessage.line == 0 {
                return "[\(time)] [\(flag)]" + " " + message
            }
            // [\(logMessage.threadID)]
            return "[\(time)] [\(flag)]" + " " +  "[\(logMessage.fileName):\(logMessage.line) \(logMessage.function ?? "")]" + " " + message
        }
    }
}

// MARK: - LogTag 工厂

public extension LoggerManager {

    static func tag(_ tag: String) -> LogTag {
        LogTag(tag)
    }

    static func tag(_ tags: [String]) -> LogTag {
        LogTag(tags: tags)
    }

    static func tag(_ tags: String...) -> LogTag {
        LogTag(tags: tags)
    }

    static func tag<E: LogTagEnum>(_ tag: E) -> LogTag {
        LogTag(tag.rawValue)
    }
}
