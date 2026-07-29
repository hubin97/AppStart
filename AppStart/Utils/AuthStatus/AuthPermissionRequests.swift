//
//  AuthPermissionRequests.swift
//  AppStart
//
//  各权限的系统 API 调用（async 封装）。

import AVFoundation
import EventKit
import Intents
import Photos
import UserNotifications

enum AuthPermissionRequests {

    static func requestAPNs() async -> PermissionStatus {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                continuation.resume(returning: granted ? .granted : .denied)
            }
        }
    }

    static func requestCamera() async -> PermissionStatus {
        await AuthPermissionMapping.avAuthorization(await requestCameraAccess())
    }

    static func requestPhotoLibrary() async -> PermissionStatus {
        await AuthPermissionMapping.photoLibrary(await requestPhotoLibraryAccess())
    }

    static func requestMicrophone() async -> PermissionStatus {
        await AuthPermissionMapping.microphone(granted: await requestMicrophoneAccess())
    }

    static func requestSiri() async -> PermissionStatus {
        guard AuthorizationStatus.configuration.isSiriCapabilityEnabled else { return .restricted }
        return await AuthPermissionMapping.siri(await requestSiriAuthorization())
    }

    static func requestCalendar() async -> PermissionStatus {
        await requestEventAccess(for: .event)
    }

    static func requestReminder() async -> PermissionStatus {
        await requestEventAccess(for: .reminder)
    }

    // MARK: - Private

    private static func requestCameraAccess() async -> AVAuthorizationStatus {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { _ in
                continuation.resume(returning: AVCaptureDevice.authorizationStatus(for: .video))
            }
        }
    }

    private static func requestPhotoLibraryAccess() async -> PHAuthorizationStatus {
        await withCheckedContinuation { continuation in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func requestMicrophoneAccess() async -> Bool {
        if #available(iOS 17.0, *) {
            return await AVAudioApplication.requestRecordPermission()
        }
        return await withCheckedContinuation { continuation in
            AVAudioSession.sharedInstance().requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }

    private static func requestSiriAuthorization() async -> INSiriAuthorizationStatus {
        guard AuthorizationStatus.configuration.isSiriCapabilityEnabled else { return .denied }
        return await withCheckedContinuation { continuation in
            INPreferences.requestSiriAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private static func requestEventAccess(for entity: EKEntityType) async -> PermissionStatus {
        if #available(iOS 17.0, *) {
            let status = EKEventStore.authorizationStatus(for: entity)
            switch status {
            case .fullAccess, .writeOnly:
                return .granted
            case .notDetermined:
                return await withCheckedContinuation { continuation in
                    let store = EKEventStore()
                    switch entity {
                    case .event:
                        store.requestFullAccessToEvents { granted, _ in
                            continuation.resume(returning: granted ? .granted : .denied)
                        }
                    case .reminder:
                        store.requestFullAccessToReminders { granted, _ in
                            continuation.resume(returning: granted ? .granted : .denied)
                        }
                    @unknown default:
                        continuation.resume(returning: .denied)
                    }
                }
            case .denied:
                return .denied
            case .restricted:
                return .restricted
            @unknown default:
                return .denied
            }
        }
        return await withCheckedContinuation { continuation in
            EKEventStore().requestAccess(to: entity) { granted, _ in
                continuation.resume(returning: granted ? .granted : .denied)
            }
        }
    }
}
