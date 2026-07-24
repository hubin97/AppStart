//
//  BleLogger.swift
//  AppStart
//
//  BLE 调试日志，由 BleConfiguration.debugLog 控制；写入 LogM（控制台 + 文件）。

import Foundation

struct BleLogger {
    var isEnabled: Bool
    var tag: String

    init(isEnabled: Bool, tag: String) {
        self.isEnabled = isEnabled
        self.tag = tag
    }

    init(configurations: [BleConfiguration]) {
        isEnabled = configurations.contains { $0.debugLog }
        tag = configurations.first(where: { $0.debugLog })?.logTag
            ?? configurations.first?.logTag
            ?? "[Ble] "
    }

    func log(_ message: String) {
        guard isEnabled else { return }
        LogM.tag(normalizedTag).debug(message)
    }

    private var normalizedTag: String {
        tag
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    }
}
