//
//  AuthPermissionMapping.swift
//  AppStart
//
//  系统授权枚举 → `PermissionStatus` 映射。

import AVFoundation
import CoreBluetooth
import CoreLocation
import EventKit
import Intents
import Photos
import UserNotifications

enum AuthPermissionMapping {

    static func notification(_ status: UNAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized, .provisional, .ephemeral:
            return .granted
        case .denied:
            return .denied
        case .notDetermined:
            return .notDetermined
        @unknown default:
            return .denied
        }
    }

    static func avAuthorization(_ status: AVAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    static func photoLibrary(_ status: PHAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized, .limited:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    static func microphone() -> PermissionStatus {
        if #available(iOS 17.0, *) {
            switch AVAudioApplication.shared.recordPermission {
            case .granted: return .granted
            case .undetermined: return .notDetermined
            case .denied: return .denied
            @unknown default: return .denied
            }
        }
        switch AVAudioSession.sharedInstance().recordPermission {
        case .granted: return .granted
        case .undetermined: return .notDetermined
        case .denied: return .denied
        @unknown default: return .denied
        }
    }

    static func microphone(granted: Bool) -> PermissionStatus {
        granted ? .granted : .denied
    }

    static func location(_ status: CLAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorizedAlways, .authorizedWhenInUse:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    static func eventStore(for entity: EKEntityType) -> PermissionStatus {
        if #available(iOS 17.0, *) {
            switch EKEventStore.authorizationStatus(for: entity) {
            case .fullAccess, .writeOnly:
                return .granted
            case .notDetermined:
                return .notDetermined
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            @unknown default:
                return .denied
            }
        }
        switch EKEventStore.authorizationStatus(for: entity) {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    static func siri(_ status: INSiriAuthorizationStatus) -> PermissionStatus {
        switch status {
        case .authorized:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }

    static func bluetooth(_ status: CBManagerAuthorization) -> PermissionStatus {
        switch status {
        case .allowedAlways:
            return .granted
        case .notDetermined:
            return .notDetermined
        case .denied:
            return .denied
        case .restricted:
            return .restricted
        @unknown default:
            return .denied
        }
    }
}
