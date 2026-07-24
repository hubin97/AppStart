//
//  LogTag.swift
//  AppStart
//
//  带前缀标签的日志：`LogM.tag("BLE").info("...")` / `LogM.tag(LogLane.ble).debug("...")`

import CocoaLumberjack
import Foundation

/// `String` 原始值的日志标签枚举；业务工程定义 `LogLane` 等。
public protocol LogTagEnum: RawRepresentable where RawValue == String {}

/// 链式追加子标签：`LogM.tag("BLE").tag("Pump").debug("scan")` → `[BLE][Pump] scan`
public struct LogTag: Sendable {

    private let tags: [String]

    public init(_ tag: String) {
        tags = [tag]
    }

    public init(tags: [String]) {
        self.tags = tags
    }

    private var prefix: String {
        tags.map { "[\($0)]" }.joined()
    }

    private func prefixedMessage(_ message: String) -> String {
        guard !tags.isEmpty else { return message }
        return "\(prefix) \(message)"
    }

    public func tag(_ tag: String) -> LogTag {
        LogTag(tags: tags + [tag])
    }

    public func tag<E: LogTagEnum>(_ tag: E) -> LogTag {
        LogTag(tags: tags + [tag.rawValue])
    }

    public func error(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        LogM.error(prefixedMessage(message), file: file, function: function, line: line)
    }

    public func warn(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        LogM.warn(prefixedMessage(message), file: file, function: function, line: line)
    }

    public func info(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        LogM.info(prefixedMessage(message), file: file, function: function, line: line)
    }

    public func debug(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        LogM.debug(prefixedMessage(message), file: file, function: function, line: line)
    }

    public func verbose(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        LogM.verbose(prefixedMessage(message), file: file, function: function, line: line)
    }

    public func all(
        _ message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        LogM.all(prefixedMessage(message), file: file, function: function, line: line)
    }

    public func log(
        level: DDLogLevel,
        message: String,
        file: String = #file,
        function: String = #function,
        line: UInt = #line
    ) {
        LogM.log(level: level, message: prefixedMessage(message), file: file, function: function, line: line)
    }
}
