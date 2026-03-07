import AppKit
import ApplicationServices
import Carbon
import Foundation
import HotKey

@MainActor
struct AppSystemServices {
    let isAccessibilityPermissionGranted: () -> Bool
    let isScreenRecordingPermissionGranted: () -> Bool
    let isShortcutAvailable: (Key, NSEvent.ModifierFlags) -> Bool
    let openApplicationSettings: () -> Void
    let openAccessibilityPrivacySettings: () -> Void
    let openScreenRecordingPrivacySettings: () -> Void

    static func live(workspace: NSWorkspace = .shared) -> AppSystemServices {
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
