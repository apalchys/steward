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

    private enum StatusSymbolName {
        static let readyFallback = "pencil.and.outline"
        static let error = "exclamationmark.triangle"
        static let processing = "ellipsis.circle"
    }

    private static let readyStatusIconImage = StatusBarIcon.readyImage()
    private static let readyFallbackImage = StatusBarIcon.symbolImage(named: StatusSymbolName.readyFallback)
    private static let processingImage = StatusBarIcon.symbolImage(named: StatusSymbolName.processing)
    private static let errorImage = StatusBarIcon.symbolImage(named: StatusSymbolName.error)

    let settingsStore: any LLMSettingsProviding & ClipboardHistorySettingsProviding
    let clipboardHistoryStore: ClipboardHistoryStore

    @Published private(set) var activityStatus: ActivityStatus = .ready
    @Published private(set) var grammarStatus: ProviderStatus = .error(providerID: nil, message: "Not checked")
    @Published private(set) var ocrStatus: ProviderStatus = .error(providerID: nil, message: "Not checked")
    @Published private(set) var accessibilityPermissionGranted = false
    @Published private(set) var screenRecordingPermissionGranted = false
    @Published private(set) var shortcutRegistrationMessage: String?

    private let clipboardMonitor: any ClipboardMonitoring
    private let llmRouter: any LLMRouting
    private let grammarCoordinator: any GrammarCoordinating
    private let screenOCRCoordinator: any ScreenOCRCoordinating
    private let permissionStatusProvider: PermissionStatusProviding
    private let shortcutAvailabilityChecker: ShortcutAvailabilityChecking
    private let systemSettingsOpener: SystemSettingsOpening

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
        settingsStore: any LLMSettingsProviding & ClipboardHistorySettingsProviding,
        clipboardHistoryStore: ClipboardHistoryStore,
        clipboardMonitor: any ClipboardMonitoring,
        llmRouter: any LLMRouting,
        grammarCoordinator: any GrammarCoordinating,
        screenOCRCoordinator: any ScreenOCRCoordinating,
        permissionStatusProvider: PermissionStatusProviding,
        shortcutAvailabilityChecker: ShortcutAvailabilityChecking,
        systemSettingsOpener: SystemSettingsOpening
    ) {
        self.settingsStore = settingsStore
        self.clipboardHistoryStore = clipboardHistoryStore
        self.clipboardMonitor = clipboardMonitor
        self.llmRouter = llmRouter
        self.grammarCoordinator = grammarCoordinator
        self.screenOCRCoordinator = screenOCRCoordinator
        self.permissionStatusProvider = permissionStatusProvider
        self.shortcutAvailabilityChecker = shortcutAvailabilityChecker
        self.systemSettingsOpener = systemSettingsOpener

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
        providerStatusTitle(prefix: "Grammar", status: grammarStatus)
    }

    var ocrStatusTitle: String {
        providerStatusTitle(prefix: "OCR", status: ocrStatus)
    }

    var accessibilityStatusTitle: String {
        accessibilityPermissionGranted ? "Accessibility: Granted" : "Accessibility: Open Privacy Settings"
    }

    var screenRecordingStatusTitle: String {
        screenRecordingPermissionGranted ? "Screen Recording: Granted" : "Screen Recording: Open Privacy Settings"
    }

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        NSApp.setActivationPolicy(.accessory)

        refreshPermissionStatuses()
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
        handleGrammarHotKeyPress()
    }

    func runScreenOCRAction() {
        handleScreenOCRHotKeyPress()
    }

    func checkGrammarProviderStatus() {
        let providerID = currentGrammarProviderID()
        grammarStatus = .processing(providerID: providerID)
        refreshStatusUI()

        grammarHealthCheckTask?.cancel()
        grammarHealthCheckTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let health = try await self.llmRouter.checkAccess(for: providerID)
                guard !Task.isCancelled else {
                    return
                }
                self.grammarStatus = self.providerStatus(from: health)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self.grammarStatus = .error(
                    providerID: providerID,
                    message: error.localizedDescription
                )
            }

            self.refreshStatusUI()
        }
    }

    func checkOCRProviderStatus() {
        let providerID = currentScreenshotProviderID()
        ocrStatus = .processing(providerID: providerID)
        refreshStatusUI()

        ocrHealthCheckTask?.cancel()
        ocrHealthCheckTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            do {
                let health = try await self.llmRouter.checkAccess(for: providerID)
                guard !Task.isCancelled else {
                    return
                }
                self.ocrStatus = self.providerStatus(from: health)
            } catch {
                guard !Task.isCancelled else {
                    return
                }
                self.ocrStatus = .error(
                    providerID: providerID,
                    message: error.localizedDescription
                )
            }

            self.refreshStatusUI()
        }
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
        openSettingsWindow()
    }

    func refreshPermissionStatuses() {
        accessibilityPermissionGranted = permissionStatusProvider.isAccessibilityPermissionGranted()
        screenRecordingPermissionGranted = permissionStatusProvider.isScreenRecordingPermissionGranted()
    }

    func openAccessibilityPrivacySettings() {
        systemSettingsOpener.openAccessibilityPrivacySettings()
    }

    func openScreenRecordingPrivacySettings() {
        systemSettingsOpener.openScreenRecordingPrivacySettings()
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
                self?.handleGrammarHotKeyPress()
            })
        {
            grammarHotKey = hotKey
        } else {
            unavailableShortcuts.append(grammarShortcut)
        }

        if let hotKey = makeHotKey(
            for: screenOCRShortcut,
            action: { [weak self] in
                self?.handleScreenOCRHotKeyPress()
            })
        {
            screenOCRHotKey = hotKey
        } else {
            unavailableShortcuts.append(screenOCRShortcut)
        }

        shortcutRegistrationMessage = shortcutConflictMessage(for: unavailableShortcuts)
    }

    private func handleGrammarHotKeyPress() {
        guard !isProcessing else {
            return
        }

        lastOperationFailed = false
        isProcessing = true

        grammarStatus = .processing(providerID: currentGrammarProviderID())
        refreshStatusUI()

        Task {
            do {
                try await grammarCoordinator.handleHotKeyPress()
                self.lastOperationFailed = false
                self.markGrammarStatusFromCurrentConfiguration(asError: false, message: nil)
            } catch {
                if case GrammarCoordinatorError.noSelectedText = error {
                    self.lastOperationFailed = false
                } else {
                    self.lastOperationFailed = true
                    self.markGrammarStatusFromCurrentConfiguration(
                        asError: true, message: error.localizedDescription)
                    if self.shouldOpenSettings(for: error) {
                        self.openSettingsWindow()
                    }
                    logger.error("Grammar error: \(error.localizedDescription)")
                }
            }

            self.isProcessing = false
            self.refreshStatusUI()
        }
    }

    private func handleScreenOCRHotKeyPress() {
        guard !isProcessing else {
            return
        }

        lastOperationFailed = false
        isProcessing = true

        ocrStatus = .processing(providerID: currentScreenshotProviderID())
        refreshStatusUI()

        Task {
            do {
                try await screenOCRCoordinator.handleHotKeyPress()
                self.lastOperationFailed = false
                self.markOCRStatusFromCurrentConfiguration(asError: false, message: nil)
            } catch {
                if case ScreenOCRCoordinatorError.cancelled = error {
                    self.lastOperationFailed = false
                } else {
                    self.lastOperationFailed = true
                    self.markOCRStatusFromCurrentConfiguration(asError: true, message: error.localizedDescription)
                    if self.shouldOpenSettings(for: error) {
                        self.openSettingsWindow()
                    }
                    logger.error("OCR error: \(error.localizedDescription)")
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
        systemSettingsOpener.openApplicationSettings()
    }

    private func markGrammarStatusFromCurrentConfiguration(asError: Bool, message: String?) {
        let providerID = currentGrammarProviderID()

        if asError {
            grammarStatus = .error(providerID: providerID, message: message ?? "Error")
        } else {
            grammarStatus = .ok(providerID: providerID)
        }
    }

    private func markOCRStatusFromCurrentConfiguration(asError: Bool, message: String?) {
        let providerID = currentScreenshotProviderID()

        if asError {
            ocrStatus = .error(providerID: providerID, message: message ?? "Error")
        } else {
            ocrStatus = .ok(providerID: providerID)
        }
    }

    private func currentGrammarProviderID() -> LLMProviderID {
        settingsStore.loadSettings().grammarProviderID
    }

    private func currentScreenshotProviderID() -> LLMProviderID {
        settingsStore.loadSettings().screenshotProviderID
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
        let clipboardHistorySettings = settingsStore.clipboardHistorySettings()
        clipboardHistoryStore.updateMaxStoredRecords(clipboardHistorySettings.maxStoredRecords)

        if clipboardHistorySettings.isEnabled {
            clipboardMonitor.start()
        } else {
            clipboardMonitor.stop()
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
        guard shortcutAvailabilityChecker.isShortcutAvailable(key: shortcut.key, modifiers: shortcut.modifiers) else {
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
