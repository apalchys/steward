import AppKit
import HotKey
import XCTest
@testable import Steward

@MainActor
final class AppStateTests: XCTestCase {
    func testStartIsIdempotentForClipboardMonitor() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore(
            historySettings: ClipboardHistorySettings(isEnabled: true)
        )
        let clipboardHistoryStore = ClipboardHistoryStore(autoLoad: false)
        let clipboardMonitor = FakeClipboardMonitor()
        let router = FakeAppRouter()
        let grammarCoordinator = FakeGrammarCoordinator()
        let screenOCRCoordinator = FakeScreenOCRCoordinator()
        let permissionStatusProvider = FakePermissionStatusProvider()
        let shortcutAvailabilityChecker = FakeShortcutAvailabilityChecker()
        let systemSettingsOpener = FakeSystemSettingsOpener()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: clipboardHistoryStore,
            clipboardMonitor: clipboardMonitor,
            llmRouter: router,
            grammarCoordinator: grammarCoordinator,
            screenOCRCoordinator: screenOCRCoordinator,
            permissionStatusProvider: permissionStatusProvider,
            shortcutAvailabilityChecker: shortcutAvailabilityChecker,
            systemSettingsOpener: systemSettingsOpener
        )

        appState.start()
        appState.start()
        await Task.yield()

        XCTAssertEqual(clipboardMonitor.startCallCount, 1)
    }

    func testStartRefreshesPermissionStatuses() async {
        _ = NSApplication.shared
        let permissionStatusProvider = FakePermissionStatusProvider(
            accessibilityPermissionGranted: true,
            screenRecordingPermissionGranted: false
        )
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            permissionStatusProvider: permissionStatusProvider,
            shortcutAvailabilityChecker: FakeShortcutAvailabilityChecker(),
            systemSettingsOpener: FakeSystemSettingsOpener()
        )

        appState.start()
        await Task.yield()

        XCTAssertTrue(appState.accessibilityPermissionGranted)
        XCTAssertFalse(appState.screenRecordingPermissionGranted)
        XCTAssertEqual(appState.screenRecordingStatusTitle, "Screen Recording: Open Privacy Settings")
    }

    func testStartPublishesShortcutConflictMessageWhenShortcutIsUnavailable() async {
        _ = NSApplication.shared
        let shortcutAvailabilityChecker = FakeShortcutAvailabilityChecker(unavailableKeyCodes: [Key.f.carbonKeyCode])
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            permissionStatusProvider: FakePermissionStatusProvider(),
            shortcutAvailabilityChecker: shortcutAvailabilityChecker,
            systemSettingsOpener: FakeSystemSettingsOpener()
        )

        appState.start()
        await Task.yield()

        XCTAssertEqual(
            appState.shortcutRegistrationMessage,
            "Shortcut unavailable: Grammar Check (Command-Shift-F) is already in use by another app."
        )
    }

    func testOpenPreferencesUsesSettingsOpener() {
        _ = NSApplication.shared
        let systemSettingsOpener = FakeSystemSettingsOpener()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            permissionStatusProvider: FakePermissionStatusProvider(),
            shortcutAvailabilityChecker: FakeShortcutAvailabilityChecker(),
            systemSettingsOpener: systemSettingsOpener
        )

        appState.openPreferences()

        XCTAssertEqual(systemSettingsOpener.openApplicationSettingsCallCount, 1)
    }
}

@MainActor
private final class FakeClipboardMonitor: ClipboardMonitoring {
    private(set) var startCallCount = 0
    private(set) var stopCallCount = 0

    func start() {
        startCallCount += 1
    }

    func stop() {
        stopCallCount += 1
    }

    func suppressNextClipboardChanges(_ count: Int) {}
}

@MainActor
private final class FakeAppRouter: LLMRouting {
    func perform(_ request: LLMRequest) async throws -> LLMResult {
        .text("ok")
    }

    func checkAccess(for providerID: LLMProviderID) async throws -> LLMProviderHealth {
        LLMProviderHealth(providerID: providerID, state: .available, message: "Ready")
    }
}

private final class FakeGrammarCoordinator: GrammarCoordinating {
    func handleHotKeyPress() async throws {}
}

private final class FakeScreenOCRCoordinator: ScreenOCRCoordinating {
    var onSelectionActivityChanged: ((Bool) -> Void)?

    func handleHotKeyPress() async throws {}
}

private final class FakeAppSettingsStore: AppSettingsProviding {
    private var settings = LLMSettings.empty()

    init(historySettings: ClipboardHistorySettings = ClipboardHistorySettings()) {
        settings.clipboardHistory = historySettings
    }

    func loadSettings() -> LLMSettings {
        settings
    }

    func saveSettings(_ settings: LLMSettings) {
        self.settings = settings
    }
}

private struct FakePermissionStatusProvider: PermissionStatusProviding {
    var accessibilityPermissionGranted = false
    var screenRecordingPermissionGranted = false

    func isAccessibilityPermissionGranted() -> Bool {
        accessibilityPermissionGranted
    }

    func isScreenRecordingPermissionGranted() -> Bool {
        screenRecordingPermissionGranted
    }
}

private struct FakeShortcutAvailabilityChecker: ShortcutAvailabilityChecking {
    var unavailableKeyCodes: Set<UInt32> = []

    func isShortcutAvailable(key: Key, modifiers: NSEvent.ModifierFlags) -> Bool {
        !unavailableKeyCodes.contains(key.carbonKeyCode)
    }
}

private final class FakeSystemSettingsOpener: SystemSettingsOpening {
    private(set) var openApplicationSettingsCallCount = 0
    private(set) var openAccessibilityPrivacySettingsCallCount = 0
    private(set) var openScreenRecordingPrivacySettingsCallCount = 0

    func openApplicationSettings() {
        openApplicationSettingsCallCount += 1
    }

    func openAccessibilityPrivacySettings() {
        openAccessibilityPrivacySettingsCallCount += 1
    }

    func openScreenRecordingPrivacySettings() {
        openScreenRecordingPrivacySettingsCallCount += 1
    }
}
