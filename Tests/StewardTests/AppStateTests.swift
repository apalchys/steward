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
        let refineCoordinator = FakeRefineCoordinator()
        let captureCoordinator = FakeCaptureCoordinator()
        let dictateCoordinator = FakeDictateCoordinator()
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: clipboardHistoryStore,
            clipboardMonitor: clipboardMonitor,
            llmRouter: router,
            refineCoordinator: refineCoordinator,
            captureCoordinator: captureCoordinator,
            dictateCoordinator: dictateCoordinator,
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        XCTAssertEqual(
            appState.shortcutRegistrationMessage,
            "Shortcut unavailable: Refine (Command-Shift-F) is already in use by another app."
        )
    }

    func testStartPublishesDictateShortcutConflictMessageWhenShortcutIsUnavailable() async {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(unavailableKeyCodes: [Key.d.carbonKeyCode])
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        XCTAssertEqual(
            appState.shortcutRegistrationMessage,
            """
            Shortcut unavailable: Dictate Push-to-Talk (Command-Shift-D) is already in use by another app.
            Shortcut unavailable: Dictate Regular (Command-Option-D) is already in use by another app.
            """
        )
    }

    func testSettingsDidChangeRegistersCustomDictateShortcutImmediately() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore()
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()
        appSystemServices.resetCheckedHotKeys()

        settingsStore.settings.voice.hotKey = AppHotKey(
            carbonKeyCode: Key.v.carbonKeyCode,
            carbonModifiers: NSEvent.ModifierFlags([.command, .option]).carbonFlags
        )

        appState.settingsDidChange()
        await Task.yield()

        XCTAssertTrue(appSystemServices.checkedHotKeys.contains(settingsStore.settings.voice.hotKey))
        XCTAssertNil(appState.shortcutRegistrationMessage)
    }

    func testSettingsDidChangeRegistersMouseButtonDictateShortcutImmediately() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore()
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()
        appSystemServices.resetCheckedHotKeys()

        settingsStore.settings.voice.hotKey = AppHotKey(mouseButtonNumber: 4)

        appState.settingsDidChange()
        await Task.yield()

        XCTAssertEqual(appSystemServices.registeredMouseHotKeys, [settingsStore.settings.voice.hotKey])
        XCTAssertEqual(appSystemServices.checkedHotKeys, [settingsStore.settings.voice.regularModeHotKey])
        XCTAssertNil(appState.shortcutRegistrationMessage)
    }

    func testSettingsDidChangeRejectsVoiceShortcutThatConflictsWithRefine() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore()
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()
        appSystemServices.resetCheckedHotKeys()

        settingsStore.settings.voice.hotKey = .refine

        appState.settingsDidChange()
        await Task.yield()

        XCTAssertEqual(appSystemServices.checkedHotKeys, [settingsStore.settings.voice.regularModeHotKey])
        XCTAssertEqual(
            appState.shortcutRegistrationMessage,
            "Shortcut unavailable: Dictate Push-to-Talk (Command-Shift-F) conflicts with Refine."
        )
    }

    func testSettingsDidChangeRejectsRegularShortcutThatConflictsWithPushToTalk() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore()
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()
        appSystemServices.resetCheckedHotKeys()

        settingsStore.settings.voice.regularModeHotKey = settingsStore.settings.voice.pushToTalkHotKey

        appState.settingsDidChange()
        await Task.yield()

        XCTAssertTrue(appSystemServices.checkedHotKeys.isEmpty)
        XCTAssertEqual(
            appState.shortcutRegistrationMessage,
            """
            Shortcut unavailable: Dictate Push-to-Talk (Command-Shift-D) conflicts with Dictate Regular.
            Shortcut unavailable: Dictate Regular (Command-Shift-D) conflicts with Dictate Push-to-Talk.
            """
        )
    }

    func testValidateDictateHotKeyRejectsRefineConflict() {
        _ = NSApplication.shared
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: FakeAppSystemServices().services
        )

        XCTAssertEqual(
            appState.validateDictateHotKey(.refine),
            .conflictsWithFeature("Refine")
        )
    }

    func testValidateDictateHotKeyRejectsUnavailableShortcut() {
        _ = NSApplication.shared
        let unavailableHotKey = AppHotKey(
            carbonKeyCode: Key.v.carbonKeyCode,
            carbonModifiers: NSEvent.ModifierFlags([.command, .option]).carbonFlags
        )
        let appSystemServices = FakeAppSystemServices()
        appSystemServices.unavailableHotKeys = [unavailableHotKey]
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: appSystemServices.services
        )

        XCTAssertEqual(appState.validateDictateHotKey(unavailableHotKey), AppHotKeyValidationError.unavailable)
    }

    func testValidateDictateHotKeyAllowsMouseButtonWithoutModifier() {
        _ = NSApplication.shared
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: FakeAppSystemServices().services
        )

        XCTAssertNil(appState.validateDictateHotKey(AppHotKey(mouseButtonNumber: 4)))
    }

    func testValidateRegularDictateHotKeyRejectsPushToTalkConflict() {
        _ = NSApplication.shared
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: FakeAppSystemServices().services
        )

        XCTAssertEqual(
            appState.validateRegularDictateHotKey(.defaultVoiceDictation),
            .conflictsWithFeature("Dictate Push-to-Talk")
        )
    }

    func testMouseDictateShortcutInvokesPushToTalkHandlers() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore()
        settingsStore.settings.voice.hotKey = AppHotKey(mouseButtonNumber: 4)
        let dictateCoordinator = FakeDictateCoordinator()
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: dictateCoordinator,
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        appSystemServices.lastMouseMonitor?.simulateButtonDown()
        await Task.yield()
        appSystemServices.lastMouseMonitor?.simulateButtonUp()
        await Task.yield()

        XCTAssertEqual(dictateCoordinator.handlePushToTalkKeyDownCallCount, 1)
        XCTAssertEqual(dictateCoordinator.handlePushToTalkKeyUpCallCount, 1)
    }

    func testMouseRegularDictateShortcutInvokesToggleHandler() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore()
        settingsStore.settings.voice.regularModeHotKey = AppHotKey(mouseButtonNumber: 4)
        let dictateCoordinator = FakeDictateCoordinator()
        let appSystemServices = FakeAppSystemServices()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: dictateCoordinator,
            appSystemServices: appSystemServices.services
        )

        appState.start()
        await Task.yield()

        appSystemServices.lastMouseMonitor?.simulateButtonDown()
        await Task.yield()
        appSystemServices.lastMouseMonitor?.simulateButtonUp()
        await Task.yield()

        XCTAssertEqual(dictateCoordinator.handleRegularHotKeyToggleActionCallCount, 1)
        XCTAssertEqual(dictateCoordinator.handlePushToTalkKeyDownCallCount, 0)
        XCTAssertEqual(dictateCoordinator.handlePushToTalkKeyUpCallCount, 0)
    }

    func testStartRefreshesLaunchAtLoginStatus() async {
        _ = NSApplication.shared
        let appSystemServices = FakeAppSystemServices(launchAtLoginStatus: .enabled)
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
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
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: appSystemServices.services
        )

        appState.openLoginItemsSettings()

        XCTAssertEqual(appSystemServices.openLoginItemsSettingsCallCount, 1)
    }

    func testRunDictateActionInvokesDictateCoordinator() async {
        _ = NSApplication.shared
        let dictateCoordinator = FakeDictateCoordinator()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: dictateCoordinator,
            appSystemServices: FakeAppSystemServices().services
        )

        appState.runDictateAction()
        await Task.yield()

        XCTAssertEqual(dictateCoordinator.handleManualToggleActionCallCount, 1)
    }

    func testDictateRecordingUpdatesActivityStatusTitle() async {
        _ = NSApplication.shared
        let dictateCoordinator = FakeDictateCoordinator()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: dictateCoordinator,
            appSystemServices: FakeAppSystemServices().services
        )

        appState.start()
        appState.checkRefineProviderStatus()
        appState.checkCaptureProviderStatus()
        appState.checkDictateProviderStatus()
        await Task.yield()

        dictateCoordinator.onStateChanged?(.recording)
        await Task.yield()

        XCTAssertEqual(appState.activityStatus, .processing)
        XCTAssertTrue(appState.shouldShowActivityStatusTitle)
        XCTAssertEqual(appState.activityStatusTitle, "Status: Listening...")

        dictateCoordinator.onStateChanged?(.transcribing)
        await Task.yield()

        XCTAssertEqual(appState.activityStatusTitle, "Status: Transcribing...")

        dictateCoordinator.onStateChanged?(.idle)
        await Task.yield()

        XCTAssertEqual(appState.activityStatus, .ready)
        XCTAssertFalse(appState.shouldShowActivityStatusTitle)
        XCTAssertEqual(appState.activityStatusTitle, "Status: Ready")
    }

    func testDictateRecordingBlocksRefineActionUntilIdle() async {
        _ = NSApplication.shared
        let refineCoordinator = FakeRefineCoordinator()
        let dictateCoordinator = FakeDictateCoordinator()
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: refineCoordinator,
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: dictateCoordinator,
            appSystemServices: FakeAppSystemServices().services
        )

        appState.start()
        dictateCoordinator.onStateChanged?(.recording)
        await Task.yield()

        appState.runRefineAction()
        await Task.yield()

        XCTAssertEqual(refineCoordinator.handleHotKeyPressCallCount, 0)

        dictateCoordinator.onStateChanged?(.idle)
        await Task.yield()

        appState.runRefineAction()
        await Task.yield()

        XCTAssertEqual(refineCoordinator.handleHotKeyPressCallCount, 1)
    }

    func testCheckDictateProviderStatusUsesSelectedProviderAndUpdatesTitle() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore()
        let voiceSelection = LLMModelSelection(providerID: .openAI, modelID: "gpt-4o-mini-transcribe")
        settingsStore.settings.providerSettings[.openAI] = LLMProviderSettings(apiKey: "openai-key")
        settingsStore.settings.voice = VoiceSettings(selectedModel: voiceSelection)
        let router = FakeAppRouter()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: router,
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: FakeAppSystemServices().services
        )

        appState.checkDictateProviderStatus()
        await Task.yield()

        XCTAssertEqual(router.checkedSelections, [voiceSelection])
        XCTAssertEqual(appState.dictateStatusTitle, "Dictate: OpenAI Ready")
    }

    func testProviderMenuStatusesShowUniqueProvidersInsteadOfFeatures() async {
        _ = NSApplication.shared
        let appState = AppState(
            settingsStore: FakeAppSettingsStore(),
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: FakeAppRouter(),
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: FakeAppSystemServices().services
        )

        appState.checkRefineProviderStatus()
        appState.checkCaptureProviderStatus()
        appState.checkDictateProviderStatus()
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(
            appState.providerMenuStatuses.map(\.title),
            ["OpenAI: Ready", "Gemini: Ready"]
        )
    }

    func testCheckProviderStatusRefreshesAllFeaturesUsingProvider() async {
        _ = NSApplication.shared
        let settingsStore = FakeAppSettingsStore()
        let screenSelection = settingsStore.settings.screenText.selectedModel!
        let voiceSelection = settingsStore.settings.voice.selectedModel!
        let router = FakeAppRouter()
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: ClipboardHistoryStore(autoLoad: false),
            clipboardMonitor: FakeClipboardMonitor(),
            llmRouter: router,
            refineCoordinator: FakeRefineCoordinator(),
            captureCoordinator: FakeCaptureCoordinator(),
            dictateCoordinator: FakeDictateCoordinator(),
            appSystemServices: FakeAppSystemServices().services
        )

        appState.checkProviderStatus(for: .gemini)
        await Task.yield()
        await Task.yield()

        XCTAssertEqual(router.checkedSelections, [screenSelection, voiceSelection])
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
    private(set) var checkedSelections: [LLMModelSelection] = []

    func perform(_ request: LLMRequest) async throws -> LLMResult {
        .text("ok")
    }

    func checkAccess(for selection: LLMModelSelection) async throws -> LLMProviderHealth {
        checkedSelections.append(selection)
        return LLMProviderHealth(providerID: selection.providerID, state: .available, message: "Ready")
    }
}

private final class FakeRefineCoordinator: RefineCoordinating {
    private(set) var handleHotKeyPressCallCount = 0

    func handleHotKeyPress() async throws {
        handleHotKeyPressCallCount += 1
    }
}

private final class FakeCaptureCoordinator: CaptureCoordinating {
    var onSelectionActivityChanged: ((Bool) -> Void)?

    func handleHotKeyPress() async throws {}
}

private final class FakeDictateCoordinator: DictateCoordinating {
    var onStateChanged: ((DictateWorkflowState) -> Void)?
    var onError: ((any Error) -> Void)?
    private(set) var handleManualToggleActionCallCount = 0
    private(set) var handleRegularHotKeyToggleActionCallCount = 0
    private(set) var handlePushToTalkKeyDownCallCount = 0
    private(set) var handlePushToTalkKeyUpCallCount = 0

    func handleManualToggleAction() async throws {
        handleManualToggleActionCallCount += 1
    }

    func handleRegularHotKeyToggleAction() async throws {
        handleRegularHotKeyToggleActionCallCount += 1
    }

    func handlePushToTalkKeyDown() async throws {
        handlePushToTalkKeyDownCallCount += 1
    }

    func handlePushToTalkKeyUp() async throws {
        handlePushToTalkKeyUpCallCount += 1
    }
}

private final class FakeAppSettingsStore: AppSettingsProviding {
    var settings = LLMSettings.empty()

    init(historySettings: ClipboardHistorySettings = ClipboardHistorySettings()) {
        settings.providerSettings[.openAI] = LLMProviderSettings(apiKey: "openai-key")
        settings.providerSettings[.gemini] = LLMProviderSettings(apiKey: "gemini-key")
        settings.refine.selectedModel = LLMModelSelection(providerID: .openAI, modelID: "gpt-5.4")
        settings.screenText.selectedModel = LLMModelSelection(
            providerID: .gemini,
            modelID: "gemini-3.1-flash-lite-preview"
        )
        settings.voice.selectedModel = LLMModelSelection(
            providerID: .gemini,
            modelID: "gemini-3.1-flash-lite-preview"
        )
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
    var unavailableHotKeys: Set<AppHotKey> = []
    var setLaunchAtLoginEnabledError: Error?
    private(set) var openAccessibilityPrivacySettingsCallCount = 0
    private(set) var openMicrophonePrivacySettingsCallCount = 0
    private(set) var openScreenRecordingPrivacySettingsCallCount = 0
    private(set) var openLoginItemsSettingsCallCount = 0
    private(set) var setLaunchAtLoginEnabledCalls: [Bool] = []
    private(set) var checkedHotKeys: [AppHotKey] = []
    private(set) var registeredMouseHotKeys: [AppHotKey] = []
    private(set) var lastMouseMonitor: FakeMouseButtonShortcutMonitor?

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

    func resetCheckedHotKeys() {
        checkedHotKeys.removeAll()
    }

    var services: AppSystemServices {
        AppSystemServices(
            isAccessibilityPermissionGranted: { self.accessibilityPermissionGranted },
            isMicrophonePermissionGranted: { self.microphonePermissionGranted },
            isScreenRecordingPermissionGranted: { self.screenRecordingPermissionGranted },
            isShortcutAvailable: { key, modifiers in
                let hotKey = AppHotKey(carbonKeyCode: key.carbonKeyCode, carbonModifiers: modifiers.carbonFlags)
                self.checkedHotKeys.append(hotKey)
                return !self.unavailableKeyCodes.contains(key.carbonKeyCode)
                    && !self.unavailableHotKeys.contains(hotKey)
            },
            makeMouseButtonMonitor: { buttonNumber, modifiers, onButtonDown, onButtonUp in
                let hotKey = AppHotKey(mouseButtonNumber: buttonNumber, carbonModifiers: modifiers.carbonFlags)
                self.registeredMouseHotKeys.append(hotKey)
                let monitor = FakeMouseButtonShortcutMonitor(
                    buttonNumber: buttonNumber,
                    modifiers: modifiers,
                    onButtonDown: onButtonDown,
                    onButtonUp: onButtonUp
                )
                self.lastMouseMonitor = monitor
                return monitor
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

@MainActor
private final class FakeMouseButtonShortcutMonitor: MouseButtonShortcutMonitoring {
    let buttonNumber: Int
    let modifiers: NSEvent.ModifierFlags
    private let onButtonDown: @MainActor () -> Void
    private let onButtonUp: @MainActor () -> Void
    private(set) var stopCallCount = 0

    init(
        buttonNumber: Int,
        modifiers: NSEvent.ModifierFlags,
        onButtonDown: @escaping @MainActor () -> Void,
        onButtonUp: @escaping @MainActor () -> Void
    ) {
        self.buttonNumber = buttonNumber
        self.modifiers = modifiers
        self.onButtonDown = onButtonDown
        self.onButtonUp = onButtonUp
    }

    func simulateButtonDown() {
        onButtonDown()
    }

    func simulateButtonUp() {
        onButtonUp()
    }

    func stop() {
        stopCallCount += 1
    }
}
