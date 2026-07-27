//
//  AuthorizationStatus+Legacy.swift
//  AppStart
//
//  旧版回调 API（`AuthsBlock`）；后续版本可整文件删除。

import Foundation
import CoreBluetooth

// MARK: - Legacy Callback API

public typealias AuthsBlock = (_ granted: Bool?) -> Void

private extension PermissionStatus {
    var legacyBool: Bool? {
        switch self {
        case .granted: return true
        case .notDetermined: return nil
        case .denied, .restricted: return false
        }
    }
}

extension AuthorizationStatus {

    /// 定位服务
    /**
     <!-- 位置 -->
     <key>NSLocationUsageDescription</key>
     <string>App需要您的同意,才能访问位置</string>
     <!-- 在使用期间访问位置 -->
     <key>NSLocationWhenInUseUsageDescription</key>
     <string>App需要您的同意,才能在使用期间访问位置</string>
     <!-- 始终访问位置 -->
     <key>NSLocationAlwaysUsageDescription</key>
     <string>App需要您的同意,才能始终访问位置</string>

     KEY: NSLocationAlwaysAndWhenInUseUsageDescription

     This app has attempted to access privacy-sensitive data without a usage description. The app's Info.plist must contain both “NSLocationAlwaysAndWhenInUseUsageDescription” and “NSLocationWhenInUseUsageDescription” keys with string values explaining to the user how the app uses this data

     */
    /// 返回 nil 表示未选定。推荐改用 `await request(.location(.whenInUse))`。
    @available(*, deprecated, message: "Use await AuthorizationStatus.request(.location(.whenInUse)) instead")
    public static func locationServices(authsBlock: @escaping AuthsBlock) {
        Task {
            authsBlock(await status(for: .location(.whenInUse)).legacyBool)
        }
    }

    @available(*, deprecated, message: "Use await AuthorizationStatus.request(_:) instead")
    public static func apnsServices(authsBlock: @escaping AuthsBlock) {
        Task { authsBlock(await request(.apns).legacyBool) }
    }

    @available(*, deprecated, message: "Use await AuthorizationStatus.request(.camera) instead")
    public static func cameraService(authsBlock: @escaping AuthsBlock) {
        Task { authsBlock(await request(.camera).legacyBool) }
    }

    /// 相册权限（含 iOS 14+ 有限访问 `.limited`）
    /**
     <!-- 相册 -->
     <key>NSPhotoLibraryUsageDescription</key>
     <string>App需要您的同意,才能访问相册</string>
     <!-- iOS11 新增 -->
     <key>NSPhotoLibraryAddUsageDescription</key>
     <string>App需要您的同意,才能添加照片到相册</string>
     */
    @available(*, deprecated, message: "Use await AuthorizationStatus.request(.photoLibrary) instead")
    public static func albumService(authsBlock: @escaping AuthsBlock) {
        Task { authsBlock(await request(.photoLibrary).legacyBool) }
    }

    /**
     <!-- 麦克风 -->
     <key>NSMicrophoneUsageDescription</key>
     <string>App需要您的同意,才能访问麦克风</string>
     */
    @available(*, deprecated, message: "Use await AuthorizationStatus.request(.microphone) instead")
    public static func microphoneService(authsBlock: @escaping AuthsBlock) {
        Task { authsBlock(await request(.microphone).legacyBool) }
    }

    /// 应用内使用数据权限, 蜂窝/WLAN 网络对应 CTCellularData 值如下
    /// [关闭:.restricted; WLAN:.restricted; WLAN与蜂窝网络:.notRestricted]
    @available(*, deprecated, message: "Use AuthorizationStatus.monitorCellularDataRestriction() instead")
    public static func cellularDataService(authsBlock: @escaping AuthsBlock) {
        Task {
            for await allowed in monitorCellularDataRestriction() {
                authsBlock(allowed)
            }
        }
    }

    @available(*, deprecated, message: "Use AuthorizationStatus.monitorNetworkReachability() instead")
    public static func networkService(authsBlock: @escaping AuthsBlock) {
        Task {
            for await reachable in monitorNetworkReachability() {
                authsBlock(reachable)
            }
        }
    }

    @available(*, deprecated, message: "Use await AuthorizationStatus.request(.siri) instead")
    public static func siriService(authsBlock: @escaping AuthsBlock) {
        Task { authsBlock(await request(.siri).legacyBool) }
    }

    // Privacy - Calendars Usage Description
    // App需要您的同意,才能访问你的日历
    @available(*, deprecated, message: "Use await AuthorizationStatus.request(.calendar) instead")
    public static func calendarService(authsBlock: @escaping AuthsBlock) {
        Task { authsBlock(await request(.calendar).legacyBool) }
    }

    // Privacy - Reminders Usage Description
    // App需要您的同意,才能访问你的提醒事项
    @available(*, deprecated, message: "Use await AuthorizationStatus.request(.reminder) instead")
    public static func reminderService(authsBlock: @escaping AuthsBlock) {
        Task { authsBlock(await request(.reminder).legacyBool) }
    }

    /// 获取系统蓝牙是否打开（代理方式；`.unknown` 时等待状态回调）
    @available(*, deprecated, message: "Use await AuthorizationStatus.bluetoothManagerState() instead")
    public static func systemBleStateUpdate(authsBlock: @escaping (_ state: CBManagerState) -> Void) {
        Task { authsBlock(await bluetoothManagerState()) }
    }

    // !!!: 必要时使用 bluetoothManagerState 方法可全替代
    // !!!: 此方法只能判断当前应用内是否授权; 打开蓝牙服务, 需要进一步判断手机是否打开蓝牙(此时必须使用 bluetoothManagerState)
    @available(*, deprecated, message: "Use AuthorizationStatus.status(for: .bluetooth) instead")
    public static func bleService(authsBlock: @escaping AuthsBlock) {
        Task {
            authsBlock(await status(for: .bluetooth).legacyBool)
        }
    }
}
