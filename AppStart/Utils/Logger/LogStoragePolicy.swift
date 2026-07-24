//
//  LogStoragePolicy.swift
//  AppStart
//
//  本地文件日志存储策略（对应 CocoaLumberjack DDFileLogger 参数）。

import Foundation

public struct LogStoragePolicy: Equatable, Sendable {

    private static let bytesPerMB: UInt64 = 1024 * 1024
    private static let secondsPerDay: TimeInterval = 24 * 60 * 60

    public let maxFileSize: UInt64
    public let maxFileCount: UInt
    public let diskQuota: UInt64
    public let rollingFrequency: TimeInterval
    /// true：冷启动续写最新文件；false：每次冷启动新建文件
    public let reuseLogFilesOnLaunch: Bool

    public init(
        maxFileSize: UInt64,
        maxFileCount: UInt,
        diskQuota: UInt64,
        rollingFrequency: TimeInterval,
        reuseLogFilesOnLaunch: Bool
    ) {
        self.maxFileSize = maxFileSize
        self.maxFileCount = maxFileCount
        self.diskQuota = diskQuota
        self.rollingFrequency = rollingFrequency
        self.reuseLogFilesOnLaunch = reuseLogFilesOnLaunch
        assert(maxFileCount > 0, "LogStoragePolicy: maxFileCount 必须 > 0")
        assert(diskQuota > 0, "LogStoragePolicy: diskQuota 必须 > 0")
        if maxFileSize > 0 {
            assert(diskQuota >= maxFileSize, "LogStoragePolicy: diskQuota 至少应能容纳一个满文件")
        }
    }

    /// 2MB × 10，目录 20MB，仅按大小滚动
    public static let `default` = LogStoragePolicy(
        maxFileSize: 2 * bytesPerMB,
        maxFileCount: 10,
        diskQuota: 20 * bytesPerMB,
        rollingFrequency: 0,
        reuseLogFilesOnLaunch: true
    )

    /// 5MB × 20，目录 100MB，按天 + 大小
    public static let standard = LogStoragePolicy(
        maxFileSize: 5 * bytesPerMB,
        maxFileCount: 20,
        diskQuota: 100 * bytesPerMB,
        rollingFrequency: secondsPerDay,
        reuseLogFilesOnLaunch: true
    )

    /// 10MB × 30，目录 300MB，每次启动新文件
    public static let heavy = LogStoragePolicy(
        maxFileSize: 10 * bytesPerMB,
        maxFileCount: 30,
        diskQuota: 300 * bytesPerMB,
        rollingFrequency: secondsPerDay,
        reuseLogFilesOnLaunch: false
    )

    public static func dailyOnly(
        diskQuotaMB: UInt,
        maxFileCount: UInt = 30,
        reuseLogFilesOnLaunch: Bool = true
    ) -> LogStoragePolicy {
        LogStoragePolicy(
            maxFileSize: 0,
            maxFileCount: max(1, maxFileCount),
            diskQuota: UInt64(diskQuotaMB) * bytesPerMB,
            rollingFrequency: secondsPerDay,
            reuseLogFilesOnLaunch: reuseLogFilesOnLaunch
        )
    }

    public var theoreticalMaxBytes: UInt64 {
        guard maxFileSize > 0 else { return diskQuota }
        return min(diskQuota, maxFileSize * UInt64(maxFileCount))
    }
}
