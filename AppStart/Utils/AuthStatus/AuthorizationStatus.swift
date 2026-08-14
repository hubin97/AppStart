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

 2. 选哪个 API？

 | 场景 | 用法 |
 |------|------|
 | 只读（UI 展示、预检） | `snapshot(for:mode: .readOnly)` 或省略 mode |
 | 需要弹窗时再请求 | `snapshot(for:mode: .requestIfNeeded)` |
 | 跳转系统设置 | `openSettings()` |

 对外统一返回 `AuthPermissionSnapshot`（service + authorization）。

 // 1. 常规：用户点击「开启相机」后再 requestIfNeeded
 Task {
     let camera = await AuthorizationStatus.snapshot(for: .camera, mode: .requestIfNeeded)
     guard camera.isUsable else {
         label.text = camera.summaryText
         return
     }
     // 打开相机…
 }

 // 2. 只读
 Task {
     let snap = await AuthorizationStatus.snapshot(for: .bluetooth)   // mode 默认 .readOnly
     // snap.service / snap.authorization / snap.summaryText
 }

 // 3. 非标准权限（以下差异在「何时调用、会不会弹框」，不在 mode 本身）
 ///
 /// | 权限 | 说明 |
 /// |------|------|
 /// | 蓝牙 | 只读：`snapshot(for: .bluetooth)`。避免冷启动批量调用（会初始化 Central，可能弹框）。`.requestIfNeeded` **不会**弹隐私框；拒权后只能 openSettings。 |
 /// | 本地网络 | 只读：`snapshot`（未决定时不探测）。要弹框：`mode: .requestIfNeeded`。可配 `grantConfirmationWait`。 |
 /// | 定位 | 系统一项权限；Demo/前台用 `.whenInUse`；后台需 `.always`（常需设置升级，勿 UI 拆两个入口） |
 /// | Siri | 需 configure + Xcode capability。 |
 /// | 相册 | `.limited` → `.granted`；request 可能三选一弹框。 |

 // 4. 各权限一行示例（需要弹框的用 .requestIfNeeded）
 await AuthorizationStatus.snapshot(for: .apns, mode: .requestIfNeeded)
 await AuthorizationStatus.snapshot(for: .photoLibrary, mode: .requestIfNeeded)
 await AuthorizationStatus.snapshot(for: .bluetooth)               // 只读蓝牙
 await AuthorizationStatus.snapshot(for: .localNetwork, mode: .requestIfNeeded)  // 未决定时会探测并可能弹框

 // 5. Siri / 本地网络（App 启动时一次性配置，见 `AuthStatusConfiguration.swift`）
 // AppDelegate.application(_:didFinishLaunchingWithOptions:)
 AuthorizationStatus.configure {
     $0.isSiriCapabilityEnabled = true
     // $0.localNetwork.bonjourServiceTypes = ["_mydevice._tcp"]  // 默认 _http._tcp
     // $0.localNetwork.grantConfirmationWait = 15  // 弹框场景下判定 granted 前的等待（秒）；越大越不易误判
 }
 Task {
     let siri = await AuthorizationStatus.snapshot(for: .siri, mode: .requestIfNeeded)
     let local = await AuthorizationStatus.snapshot(for: .localNetwork, mode: .requestIfNeeded)
 }

 // 6. 跳转系统设置（引导用户开定位/蓝牙/通知等）
 AuthorizationStatus.shared.openSettings()

 // 7. UI 更新请在 MainActor
 Task { @MainActor in
     let snap = await AuthorizationStatus.snapshot(for: .camera)
     self.detailLabel.text = snap.summaryText
 }
 */

// MARK: - Types

public typealias AuthStatus = AuthorizationStatus

/// 权限授权结果。
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

/// 查询模式：`readOnly` 只读快照；`requestIfNeeded` 在 `canRequestAuthorization` 时先 request 再读。
public enum AuthQueryMode: Sendable {
    case readOnly
    case requestIfNeeded
}

/// 可查询 / 请求的权限与系统服务（配合 `snapshot(for:mode:)`；示例见文件顶部注释）。
public enum AuthPermission: Sendable, Equatable {
    /// 推送通知（APNs）
    case apns
    /// 相机
    case camera
    /// 相册；iOS 14+ `.limited` 映射为 `.granted`；request 可能三选一弹框
    case photoLibrary
    /// 麦克风
    case microphone
    /// 定位；系统一项权限，`.location(.whenInUse / .always)` 表业务所需级别，非两个独立开关
    case location(LocationAuthLevel)
    /// 日历
    case calendar
    /// 提醒事项
    case reminder
    /// Siri；需 configure capability；未开启时 snapshot 为 service.disabled、authorization 为 nil
    case siri
    /// 蓝牙；`.requestIfNeeded` 不弹隐私框；readOnly snapshot 可能初始化 Central
    case bluetooth
    /// 本地网络；无系统回调，Bonjour 推断；可配 `grantConfirmationWait`；拒权后需 openSettings
    case localNetwork
}

/// 「系统服务 + App 授权」快照。
/// - `isUsable`：服务可用且已授权
/// - `summaryText`：UI 展示文案
///
/// 例外：蓝牙 App 拒权（`state == .unauthorized`）时 `service == nil`，`authorization` 仍可能有值（多为 `.denied`）。
public struct AuthPermissionSnapshot: Sendable {
    /// 系统服务状态；`nil` 表示无独立开关，或蓝牙 unauthorized 时 state 无法单独表示系统开关
    public let service: AuthServiceState?
    /// App 授权；通常 service 不可用时为 `nil`；蓝牙 unauthorized 时例外
    public let authorization: PermissionStatus?

    /// 服务层可用（或无服务层）且 App 已授权。
    public var isUsable: Bool {
        (service?.isAvailable ?? true) && authorization?.isGranted == true
    }

    /// 是否可以请求授权
    public var canRequestAuthorization: Bool {
        (service?.isAvailable ?? true) && authorization == .notDetermined
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

    /// `.unknown` 时由 `CBCentralManagerDelegate` 唤醒
    var bluetoothStateContinuation: CheckedContinuation<CBManagerState, Never>?

    //FIXME: @MainActor 类型不能在 AuthorizationStatus.init 里同步创建；改为 lazy，首次主线程访问时再初始化。版本 bump 至 0.2.1。
    @MainActor
    lazy var locationCoordinator = LocationAuthorizationCoordinator()
    let localNetworkCoordinator = LocalNetworkAuthorizationCoordinator()

    lazy var centralManager: CBCentralManager = {
        CBCentralManager(
            delegate: self,
            queue: nil,
            options: [CBCentralManagerOptionShowPowerAlertKey: false]
        )
    }()

    override init() {
        super.init()
        applyConfiguration(configurationStorage)
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

    /// 权限快照（service + authorization）。默认 `mode: .readOnly`。
    /// 蓝牙/本地网络有特殊行为，见文件顶部注释 // 3.
    public static func snapshot(
        for permission: AuthPermission,
        mode: AuthQueryMode = .readOnly
    ) async -> AuthPermissionSnapshot {
        await AuthPermissionCenter.snapshot(for: permission, mode: mode, on: shared)
    }

    func resolveBluetoothManagerState() async -> CBManagerState {
        if centralManager.state != .unknown { return centralManager.state }
        return await withCheckedContinuation { continuation in
            bluetoothStateContinuation = continuation
        }
    }
}
