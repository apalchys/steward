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
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: clipboardHistoryStore,
            clipboardMonitor: clipboardMonitor,
            llmRouter: router,
            grammarCoordinator: grammarCoordinator,
            screenOCRCoordinator: screenOCRCoordinator,
            appSystemServices: appSystemServices.services
        )

        appState.start()
        appState.start()
        await Task.yield()

        XCTAssertEqual(clipboardMonitor.startCallCount, 1)
    }

    func testStartRefreshesPermissionStatuses() async {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(
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
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        XCTAssertTrue(appState.accessibilityPermissionGranted)
        XCTAssertFalse(appState.screenRecordingPermissionGranted)
        XCTAssertEqual(appState.screenRecordingStatusTitle, "Screen Recording: Open Privacy Settings")
        XCTAssertTrue(appState.shouldShowPermissionActions)
    }

    func testStartHidesPermissionActionsWhenAllPermissionsAreGranted() async {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(
            accessibilityPermissionGranted: true,
            screenRecordingPermissionGranted: true
        )
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        XCTAssertFalse(appState.shouldShowPermissionActions)
    }

    func testStartPublishesShortcutConflictMessageWhenShortcutIsUnavailable() async {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(unavailableKeyCodes: [Key.f.carbonKeyCode])
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            appSystemServices: appSystemServices.services
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
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.openPreferences()

        XCTAssertEqual(appSystemServices.openApplicationSettingsCallCount, 1)
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

@MainActor
private final class FakeAppSystemServices {
    var accessibilityPermissionGranted = false
    var screenRecordingPermissionGranted = false
    var unavailableKeyCodes: Set<UInt32> = []
    private(set) var openApplicationSettingsCallCount = 0
    private(set) var openAccessibilityPrivacySettingsCallCount = 0
    private(set) var openScreenRecordingPrivacySettingsCallCount = 0

    init(
        accessibilityPermissionGranted: Bool = false,
        screenRecordingPermissionGranted: Bool = false,
        unavailableKeyCodes: Set<UInt32> = []
    ) {
        self.accessibilityPermissionGranted = accessibilityPermissionGranted
        self.screenRecordingPermissionGranted = screenRecordingPermissionGranted
        self.unavailableKeyCodes = unavailableKeyCodes
    }

    var services: AppSystemServices {
        AppSystemServices(
            isAccessibilityPermissionGranted: { self.accessibilityPermissionGranted },
            isScreenRecordingPermissionGranted: { self.screenRecordingPermissionGranted },
            isShortcutAvailable: { key, _ in
                !self.unavailableKeyCodes.contains(key.carbonKeyCode)
            },
            openApplicationSettings: {
                self.openApplicationSettingsCallCount += 1
            },
            openAccessibilityPrivacySettings: {
                self.openAccessibilityPrivacySettingsCallCount += 1
            },
            openScreenRecordingPrivacySettings: {
                self.openScreenRecordingPrivacySettingsCallCount += 1
            }
        )
    }
}
