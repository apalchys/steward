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
        let voiceDictationCoordinator = FakeVoiceDictationCoordinator()
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: clipboardHistoryStore,
            clipboardMonitor: clipboardMonitor,
            llmRouter: router,
            grammarCoordinator: grammarCoordinator,
            screenOCRCoordinator: screenOCRCoordinator,
            voiceDictationCoordinator: voiceDictationCoordinator,
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
            microphonePermissionGranted: false,
            screenRecordingPermissionGranted: false
        )
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        XCTAssertTrue(appState.accessibilityPermissionGranted)
        XCTAssertFalse(appState.microphonePermissionGranted)
        XCTAssertFalse(appState.screenRecordingPermissionGranted)
        XCTAssertEqual(appState.microphoneStatusTitle, "Microphone: Open Privacy Settings")
        XCTAssertEqual(appState.screenRecordingStatusTitle, "Screen Recording: Open Privacy Settings")
        XCTAssertTrue(appState.shouldShowPermissionActions)
    }

    func testStartHidesPermissionActionsWhenAllPermissionsAreGranted() async {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(
            accessibilityPermissionGranted: true,
            microphonePermissionGranted: true,
            screenRecordingPermissionGranted: true
        )
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        XCTAssertFalse(appState.shouldShowPermissionActions)
    }

    func testOpenMicrophonePrivacySettingsUsesSystemServices() {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.openMicrophonePrivacySettings()

        XCTAssertEqual(appSystemServices.openMicrophonePrivacySettingsCallCount, 1)
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
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        XCTAssertEqual(
            appState.shortcutRegistrationMessage,
            "Shortcut unavailable: Grammar Check (Command-Shift-F) is already in use by another app."
        )
    }

    func testStartPublishesVoiceShortcutConflictMessageWhenVoiceShortcutIsUnavailable() async {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(unavailableKeyCodes: [Key.d.carbonKeyCode])
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        XCTAssertEqual(
            appState.shortcutRegistrationMessage,
            "Shortcut unavailable: Voice Dictation (Command-Shift-D) is already in use by another app."
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
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.openPreferences()

        XCTAssertEqual(appSystemServices.openApplicationSettingsCallCount, 1)
    }

    func testStartRefreshesLaunchAtLoginStatus() async {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(launchAtLoginStatus: .enabled)
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        XCTAssertEqual(appState.launchAtLoginStatus, .enabled)
        XCTAssertTrue(appState.isLaunchAtLoginEnabled)
        XCTAssertNil(appState.launchAtLoginMessage)
    }

    func testSetLaunchAtLoginEnabledTurnsOnAndRefreshesStatus() {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(launchAtLoginStatus: .notRegistered)
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(appSystemServices.setLaunchAtLoginEnabledCalls, [true])
        XCTAssertEqual(appState.launchAtLoginStatus, .enabled)
        XCTAssertTrue(appState.isLaunchAtLoginEnabled)
        XCTAssertNil(appState.launchAtLoginMessage)
    }

    func testSetLaunchAtLoginEnabledTurnsOffAndRefreshesStatus() {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(launchAtLoginStatus: .enabled)
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.setLaunchAtLoginEnabled(false)

        XCTAssertEqual(appSystemServices.setLaunchAtLoginEnabledCalls, [false])
        XCTAssertEqual(appState.launchAtLoginStatus, .notRegistered)
        XCTAssertFalse(appState.isLaunchAtLoginEnabled)
        XCTAssertNil(appState.launchAtLoginMessage)
    }

    func testRefreshLaunchAtLoginStatusShowsRequiresApprovalMessage() {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(launchAtLoginStatus: .requiresApproval)
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.refreshLaunchAtLoginStatus()

        XCTAssertEqual(appState.launchAtLoginStatus, .requiresApproval)
        XCTAssertEqual(appState.launchAtLoginMessage, LaunchAtLoginError.requiresApproval.errorDescription)
        XCTAssertTrue(appState.shouldShowOpenLoginItemsAction)
    }

    func testRefreshLaunchAtLoginStatusShowsNotFoundMessage() {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(launchAtLoginStatus: .notFound)
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.refreshLaunchAtLoginStatus()

        XCTAssertEqual(appState.launchAtLoginStatus, .notFound)
        XCTAssertEqual(appState.launchAtLoginMessage, "Steward could not locate its login item registration.")
    }

    func testSetLaunchAtLoginEnabledWithRequiresApprovalErrorShowsActionableMessage() {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(launchAtLoginStatus: .requiresApproval)
        appSystemServices.setLaunchAtLoginEnabledError = LaunchAtLoginError.requiresApproval
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.setLaunchAtLoginEnabled(true)

        XCTAssertEqual(appState.launchAtLoginStatus, .requiresApproval)
        XCTAssertEqual(appState.launchAtLoginMessage, LaunchAtLoginError.requiresApproval.errorDescription)
        XCTAssertTrue(appState.shouldShowOpenLoginItemsAction)
    }

    func testOpenLoginItemsSettingsUsesSystemServices() {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.openLoginItemsSettings()

        XCTAssertEqual(appSystemServices.openLoginItemsSettingsCallCount, 1)
    }

    func testRunVoiceDictationActionInvokesVoiceCoordinator() async {
        _ = NSApplication.shared
        let voiceDictationCoordinator = FakeVoiceDictationCoordinator()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: voiceDictationCoordinator,
            appSystemServices: FakeAppSystemServices().services
        )

        appState.runVoiceDictationAction()
        await Task.yield()

        XCTAssertEqual(voiceDictationCoordinator.handleHotKeyPressCallCount, 1)
    }

    func testVoiceRecordingUpdatesActivityStatusTitle() async {
        _ = NSApplication.shared
        let voiceDictationCoordinator = FakeVoiceDictationCoordinator()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: voiceDictationCoordinator,
            appSystemServices: FakeAppSystemServices().services
        )

        appState.start()
        appState.checkGrammarProviderStatus()
        appState.checkOCRProviderStatus()
        appState.checkVoiceProviderStatus()
        await Task.yield()

        voiceDictationCoordinator.onStateChanged?(.recording)
        await Task.yield()

        XCTAssertEqual(appState.activityStatus, .processing)
        XCTAssertEqual(appState.activityStatusTitle, "Status: Listening...")

        voiceDictationCoordinator.onStateChanged?(.transcribing)
        await Task.yield()

        XCTAssertEqual(appState.activityStatusTitle, "Status: Transcribing...")

        voiceDictationCoordinator.onStateChanged?(.idle)
        await Task.yield()

        XCTAssertEqual(appState.activityStatus, .ready)
        XCTAssertEqual(appState.activityStatusTitle, "Status: Ready")
    }

    func testVoiceRecordingBlocksGrammarActionUntilIdle() async {
        _ = NSApplication.shared
        let grammarCoordinator = FakeGrammarCoordinator()
        let voiceDictationCoordinator = FakeVoiceDictationCoordinator()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            grammarCoordinator: grammarCoordinator,
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: voiceDictationCoordinator,
            appSystemServices: FakeAppSystemServices().services
        )

        appState.start()
        voiceDictationCoordinator.onStateChanged?(.recording)
        await Task.yield()

        appState.runGrammarAction()
        await Task.yield()

        XCTAssertEqual(grammarCoordinator.handleHotKeyPressCallCount, 0)

        voiceDictationCoordinator.onStateChanged?(.idle)
        await Task.yield()

        appState.runGrammarAction()
        await Task.yield()

        XCTAssertEqual(grammarCoordinator.handleHotKeyPressCallCount, 1)
    }

    func testCheckVoiceProviderStatusUsesSelectedVoiceProviderAndUpdatesTitle() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore()
        settingsStore.settings.voice = VoiceSettings(providerID: .openAI)
        let router = FakeAppRouter()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: router,
            grammarCoordinator: FakeGrammarCoordinator(),
            screenOCRCoordinator: FakeScreenOCRCoordinator(),
            voiceDictationCoordinator: FakeVoiceDictationCoordinator(),
            appSystemServices: FakeAppSystemServices().services
        )

        appState.checkVoiceProviderStatus()
        await Task.yield()

        XCTAssertEqual(router.checkedProviderIDs, [.openAI])
        XCTAssertEqual(appState.voiceStatusTitle, "Voice Dictation: OpenAI Ready")
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
    private(set) var checkedProviderIDs: [LLMProviderID] = []

    func perform(_ request: LLMRequest) async throws -> LLMResult {
        .text("ok")
    }

    func checkAccess(for providerID: LLMProviderID) async throws -> LLMProviderHealth {
        checkedProviderIDs.append(providerID)
        return LLMProviderHealth(providerID: providerID, state: .available, message: "Ready")
    }
}

private final class FakeGrammarCoordinator: GrammarCoordinating {
    private(set) var handleHotKeyPressCallCount = 0

    func handleHotKeyPress() async throws {
        handleHotKeyPressCallCount += 1
    }
}

private final class FakeScreenOCRCoordinator: ScreenOCRCoordinating {
    var onSelectionActivityChanged: ((Bool) -> Void)?

    func handleHotKeyPress() async throws {}
}

private final class FakeVoiceDictationCoordinator: VoiceDictationCoordinating {
    var onStateChanged: ((VoiceDictationWorkflowState) -> Void)?
    var onError: ((any Error) -> Void)?
    private(set) var handleHotKeyPressCallCount = 0

    func handleHotKeyPress() async throws {
        handleHotKeyPressCallCount += 1
    }
}

private final class FakeAppSettingsStore: AppSettingsProviding {
    var settings = LLMSettings.empty()

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
    var microphonePermissionGranted = false
    var screenRecordingPermissionGranted = false
    var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
    var unavailableKeyCodes: Set<UInt32> = []
    var setLaunchAtLoginEnabledError: Error?
    private(set) var openApplicationSettingsCallCount = 0
    private(set) var openAccessibilityPrivacySettingsCallCount = 0
    private(set) var openMicrophonePrivacySettingsCallCount = 0
    private(set) var openScreenRecordingPrivacySettingsCallCount = 0
    private(set) var openLoginItemsSettingsCallCount = 0
    private(set) var setLaunchAtLoginEnabledCalls: [Bool] = []

    init(
        accessibilityPermissionGranted: Bool = false,
        microphonePermissionGranted: Bool = false,
        screenRecordingPermissionGranted: Bool = false,
        launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered,
        unavailableKeyCodes: Set<UInt32> = []
    ) {
        self.accessibilityPermissionGranted = accessibilityPermissionGranted
        self.microphonePermissionGranted = microphonePermissionGranted
        self.screenRecordingPermissionGranted = screenRecordingPermissionGranted
        self.launchAtLoginStatus = launchAtLoginStatus
        self.unavailableKeyCodes = unavailableKeyCodes
    }

    var services: AppSystemServices {
        AppSystemServices(
            isAccessibilityPermissionGranted: { self.accessibilityPermissionGranted },
            isMicrophonePermissionGranted: { self.microphonePermissionGranted },
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
            openMicrophonePrivacySettings: {
                self.openMicrophonePrivacySettingsCallCount += 1
            },
            openScreenRecordingPrivacySettings: {
                self.openScreenRecordingPrivacySettingsCallCount += 1
            },
            launchAtLoginStatus: {
                self.launchAtLoginStatus
            },
            setLaunchAtLoginEnabled: { isEnabled in
                self.setLaunchAtLoginEnabledCalls.append(isEnabled)

                if let error = self.setLaunchAtLoginEnabledError {
                    throw error
                }

                self.launchAtLoginStatus = isEnabled ? .enabled : .notRegistered
            },
            openLoginItemsSettings: {
                self.openLoginItemsSettingsCallCount += 1
            }
        )
    }
}
