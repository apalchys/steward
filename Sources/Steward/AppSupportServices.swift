import AppKit
import ApplicationServices
import Carbon
import Foundation
import HotKey

@MainActor
protocol PermissionStatusProviding {
    func isAccessibilityPermissionGranted() -> Bool
    func isScreenRecordingPermissionGranted() -> Bool
}

struct SystemPermissionStatusProvider: PermissionStatusProviding {
    func isAccessibilityPermissionGranted() -> Bool {
        AXIsProcessTrusted()
    }

    func isScreenRecordingPermissionGranted() -> Bool {
        CGPreflightScreenCaptureAccess()
    }
}

@MainActor
protocol ShortcutAvailabilityChecking {
    func isShortcutAvailable(key: Key, modifiers: NSEvent.ModifierFlags) -> Bool
}

struct SystemShortcutAvailabilityChecker: ShortcutAvailabilityChecking {
    private static let probeSignature = fourCharCode("StPr")

    func isShortcutAvailable(key: Key, modifiers: NSEvent.ModifierFlags) -> Bool {
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

@MainActor
protocol SystemSettingsOpening {
    func openApplicationSettings()
    func openAccessibilityPrivacySettings()
    func openScreenRecordingPrivacySettings()
}

struct SystemSettingsOpener: SystemSettingsOpening {
    private static let applicationSettingsSelector = Selector(("showSettingsWindow:"))
    private static let accessibilityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!
    private static let screenRecordingURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
    )!
    private static let systemSettingsAppURL = URL(fileURLWithPath: "/System/Applications/System Settings.app")

    private let workspace: NSWorkspace

    init(workspace: NSWorkspace = .shared) {
        self.workspace = workspace
    }

    func openApplicationSettings() {
        NSApp.activate(ignoringOtherApps: true)

        // AppState can request app settings outside a SwiftUI view hierarchy.
        // There is no public equivalent to OpenSettingsAction there, so keep
        // the selector fallback isolated to this adapter.
        _ = NSApp.sendAction(Self.applicationSettingsSelector, to: nil, from: nil)
    }

    func openAccessibilityPrivacySettings() {
        openSystemSettings(at: Self.accessibilityURL)
    }

    func openScreenRecordingPrivacySettings() {
        openSystemSettings(at: Self.screenRecordingURL)
    }

    private func openSystemSettings(at url: URL) {
        guard !workspace.open(url) else {
            return
        }

        _ = workspace.open(Self.systemSettingsAppURL)
    }
}
