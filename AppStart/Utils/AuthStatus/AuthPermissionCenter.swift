//
//  AuthPermissionCenter.swift
//  AppStart
//
//  权限模块内部调度：系统服务 → App 授权 → 请求。

import AVFoundation
import CoreBluetooth
import CoreLocation
import Intents
import Photos

/// 各权限「系统服务 / App 授权」分层：
///
/// | 权限 | 系统服务（优先） | App 授权 |
/// |------|------------------|----------|
/// | 推送 / 相册 / 麦克风 / 日历 / 提醒 / 本地网络 | — | 对应隐私授权 |
/// | 相机 | 是否有摄像头 | 相机隐私 |
/// | 定位 | 定位服务总开关 | 使用期间 / 始终 |
/// | Siri | App Siri capability | Siri 隐私 |
/// | 蓝牙 | 蓝牙硬件是否开启 | 蓝牙隐私 |
enum AuthPermissionCenter {

    // MARK: - Snapshot

    static func snapshot(for permission: AuthPermission, on host: AuthorizationStatus) async -> AuthPermissionSnapshot {
        let service = await serviceState(for: permission, on: host)
        let authorization: PermissionStatus?
        if let service, !service.isAvailable {
            authorization = nil
        } else {
            authorization = await authorizationStatus(for: permission, on: host)
        }
        return AuthPermissionSnapshot(service: service, authorization: authorization)
    }

    static func resolve(
        _ permission: AuthPermission,
        requestIfNeeded: Bool,
        on host: AuthorizationStatus
    ) async -> AuthPermissionSnapshot {
        if requestIfNeeded {
            let before = await snapshot(for: permission, on: host)
            if before.canRequestAuthorization {
                await request(permission, on: host)
            }
        }
        return await snapshot(for: permission, on: host)
    }

    // MARK: - Authorization

    /// 仅读取 App 隐私授权状态，**不会**触发系统授权弹框。
    ///
    /// 适合在 UI 展示、进入页面前预检、或决定「是否需要调用 `request`」时使用。
    /// 对外入口：`AuthorizationStatus.status(for:)` / `snapshot(for:)`（后者还会查 `serviceState`）。
    ///
    /// | 权限 | 底层 API | 弹框 | 备注 |
    /// |------|----------|------|------|
    /// | 推送 | `UNUserNotificationCenter.getNotificationSettings` | 否 | 异步回调 |
    /// | 相机 | `AVCaptureDevice.authorizationStatus` | 否 | 同步 |
    /// | 相册 | `PHPhotoLibrary.authorizationStatus` | 否 | 同步；`.limited` → `.granted` |
    /// | 麦克风 | `AVAudioApplication` / `AVAudioSession.recordPermission` | 否 | 同步 |
    /// | 定位 | `CLLocationManager.authorizationStatus` | 否 | 同步；不含定位服务总开关（见 `serviceState`） |
    /// | 日历 / 提醒 | `EKEventStore.authorizationStatus` | 否 | 同步 |
    /// | Siri | `INPreferences.siriAuthorizationStatus` | 否 | capability 未开 → `.restricted` |
    /// | 蓝牙 | `CBManager.authorization` | 否 | 同步；仅隐私授权，不含硬件开关 |
    /// | 本地网络 | 缓存；已决定时会静默 re-probe 同步设置 | 否* | 无系统同步 API；`*` 未决定时不探测，避免误弹框 |
    static func authorizationStatus(for permission: AuthPermission, on host: AuthorizationStatus) async -> PermissionStatus {
        switch permission {
        case .apns:
            return await AuthPermissionMapping.notificationStatus()
        case .camera:
            return AuthPermissionMapping.avAuthorization(AVCaptureDevice.authorizationStatus(for: .video))
        case .photoLibrary:
            return AuthPermissionMapping.photoLibrary(PHPhotoLibrary.authorizationStatus(for: .readWrite))
        case .microphone:
            return AuthPermissionMapping.microphone()
        case .location:
            return host.locationCoordinator.authorizationStatus()
        case .calendar:
            return AuthPermissionMapping.eventStore(for: .event)
        case .reminder:
            return AuthPermissionMapping.eventStore(for: .reminder)
        case .siri:
            guard host.configuration.isSiriCapabilityEnabled else { return .restricted }
            return AuthPermissionMapping.siri(INPreferences.siriAuthorizationStatus())
        case .bluetooth:
            return AuthPermissionMapping.bluetooth(CBManager.authorization)
        case .localNetwork:
            host.localNetworkCoordinator.apply(host.configuration.localNetwork)
            return await host.localNetworkCoordinator.authorizationStatus()
        }
    }

    /// 请求 App 隐私授权；**仅当当前为 `.notDetermined` 时**才会调用系统请求 API 并**可能弹出系统授权框**。
    ///
    /// 已为 `.granted` / `.denied` / `.restricted` 时直接返回当前状态，不再弹框。
    /// 对外入口：`AuthorizationStatus.request(_:)`；推荐业务用 `resolve(_:requestIfNeeded:)` 先查快照再决定是否请求。
    ///
    /// | 权限 | 请求 API | 可能弹框 | 备注 |
    /// |------|----------|----------|------|
    /// | 推送 | `requestAuthorization(options:)` | 是（未决定时） | 拒绝后需引导用户去设置 |
    /// | 相机 | `AVCaptureDevice.requestAccess(for: .video)` | 是 | |
    /// | 相册 | `PHPhotoLibrary.requestAuthorization(for: .readWrite)` | 是 | iOS 14+ 可能出现「选择照片 / 全部 / 不允许」 |
    /// | 麦克风 | `AVAudioApplication.requestRecordPermission` / `AVAudioSession.requestRecordPermission` | 是 | |
    /// | 定位 | `requestWhenInUseAuthorization` / `requestAlwaysAuthorization` | 是 | 由 `location(_:)` 关联值决定级别；Always 可能二次弹框 |
    /// | 日历 / 提醒 | `requestFullAccessToEvents` / `requestFullAccessToReminders`（iOS 17+）或 `requestAccess` | 是 | |
    /// | Siri | `INPreferences.requestSiriAuthorization` | 是 | capability 未开 → 直接 `.restricted`，不弹框 |
    /// | 蓝牙 | **无**（仅读 `CBManager.authorization`） | **否** | 蓝牙隐私弹框由**首次创建并使用** `CBCentralManager` 触发（如扫描/连接），勿在此方法期望弹框 |
    /// | 本地网络 | Bonjour 推断 | 是（未决定时） | 探测总超时内收为 `grantConfirmationWait + 10s`（默认 25s）→ 超时 `.notDetermined` |
    ///
    /// UX 建议：在用户明确操作（如点「开启相机」）后再 `request`；避免冷启动批量弹框。蓝牙用 `snapshot` 判断后，在真正需要 BLE 时再初始化 `CBCentralManager`。本地网络在用户即将发现/连接局域网设备时再 `request`。
    static func request(_ permission: AuthPermission, on host: AuthorizationStatus) async -> PermissionStatus {
        let current = await authorizationStatus(for: permission, on: host)
        guard current == .notDetermined else { return current }

        switch permission {
        case .apns:
            return await AuthPermissionRequests.requestAPNs()
        case .camera:
            return await AuthPermissionRequests.requestCamera()
        case .photoLibrary:
            return await AuthPermissionRequests.requestPhotoLibrary()
        case .microphone:
            return await AuthPermissionRequests.requestMicrophone()
        case .location(let level):
            return await host.locationCoordinator.request(level)
        case .calendar:
            return await AuthPermissionRequests.requestCalendar()
        case .reminder:
            return await AuthPermissionRequests.requestReminder()
        case .siri:
            return await AuthPermissionRequests.requestSiri()
        case .bluetooth:
            return AuthPermissionMapping.bluetooth(CBManager.authorization)
        case .localNetwork:
            host.localNetworkCoordinator.apply(host.configuration.localNetwork)
            return await host.localNetworkCoordinator.request()
        }
    }

    // MARK: - Service

    /// 仅读取**系统服务能力**（硬件 / 总开关 / capability），**不会**触发隐私授权弹框。
    ///
    /// 与 `authorizationStatus` 分层：先判服务是否可用，再判 App 是否已授权（见 `snapshot`）。
    /// 无独立服务开关的权限返回 `nil`（推送、相册、麦克风、日历、提醒、本地网络）。
    ///
    /// | 权限 | 检查内容 | 弹框 | 备注 |
    /// |------|----------|------|------|
    /// | 相机 | 是否存在摄像头 | 否 | `.unsupported` = 无硬件 |
    /// | 定位 | `CLLocationManager.locationServicesEnabled()` | 否 | `.disabled` = 系统定位总开关关闭，需引导去设置 |
    /// | Siri | `configuration.isSiriCapabilityEnabled` | 否 | `.disabled` = 未在 Xcode 开启 capability |
    /// | 蓝牙 | `CBCentralManager.state`（经 `resolveBluetoothManagerState`） | 否* | `.disabled` = 蓝牙未开；`*` 读取 state 会用到已创建的 `centralManager`，**不**在此弹隐私框，但首次初始化 `CBCentralManager`  elsewhere 可能触发蓝牙授权 |
    /// | 其余 | — | — | 返回 `nil`，仅看授权层 |
    ///
    /// UX 建议：`service` 不可用时优先展示「去设置开启定位/蓝牙」等，勿再调用 `request`（`canRequestAuthorization` 已为 false）。
    static func serviceState(for permission: AuthPermission, on host: AuthorizationStatus) async -> AuthServiceState? {
        switch permission {
        case .camera:
            return AVCaptureDevice.default(for: .video) != nil ? .available : .unsupported
        case .location:
            return CLLocationManager.locationServicesEnabled() ? .available : .disabled
        case .siri:
            return AuthorizationStatus.configuration.isSiriCapabilityEnabled ? .available : .disabled
        case .bluetooth:
            return bluetoothServiceState(await host.resolveBluetoothManagerState())
        case .apns, .photoLibrary, .microphone, .calendar, .reminder, .localNetwork:
            return nil
        }
    }

    private static func bluetoothServiceState(_ managerState: CBManagerState) -> AuthServiceState {
        switch managerState {
        case .poweredOn:
            return .available
        case .poweredOff:
            return .disabled
        case .unsupported:
            return .unsupported
        case .unknown, .resetting, .unauthorized:
            return .unknown
        @unknown default:
            return .unknown
        }
    }
}
