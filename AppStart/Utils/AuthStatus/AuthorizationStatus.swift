//
//  AuthorizationStatus.swift
//  AppStart
//
//  Created by hubin.h on 2021/4/22.
//  Copyright © 2025 hubin.h. All rights reserved.

import UIKit
import Foundation
import CoreBluetooth

/**
 1. info.plist 配置权限描述

 <!-- 推送通知（APNs） -->
 <key>NSLocalNotificationUsageDescription</key>
 <string>App需要您的同意,才能访问推送通知</string>
 <!-- 相册 -->
 <key>NSPhotoLibraryUsageDescription</key>
 <string>App需要您的同意,才能访问相册</string>
 <!-- 相机 -->
 <key>NSCameraUsageDescription</key>
 <string>App需要您的同意,才能访问相机</string>
 <!-- 麦克风 -->
 <key>NSMicrophoneUsageDescription</key>
 <string>App需要您的同意,才能访问麦克风</string>
 <!-- 位置 -->
 <key>NSLocationUsageDescription</key>
 <string>App需要您的同意,才能访问位置</string>
 <!-- 在使用期间访问位置 -->
 <key>NSLocationWhenInUseUsageDescription</key>
 <string>App需要您的同意,才能在使用期间访问位置</string>
 <!-- 始终访问位置 -->
 <key>NSLocationAlwaysUsageDescription</key>
 <string>App需要您的同意,才能始终访问位置</string>
 <!-- 日历 -->
 <key>NSCalendarsUsageDescription</key>
 <string>App需要您的同意,才能访问日历</string>
 <!-- 提醒事项 -->
 <key>NSRemindersUsageDescription</key>
 <string>App需要您的同意,才能访问提醒事项</string>
 <!-- 运动与健身 -->
 <key>NSMotionUsageDescription</key>
  <string>App需要您的同意,才能访问运动与健身</string>
 <!-- 健康更新 -->
 <key>NSHealthUpdateUsageDescription</key>
 <string>App需要您的同意,才能访问健康更新 </string>
 <!-- 健康分享 -->
 <key>NSHealthShareUsageDescription</key>
 <string>App需要您的同意,才能访问健康分享</string>
 <!-- 蓝牙 -->
 <key>NSBluetoothPeripheralUsageDescription</key>
 <string>App需要您的同意,才能访问蓝牙</string>
 <key>NSBluetoothAlwaysUsageDescription</key>
 <string>App需要您的同意,才能访问蓝牙</string>
 <!-- 本地网络（Bonjour / 局域网，iOS 14+） -->
 <key>NSLocalNetworkUsageDescription</key>
 <string>App需要您的同意,才能发现与连接局域网设备</string>
 <key>NSBonjourServices</key>
 <array>
     <string>_http._tcp</string>
 </array>
 <!-- 媒体资料库 -->
 <key>NSAppleMusicUsageDescription</key>
 <string>App需要您的同意,才能访问媒体资料库</string>
 <!-- 语音识别 -->
 <key>NSSpeechRecognitionUsageDescription</key>
 <string>App需要您的同意,才能使用语音识别</string>
 <key>NSSiriUsageDescription</key>
 <string>App需要您的同意,才能使用Siri</string>
 <!-- 始终定位（iOS 11+，配合 Always 授权） -->
 <key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
 <string>App需要您的同意,才能始终访问位置</string>

 /// 网络连通性见 `AppStart/Network/Connectivity/CONNECTIVITY_README.md`

 2. 调用示例

 模型：先查「系统服务」，再查「App 授权」；业务判断用 `snapshot.isUsable`。

 // 1. 推荐入口（查询 + 可选请求授权）
 Task {
     let camera = await AuthorizationStatus.resolve(.camera, requestIfNeeded: true)
     guard camera.isUsable else {
         label.text = camera.summaryText   // 如「服务：未开启」或「授权：已拒绝」
         return
     }
     // 打开相机…
 }

 // 2. 只读快照（不弹授权框）
 Task {
     let snap = await AuthorizationStatus.snapshot(for: .bluetooth)
     // snap.service        → 蓝牙硬件是否开启
     // snap.authorization  → 蓝牙隐私授权
     // snap.summaryText    → 「服务：可用 · 授权：已授权」
 }

 // 3. 各权限类型
 await AuthorizationStatus.resolve(.apns, requestIfNeeded: true)
 await AuthorizationStatus.resolve(.photoLibrary, requestIfNeeded: true)
 await AuthorizationStatus.resolve(.microphone, requestIfNeeded: true)
 await AuthorizationStatus.resolve(.location(.whenInUse), requestIfNeeded: true)
 await AuthorizationStatus.resolve(.location(.always), requestIfNeeded: true)
 await AuthorizationStatus.resolve(.calendar, requestIfNeeded: true)
 await AuthorizationStatus.resolve(.reminder, requestIfNeeded: true)
 await AuthorizationStatus.resolve(.bluetooth, requestIfNeeded: false)  // 蓝牙授权由 CBCentralManager 首次使用时触发
 await AuthorizationStatus.resolve(.localNetwork, requestIfNeeded: true)  // 须 NSLocalNetworkUsageDescription + NSBonjourServices（默认探测 _http._tcp）

 // 4. Siri / 本地网络（App 启动时一次性配置，见 `AuthStatusConfiguration.swift`）
 // AppDelegate.application(_:didFinishLaunchingWithOptions:)
 AuthorizationStatus.configure {
     $0.isSiriCapabilityEnabled = true
     // $0.localNetwork.bonjourServiceTypes = ["_mydevice._tcp"]  // 默认 _http._tcp
     // $0.localNetwork.grantConfirmationWait = 15  // 弹框场景判定「已授权」前的确认等待（秒）；误报时可调大
 }
 Task {
     let siri = await AuthorizationStatus.resolve(.siri, requestIfNeeded: true)
     let local = await AuthorizationStatus.resolve(.localNetwork, requestIfNeeded: true)
 }

 // 5. 跳转系统设置（引导用户开定位/蓝牙/通知等）
 AuthorizationStatus.shared.openSettings()

 // 6. 进阶：仅操作 App 授权层（不含系统服务判断）
 Task {
     let status = await AuthorizationStatus.status(for: .camera)   // .granted / .denied / …
     if status == .notDetermined {
         _ = await AuthorizationStatus.request(.camera)
     }
 }

 // 7. 底层：蓝牙硬件状态（业务层优先用 snapshot(for: .bluetooth)）
 Task {
     let state = await AuthorizationStatus.bluetoothManagerState()
     // .poweredOn / .poweredOff / .unauthorized …
 }

 // 8. UI 更新请在 MainActor
 Task { @MainActor in
     let snap = await AuthorizationStatus.snapshot(for: .camera)
     self.detailLabel.text = snap.summaryText
 }
 */

// MARK: - Types

public typealias AuthStatus = AuthorizationStatus

/// 权限结果；替代旧版 `Bool?`（`nil` → `.notDetermined`）。
public enum PermissionStatus: Sendable {
    case granted
    case denied
    case notDetermined
    case restricted

    public var isGranted: Bool { self == .granted }

    /// UI 展示文案
    public var displayText: String {
        switch self {
        case .granted: return "已授权"
        case .denied: return "已拒绝"
        case .notDetermined: return "未决定"
        case .restricted: return "受限制"
        }
    }
}

/// 定位授权级别（对应 `CLLocationManager.requestWhenInUseAuthorization` / `requestAlwaysAuthorization`）。
public enum LocationAuthLevel: Sendable, Equatable {
    /// 使用期间定位；Info.plist 需 `NSLocationWhenInUseUsageDescription`
    case whenInUse
    /// 始终定位；需额外配置 `NSLocationAlwaysAndWhenInUseUsageDescription`
    case always
}

/// 系统服务能力（优先于 App 授权判断；无独立开关的权限对应 `nil`）。
public enum AuthServiceState: Sendable, Equatable {
    case available
    case disabled
    case unsupported
    case unknown

    public var isAvailable: Bool { self == .available }

    public var displayText: String {
        switch self {
        case .available: return "可用"
        case .disabled: return "未开启"
        case .unsupported: return "不支持"
        case .unknown: return "未知"
        }
    }
}

/// 可查询 / 请求的权限与系统服务（配合 `resolve` / `snapshot`；示例见文件顶部注释）。
public enum AuthPermission: Sendable, Equatable {
    /// 推送通知（APNs）
    case apns
    /// 相机
    case camera
    /// 相册读写（含 iOS 14+ `.limited` 有限访问，映射为 `.granted`）
    case photoLibrary
    /// 麦克风
    case microphone
    /// 定位；关联值区分 whenInUse / always
    case location(LocationAuthLevel)
    /// 日历
    case calendar
    /// 提醒事项
    case reminder
    /// Siri（宿主 App 需开启 Siri capability，并在 `AuthorizationStatus.configure` 中设置 `isSiriCapabilityEnabled = true`）
    case siri
    /// 蓝牙（服务：硬件开关；授权：蓝牙隐私）
    case bluetooth
    /// 本地网络（Bonjour / 局域网；须 plist + `configuration.localNetwork`）
    case localNetwork
}

/// 「服务 + 授权」快照。
/// - `isUsable`：业务是否可用（服务 OK 且已授权）
/// - `summaryText`：UI 展示，如「服务：可用 · 授权：已授权」
public struct AuthPermissionSnapshot: Sendable {
    /// 系统服务是否可用；`nil` 表示该项无独立服务开关。
    public let service: AuthServiceState?
    /// App 隐私授权；服务不可用时通常为 `nil`（无需再查授权）。
    public let authorization: PermissionStatus?

    public var isUsable: Bool {
        guard service?.isAvailable ?? true else { return false }
        guard let authorization else { return service?.isAvailable ?? true }
        return authorization.isGranted
    }

    public var canRequestAuthorization: Bool {
        guard service?.isAvailable ?? true else { return false }
        return authorization == .notDetermined
    }

    public var summaryText: String {
        if let service, !service.isAvailable {
            return "服务：\(service.displayText)"
        }
        var parts: [String] = []
        if let service {
            parts.append("服务：\(service.displayText)")
        }
        if let authorization {
            parts.append("授权：\(authorization.displayText)")
        }
        return parts.isEmpty ? "—" : parts.joined(separator: " · ")
    }
}

// MARK: - AuthorizationStatus

/// 系统权限与可达性查询（Info.plist 配置与调用示例见文件顶部注释块）。
public class AuthorizationStatus: NSObject {

    public static let shared = AuthStatus()

    private var configurationStorage = AuthStatusConfiguration()

    /// 当前宿主配置（读写后会同步到内部 Coordinator）。
    public var configuration: AuthStatusConfiguration {
        get { configurationStorage }
        set { applyConfiguration(newValue) }
    }

    /// 等待 `bluetoothManagerState()` 的 continuation（`.unknown` 时由 delegate 唤醒）
    var bluetoothStateContinuation: CheckedContinuation<CBManagerState, Never>?

    let locationCoordinator = LocationAuthorizationCoordinator()
    let localNetworkCoordinator = LocalNetworkAuthorizationCoordinator()

    lazy var centralManager: CBCentralManager = {
        let options: [String: Any] = [
            CBCentralManagerOptionShowPowerAlertKey: true,
            CBCentralManagerScanOptionAllowDuplicatesKey: false
        ]
        return CBCentralManager(delegate: self, queue: nil, options: options)
    }()

    override init() {
        super.init()
        applyConfiguration(configurationStorage)
        _ = centralManager
    }

    func applyConfiguration(_ config: AuthStatusConfiguration) {
        configurationStorage = config
        localNetworkCoordinator.apply(config.localNetwork)
    }

    /// 跳转系统设置。示例：`AuthorizationStatus.shared.openSettings()`
    public func openSettings() {
        guard let setUrl = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(setUrl) {
            UIApplication.shared.open(setUrl)
        }
    }
}

// MARK: - Async API

extension AuthorizationStatus {

    /// App 启动时注入配置。示例见文件顶部注释。
    public static func configure(_ body: (inout AuthStatusConfiguration) -> Void) {
        var config = shared.configurationStorage
        body(&config)
        shared.applyConfiguration(config)
    }

    /// 当前宿主配置。
    public static var configuration: AuthStatusConfiguration {
        get { shared.configurationStorage }
        set { shared.applyConfiguration(newValue) }
    }

    /// 只读快照，不弹授权框。示例：`await AuthorizationStatus.snapshot(for: .bluetooth)`
    public static func snapshot(for permission: AuthPermission) async -> AuthPermissionSnapshot {
        await AuthPermissionCenter.snapshot(for: permission, on: shared)
    }

    /// 查询并在需要时请求授权（推荐）。示例：`await AuthorizationStatus.resolve(.camera, requestIfNeeded: true)`
    @discardableResult
    public static func resolve(_ permission: AuthPermission, requestIfNeeded: Bool = false) async -> AuthPermissionSnapshot {
        await AuthPermissionCenter.resolve(permission, requestIfNeeded: requestIfNeeded, on: shared)
    }

    /// 仅查 App 授权，不弹框。示例：`await AuthorizationStatus.status(for: .camera)`
    public static func status(for permission: AuthPermission) async -> PermissionStatus {
        await AuthPermissionCenter.authorizationStatus(for: permission, on: shared)
    }

    /// 未决定时弹系统授权框。示例：`await AuthorizationStatus.request(.microphone)`
    @discardableResult
    public static func request(_ permission: AuthPermission) async -> PermissionStatus {
        await AuthPermissionCenter.request(permission, on: shared)
    }

    /// 蓝牙硬件状态（底层）。示例：`await AuthorizationStatus.bluetoothManagerState()` → `.poweredOn`
    public static func bluetoothManagerState() async -> CBManagerState {
        await shared.resolveBluetoothManagerState()
    }

    func resolveBluetoothManagerState() async -> CBManagerState {
        if centralManager.state != .unknown { return centralManager.state }
        return await withCheckedContinuation { continuation in
            bluetoothStateContinuation = continuation
        }
    }
}
