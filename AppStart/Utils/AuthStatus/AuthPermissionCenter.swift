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
/// | 推送 / 相册 / 麦克风 / 日历 / 提醒 | — | 对应隐私授权 |
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

    static func authorizationStatus(for permission: AuthPermission, on host: AuthorizationStatus) async -> PermissionStatus {
        switch permission {
        case .apns:
            return await AuthPermissionRequests.notificationStatus()
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
            guard AuthorizationStatus.isSiriCapabilityEnabled else { return .restricted }
            return AuthPermissionMapping.siri(INPreferences.siriAuthorizationStatus())
        case .bluetooth:
            return AuthPermissionMapping.bluetooth(CBManager.authorization)
        }
    }

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
        }
    }

    // MARK: - Service

    static func serviceState(for permission: AuthPermission, on host: AuthorizationStatus) async -> AuthServiceState? {
        switch permission {
        case .camera:
            return AVCaptureDevice.default(for: .video) != nil ? .available : .unsupported
        case .location:
            return CLLocationManager.locationServicesEnabled() ? .available : .disabled
        case .siri:
            return AuthorizationStatus.isSiriCapabilityEnabled ? .available : .disabled
        case .bluetooth:
            return bluetoothServiceState(await host.resolveBluetoothManagerState())
        case .apns, .photoLibrary, .microphone, .calendar, .reminder:
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
