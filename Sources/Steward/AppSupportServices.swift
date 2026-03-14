import AppKit
import ApplicationServices
import Carbon
import Foundation
import HotKey
import ServiceManagement

enum LaunchAtLoginStatus: Equatable {
    case notRegistered
    case enabled
    case requiresApproval
    case notFound

    var isEnabled: Bool {
        switch self {
        case .enabled, .requiresApproval:
            return true
        case .notRegistered, .notFound:
            return false
        }
    }
}

enum LaunchAtLoginError: LocalizedError, Equatable {
    case requiresApproval
    case invalidSignature
    case serviceUnavailable
    case unknown

    var errorDescription: String? {
        switch self {
        case .requiresApproval:
            return "Steward needs approval in System Settings > General > Login Items."
        case .invalidSignature:
            return "Steward could not configure launch at login because the app signature is invalid."
        case .serviceUnavailable:
            return "Steward could not configure launch at login because the system service is unavailable."
        case .unknown:
            return "Steward could not update launch at login."
        }
    }

    var shouldOfferOpenLoginItemsSettings: Bool {
        switch self {
        case .requiresApproval:
            return true
        case .invalidSignature, .serviceUnavailable, .unknown:
            return false
        }
    }
}

@MainActor
struct AppSystemServices {
    let isAccessibilityPermissionGranted: () -> Bool
    let isScreenRecordingPermissionGranted: () -> Bool
    let isShortcutAvailable: (Key, NSEvent.ModifierFlags) -> Bool
    let openApplicationSettings: () -> Void
    let openAccessibilityPrivacySettings: () -> Void
    let openScreenRecordingPrivacySettings: () -> Void
    let launchAtLoginStatus: () -> LaunchAtLoginStatus
    let setLaunchAtLoginEnabled: (Bool) throws -> Void
    let openLoginItemsSettings: () -> Void

    static func live(
        workspace: NSWorkspace = .shared,
        openLoginItemsSettingsAction: @escaping () -> Void = {
            SMAppService.openSystemSettingsLoginItems()
        }
    ) -> AppSystemServices {
        AppSystemServices(
            isAccessibilityPermissionGranted: {
                AXIsProcessTrusted()
            },
            isScreenRecordingPermissionGranted: {
                CGPreflightScreenCaptureAccess()
            },
            isShortcutAvailable: { key, modifiers in
                isShortcutAvailable(key: key, modifiers: modifiers)
            },
            openApplicationSettings: {
                openApplicationSettings()
            },
            openAccessibilityPrivacySettings: {
                openSystemSettings(at: accessibilityURL, workspace: workspace)
            },
            openScreenRecordingPrivacySettings: {
                openSystemSettings(at: screenRecordingURL, workspace: workspace)
            },
            launchAtLoginStatus: {
                launchAtLoginStatus(from: SMAppService.mainApp.status)
            },
            setLaunchAtLoginEnabled: { isEnabled in
                try setLaunchAtLoginEnabled(isEnabled)
            },
            openLoginItemsSettings: {
                openLoginItemsSettingsAction()
            }
        )
    }

    private static let applicationSettingsSelector = Selector(("showSettingsWindow:"))
    private static let accessibilityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
    private static let screenRecordingURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!
    private static let systemSettingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")
    private static let probeSignature = fourCharCode("StPr")

    private static func openApplicationSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // AppState can request app settings outside a SwiftUI view hierarchy.
        // There is no public equivalent to OpenSettingsAction there, so keep
        // the selector fallback isolated to this adapter.
        _ = NSApp.sendAction(Self.applicationSettingsSelector, to: nil, from: nil)
    }

    private static func openSystemSettings(at url: URL, workspace: NSWorkspace) {
        guard !workspace.open(url) else {
            return
        }

        _ = workspace.open(Self.systemSettingsAppURL)
    }

    static func launchAtLoginStatus(from status: SMAppService.Status) -> LaunchAtLoginStatus {
        switch status {
        case .notRegistered:
            return .notRegistered
        case .enabled:
            return .enabled
        case .requiresApproval:
            return .requiresApproval
        case .notFound:
            return .notFound
        @unknown default:
            return .notFound
        }
    }

    static func setLaunchAtLoginEnabled(_ isEnabled: Bool) throws {
        do {
            if isEnabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch let error as NSError {
            if isIdempotentLaunchAtLoginError(error, isEnabled: isEnabled) {
                return
            }

            throw launchAtLoginError(from: error)
        } catch {
            throw LaunchAtLoginError.unknown
        }
    }

    static func launchAtLoginError(from error: NSError) -> LaunchAtLoginError {
        switch error.code {
        case kSMErrorLaunchDeniedByUser:
            return .requiresApproval
        case kSMErrorInvalidSignature:
            return .invalidSignature
        case kSMErrorServiceUnavailable:
            return .serviceUnavailable
        default:
            return .unknown
        }
    }

    static func isIdempotentLaunchAtLoginError(_ error: NSError, isEnabled: Bool) -> Bool {
        if isEnabled {
            return error.code == kSMErrorAlreadyRegistered
        }

        return error.code == kSMErrorJobNotFound
    }

    private static func isShortcutAvailable(key: Key, modifiers: NSEvent.ModifierFlags) -> Bool {
        let keyCombo = KeyCombo(key: key, modifiers: modifiers)
        let hotKeyID = EventHotKeyID(signature: Self.probeSignature, id: 1)
        var eventHotKey: EventHotKeyRef?
        let registerError = RegisterEventHotKey(
            keyCombo.carbonKeyCode,
            keyCombo.carbonModifiers,
            hotKeyID,
            GetEventDispatcherTarget(),
            0,
            &eventHotKey
        )

        guard registerError == noErr, let eventHotKey else {
            return false
        }

        UnregisterEventHotKey(eventHotKey)
        return true
    }

    private static func fourCharCode(_ string: String) -> FourCharCode {
        string.utf16.reduce(0) { result, character in
            (result << 8) + FourCharCode(character)
        }
    }
}
