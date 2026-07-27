//
//  AuthorizationStatus+Coordinators.swift
//  AppStart
//
//  系统 delegate 协调：定位授权、蓝牙硬件状态。

import CoreBluetooth
import CoreLocation

// MARK: - Location

/// 内部持有 `CLLocationManager`，避免外部 delegate 协议 + 全局强引用。
final class LocationAuthorizationCoordinator: NSObject, CLLocationManagerDelegate {

    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<PermissionStatus, Never>?

    override init() {
        super.init()
        manager.delegate = self
    }

    func authorizationStatus() -> PermissionStatus {
        AuthPermissionMapping.location(manager.authorizationStatus)
    }

    func request(_ level: LocationAuthLevel) async -> PermissionStatus {
        let current = authorizationStatus()
        guard current == .notDetermined else { return current }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            switch level {
            case .whenInUse:
                manager.requestWhenInUseAuthorization()
            case .always:
                manager.requestAlwaysAuthorization()
            }
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        finishIfNeeded(for: manager.authorizationStatus)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        finishIfNeeded(for: status)
    }

    private func finishIfNeeded(for status: CLAuthorizationStatus) {
        guard continuation != nil else { return }
        let mapped = AuthPermissionMapping.location(status)
        guard mapped != .notDetermined else { return }
        continuation?.resume(returning: mapped)
        continuation = nil
    }
}

// MARK: - Bluetooth

/// 蓝牙权限
/**
 <!-- 蓝牙 -->
 <key>NSBluetoothPeripheralUsageDescription</key>
 <string>App需要您的同意,才能访问蓝牙</string>
 <!-- 上面权限 官方 API 提示 iOS13 已废弃 -->
 <key>NSBluetoothAlwaysUsageDescription</key>
 <string>App需要您的同意,才能访问蓝牙</string>
 */

extension AuthorizationStatus: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if let continuation = bluetoothStateContinuation {
            bluetoothStateContinuation = nil
            continuation.resume(returning: central.state)
        }
    }
}
