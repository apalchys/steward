import AppKit
import Foundation
import HotKey
import OSLog
import SwiftUI

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.steward", category: "app")

@MainActor
protocol ClipboardMonitoring: ClipboardChangeSuppressing {
    func start()
    func stop()
}

extension ClipboardMonitor: ClipboardMonitoring {}

@MainActor
final class AppState: ObservableObject {
    private struct AppShortcut {
        let title: String
        let key: Key
        let modifiers: NSEvent.ModifierFlags
        let displayValue: String
    }

    private enum FeatureKind {
        case grammar
        case ocr

        var statusPrefix: String {
            switch self {
            case .grammar:
                return "Grammar"
            case .ocr:
                return "Screen Text"
            }
        }

        var logLabel: String {
            statusPrefix
        }
    }

    private enum StatusSymbolName {
        static let readyFallback = "pencil.and.outline"
        static let error = "exclamationmark.triangle"
        static let processing = "ellipsis.circle"
    }

    private static let readyStatusIconImage = StatusBarIcon.readyImage()
    private static let readyFallbackImage = StatusBarIcon.symbolImage(named: StatusSymbolName.readyFallback)
    private static let processingImage = StatusBarIcon.symbolImage(named: StatusSymbolName.processing)
    private static let errorImage = StatusBarIcon.symbolImage(named: StatusSymbolName.error)

    let settingsStore: any AppSettingsProviding
    let clipboardHistoryStore: ClipboardHistoryStore

    @Published private(set) var activityStatus: ActivityStatus = .ready
    @Published private(set) var grammarStatus: ProviderStatus = .error(providerID: nil, message: "Not checked")
    @Published private(set) var ocrStatus: ProviderStatus = .error(providerID: nil, message: "Not checked")
    @Published private(set) var accessibilityPermissionGranted = false
    @Published private(set) var screenRecordingPermissionGranted = false
    @Published private(set) var shortcutRegistrationMessage: String?
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
    @Published private(set) var isUpdatingLaunchAtLogin = false
    @Published private(set) var launchAtLoginMessage: String?
    @Published private(set) var shouldShowOpenLoginItemsAction = false

    private let clipboardMonitor: any ClipboardMonitoring
    private let llmRouter: any LLMRouting
    private let grammarCoordinator: any GrammarCoordinating
    private let screenOCRCoordinator: any ScreenOCRCoordinating
    private let appSystemServices: AppSystemServices

    private var grammarHotKey: HotKey?
    private var screenOCRHotKey: HotKey?
    private var hasStarted = false
    private var initialHealthCheckTask: Task<Void, Never>?
    private var settingsHealthDebounceTask: Task<Void, Never>?
    private var grammarHealthCheckTask: Task<Void, Never>?
    private var ocrHealthCheckTask: Task<Void, Never>?

    private var isProcessing = false
    private var isScreenSelectionActive = false
    private var lastOperationFailed = false

    init(
        settingsStore: any AppSettingsProviding,
        clipboardHistoryStore: ClipboardHistoryStore,
        clipboardMonitor: any ClipboardMonitoring,
        llmRouter: any LLMRouting,
        grammarCoordinator: any GrammarCoordinating,
        screenOCRCoordinator: any ScreenOCRCoordinating,
        appSystemServices: AppSystemServices
    ) {
        self.settingsStore = settingsStore
        self.clipboardHistoryStore = clipboardHistoryStore
        self.clipboardMonitor = clipboardMonitor
        self.llmRouter = llmRouter
        self.grammarCoordinator = grammarCoordinator
        self.screenOCRCoordinator = screenOCRCoordinator
        self.appSystemServices = appSystemServices

        Task { [weak self] in
            self?.start()
        }
    }

    var statusBarIconImage: NSImage {
        switch activityStatus {
        case .ready:
            return Self.readyStatusIconImage ?? Self.readyFallbackImage
        case .processing:
            return Self.processingImage
        case .error:
            return Self.errorImage
        }
    }

    var activityStatusTitle: String {
        switch activityStatus {
        case .ready:
            return "Status: Ready"
        case .processing:
            if isScreenSelectionActive {
                return "Status: Select an area..."
            }
            return "Status: Processing..."
        case .error:
            if lastOperationFailed {
                return "Status: Last operation failed"
            }
            return "Status: Provider configuration required"
        }
    }

    var grammarStatusTitle: String {
        providerStatusTitle(prefix: FeatureKind.grammar.statusPrefix, status: grammarStatus)
    }

    var ocrStatusTitle: String {
        providerStatusTitle(prefix: FeatureKind.ocr.statusPrefix, status: ocrStatus)
    }

    var accessibilityStatusTitle: String {
        accessibilityPermissionGranted ? "Accessibility: Granted" : "Accessibility: Open Privacy Settings"
    }

    var screenRecordingStatusTitle: String {
        screenRecordingPermissionGranted ? "Screen Recording: Granted" : "Screen Recording: Open Privacy Settings"
    }

    var shouldShowPermissionActions: Bool {
        !accessibilityPermissionGranted || !screenRecordingPermissionGranted
    }

    var isLaunchAtLoginEnabled: Bool {
        launchAtLoginStatus.isEnabled
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        NSApp.setActivationPolicy(.accessory)

        refreshPermissionStatuses()
        refreshLaunchAtLoginStatus()
        setupHotKeys()
        applyClipboardHistorySettings()

        screenOCRCoordinator.onSelectionActivityChanged = { [weak self] isActive in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isScreenSelectionActive = isActive
                self.refreshStatusUI()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.clipboardMonitor.stop()
            }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.refreshLaunchAtLoginStatus()
            }
        }

        initialHealthCheckTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self, !Task.isCancelled else {
                return
            }

            self.checkGrammarProviderStatus()
            self.checkOCRProviderStatus()
        }
    }

    func runGrammarAction() {
        handleHotKeyPress(for: .grammar)
    }

    func runScreenOCRAction() {
        handleHotKeyPress(for: .ocr)
    }

    func checkGrammarProviderStatus() {
        checkProviderStatus(for: .grammar)
    }

    func checkOCRProviderStatus() {
        checkProviderStatus(for: .ocr)
    }

    func settingsDidChange() {
        applyClipboardHistorySettings()
        initialHealthCheckTask?.cancel()
        settingsHealthDebounceTask?.cancel()
        settingsHealthDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else {
                return
            }

            self.checkGrammarProviderStatus()
            self.checkOCRProviderStatus()
        }
    }

    func openPreferences() {
        refreshLaunchAtLoginStatus()
        openSettingsWindow()
    }

    func refreshPermissionStatuses() {
        accessibilityPermissionGranted = appSystemServices.isAccessibilityPermissionGranted()
        screenRecordingPermissionGranted = appSystemServices.isScreenRecordingPermissionGranted()
    }

    func openAccessibilityPrivacySettings() {
        appSystemServices.openAccessibilityPrivacySettings()
    }

    func openScreenRecordingPrivacySettings() {
        appSystemServices.openScreenRecordingPrivacySettings()
    }

    func refreshLaunchAtLoginStatus() {
        updateLaunchAtLoginState(status: appSystemServices.launchAtLoginStatus())
    }

    func setLaunchAtLoginEnabled(_ isEnabled: Bool) {
        isUpdatingLaunchAtLogin = true
        defer { isUpdatingLaunchAtLogin = false }

        do {
            try appSystemServices.setLaunchAtLoginEnabled(isEnabled)
            logger.log("Launch at login updated. enabled=\(isEnabled, privacy: .public)")
            updateLaunchAtLoginState(status: appSystemServices.launchAtLoginStatus())
        } catch let error as LaunchAtLoginError {
            logger.error("Launch at login update failed: \(error.localizedDescription)")
            updateLaunchAtLoginState(
                status: appSystemServices.launchAtLoginStatus(),
                messageOverride: error.errorDescription,
                showOpenSettingsActionOverride: error.shouldOfferOpenLoginItemsSettings
            )
        } catch {
            logger.error("Launch at login update failed: \(error.localizedDescription)")
            updateLaunchAtLoginState(
                status: appSystemServices.launchAtLoginStatus(),
                messageOverride: LaunchAtLoginError.unknown.errorDescription
            )
        }
    }

    func openLoginItemsSettings() {
        appSystemServices.openLoginItemsSettings()
    }

    private func setupHotKeys() {
        let grammarShortcut = AppShortcut(
            title: "Grammar Check",
            key: .f,
            modifiers: [.command, .shift],
            displayValue: "Command-Shift-F"
        )
        let screenOCRShortcut = AppShortcut(
            title: "Screen Text Capture",
            key: .r,
            modifiers: [.command, .shift],
            displayValue: "Command-Shift-R"
        )

        var unavailableShortcuts: [AppShortcut] = []

        if let hotKey = makeHotKey(
            for: grammarShortcut,
            action: { [weak self] in
                self?.handleHotKeyPress(for: .grammar)
            })
        {
            grammarHotKey = hotKey
        } else {
            unavailableShortcuts.append(grammarShortcut)
        }

        if let hotKey = makeHotKey(
            for: screenOCRShortcut,
            action: { [weak self] in
                self?.handleHotKeyPress(for: .ocr)
            })
        {
            screenOCRHotKey = hotKey
        } else {
            unavailableShortcuts.append(screenOCRShortcut)
        }

        shortcutRegistrationMessage = shortcutConflictMessage(for: unavailableShortcuts)
    }

    private func checkProviderStatus(for feature: FeatureKind) {
        let providerID = providerID(for: feature)
        setStatus(.processing(providerID: providerID), for: feature)
        refreshStatusUI()

        healthCheckTask(for: feature)?.cancel()
        setHealthCheckTask(
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    let health = try await self.llmRouter.checkAccess(for: providerID)
                    guard !Task.isCancelled else {
                        return
                    }
                    self.setStatus(self.providerStatus(from: health), for: feature)
                } catch {
                    guard !Task.isCancelled else {
                        return
                    }
                    self.setStatus(.error(providerID: providerID, message: error.localizedDescription), for: feature)
                }

                self.refreshStatusUI()
            },
            for: feature
        )
    }

    private func handleHotKeyPress(for feature: FeatureKind) {
        guard !isProcessing else {
            return
        }

        lastOperationFailed = false
        isProcessing = true

        setStatus(.processing(providerID: providerID(for: feature)), for: feature)
        refreshStatusUI()

        Task {
            do {
                try await performOperation(for: feature)
                self.lastOperationFailed = false
                self.markStatusFromCurrentConfiguration(for: feature, asError: false, message: nil)
            } catch {
                if self.shouldIgnoreFailure(for: feature, error: error) {
                    self.lastOperationFailed = false
                } else {
                    self.lastOperationFailed = true
                    self.markStatusFromCurrentConfiguration(
                        for: feature, asError: true, message: error.localizedDescription)
                    if self.shouldOpenSettings(for: error) {
                        self.openSettingsWindow()
                    }
                    logger.error("\(feature.logLabel) error: \(error.localizedDescription)")
                }
            }

            self.isProcessing = false
            self.refreshStatusUI()
        }
    }

    private func shouldOpenSettings(for error: Error) -> Bool {
        switch error {
        case is LLMRouterError:
            return true
        default:
            return false
        }
    }

    private func openSettingsWindow() {
        appSystemServices.openApplicationSettings()
    }

    private func markStatusFromCurrentConfiguration(for feature: FeatureKind, asError: Bool, message: String?) {
        let providerID = providerID(for: feature)
        let status: ProviderStatus =
            asError
            ? .error(providerID: providerID, message: message ?? "Error")
            : .ok(providerID: providerID)
        setStatus(status, for: feature)
    }

    private func providerID(for feature: FeatureKind) -> LLMProviderID {
        switch feature {
        case .grammar:
            return LLMSettings.grammarProvider
        case .ocr:
            return LLMSettings.screenshotProvider
        }
    }

    private func setStatus(_ status: ProviderStatus, for feature: FeatureKind) {
        switch feature {
        case .grammar:
            grammarStatus = status
        case .ocr:
            ocrStatus = status
        }
    }

    private func healthCheckTask(for feature: FeatureKind) -> Task<Void, Never>? {
        switch feature {
        case .grammar:
            return grammarHealthCheckTask
        case .ocr:
            return ocrHealthCheckTask
        }
    }

    private func setHealthCheckTask(_ task: Task<Void, Never>, for feature: FeatureKind) {
        switch feature {
        case .grammar:
            grammarHealthCheckTask = task
        case .ocr:
            ocrHealthCheckTask = task
        }
    }

    private func performOperation(for feature: FeatureKind) async throws {
        switch feature {
        case .grammar:
            try await grammarCoordinator.handleHotKeyPress()
        case .ocr:
            try await screenOCRCoordinator.handleHotKeyPress()
        }
    }

    private func shouldIgnoreFailure(for feature: FeatureKind, error: Error) -> Bool {
        switch feature {
        case .grammar:
            if case GrammarCoordinatorError.noSelectedText = error {
                return true
            }
        case .ocr:
            if case ScreenOCRCoordinatorError.cancelled = error {
                return true
            }
        }

        return false
    }

    private func refreshStatusUI() {
        if isScreenSelectionActive || isProcessing {
            activityStatus = .processing
            return
        }

        if lastOperationFailed || hasErrorStatus(grammarStatus) || hasErrorStatus(ocrStatus) {
            activityStatus = .error
            return
        }

        activityStatus = .ready
    }

    private func hasErrorStatus(_ status: ProviderStatus) -> Bool {
        if case .error = status {
            return true
        }

        return false
    }

    private func applyClipboardHistorySettings() {
        let clipboardHistorySettings = settingsStore.loadSettings().clipboardHistory
        clipboardHistoryStore.updateMaxStoredRecords(clipboardHistorySettings.maxStoredRecords)

        if clipboardHistorySettings.isEnabled {
            clipboardMonitor.start()
        } else {
            clipboardMonitor.stop()
        }
    }

    private func updateLaunchAtLoginState(
        status: LaunchAtLoginStatus,
        messageOverride: String? = nil,
        showOpenSettingsActionOverride: Bool? = nil
    ) {
        launchAtLoginStatus = status
        launchAtLoginMessage = messageOverride ?? defaultLaunchAtLoginMessage(for: status)

        let defaultActionVisibility = status == .requiresApproval
        shouldShowOpenLoginItemsAction = showOpenSettingsActionOverride ?? defaultActionVisibility
    }

    private func defaultLaunchAtLoginMessage(for status: LaunchAtLoginStatus) -> String? {
        switch status {
        case .requiresApproval:
            return LaunchAtLoginError.requiresApproval.errorDescription
        case .notFound:
            return "Steward could not locate its login item registration."
        case .enabled, .notRegistered:
            return nil
        }
    }

    private func providerStatusTitle(prefix: String, status: ProviderStatus) -> String {
        switch status {
        case .ok(let providerID):
            return "\(prefix): \(providerID.displayName) Ready"
        case .processing(let providerID):
            if let providerID {
                return "\(prefix): \(providerID.displayName) Checking..."
            }

            return "\(prefix): Checking..."
        case .error(let providerID, let message):
            if let providerID {
                return "\(prefix): \(providerID.displayName) \(message)"
            }

            return "\(prefix): \(message)"
        }
    }

    private func providerStatus(from health: LLMProviderHealth) -> ProviderStatus {
        if health.hasAccess {
            return .ok(providerID: health.providerID)
        }

        return .error(providerID: health.providerID, message: providerStatusMessage(for: health))
    }

    private func providerStatusMessage(for health: LLMProviderHealth) -> String {
        switch health.state {
        case .available:
            return "Ready"
        case .notConfigured:
            return "Needs setup in Preferences"
        case .invalidCredentials:
            return "Check API key"
        case .invalidModel:
            return "Check model"
        case .networkIssue:
            return "Network issue"
        case .rateLimited:
            return "Rate limited"
        case .serviceIssue:
            return "Service unavailable"
        case .unknown:
            return health.message
        }
    }

    private func makeHotKey(for shortcut: AppShortcut, action: @escaping @MainActor () -> Void) -> HotKey? {
        guard appSystemServices.isShortcutAvailable(shortcut.key, shortcut.modifiers) else {
            logger.error("Shortcut unavailable: \(shortcut.displayValue, privacy: .public)")
            return nil
        }

        let hotKey = HotKey(key: shortcut.key, modifiers: shortcut.modifiers)
        hotKey.keyDownHandler = {
            Task { @MainActor in
                action()
            }
        }
        return hotKey
    }

    private func shortcutConflictMessage(for shortcuts: [AppShortcut]) -> String? {
        guard !shortcuts.isEmpty else {
            return nil
        }

        let descriptions = shortcuts.map { "\($0.title) (\($0.displayValue))" }
        let summary = descriptions.joined(separator: ", ")
        let verb = shortcuts.count == 1 ? "is" : "are"
        return "Shortcut unavailable: \(summary) \(verb) already in use by another app."
    }
}
