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

    struct ProviderMenuStatus: Identifiable, Equatable {
        let providerID: LLMProviderID
        let title: String

        var id: String { providerID.id }
    }

    private enum FeatureKind: CaseIterable {
        case refine
        case capture
        case dictate

        var statusPrefix: String {
            switch self {
            case .refine:
                return "Refine"
            case .capture:
                return "Capture"
            case .dictate:
                return "Dictate"
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
        static let needsSetupMessage = "Needs setup in Preferences"
    }

    private static let readyStatusIconImage = StatusBarIcon.readyImage()
    private static let readyFallbackImage = StatusBarIcon.symbolImage(named: StatusSymbolName.readyFallback)
    private static let processingImage = StatusBarIcon.symbolImage(named: StatusSymbolName.processing)
    private static let errorImage = StatusBarIcon.symbolImage(named: StatusSymbolName.error)

    let settingsStore: any AppSettingsProviding
    let clipboardHistoryStore: ClipboardHistoryStore

    @Published private(set) var activityStatus: ActivityStatus = .ready
    @Published private(set) var refineStatus: ProviderStatus = .error(providerID: nil, message: "Not checked")
    @Published private(set) var captureStatus: ProviderStatus = .error(providerID: nil, message: "Not checked")
    @Published private(set) var dictateStatus: ProviderStatus = .error(providerID: nil, message: "Not checked")
    @Published private(set) var accessibilityPermissionGranted = false
    @Published private(set) var microphonePermissionGranted = false
    @Published private(set) var screenRecordingPermissionGranted = false
    @Published private(set) var shortcutRegistrationMessage: String?
    @Published private(set) var launchAtLoginStatus: LaunchAtLoginStatus = .notRegistered
    @Published private(set) var isUpdatingLaunchAtLogin = false
    @Published private(set) var launchAtLoginMessage: String?
    @Published private(set) var shouldShowOpenLoginItemsAction = false

    private let clipboardMonitor: any ClipboardMonitoring
    private let llmRouter: any LLMRouting
    private let refineCoordinator: any RefineCoordinating
    private let captureCoordinator: any CaptureCoordinating
    private let dictateCoordinator: any DictateCoordinating
    private let appSystemServices: AppSystemServices

    private var refineHotKey: HotKey?
    private var captureHotKey: HotKey?
    private var dictateHotKey: HotKey?
    private var dictateMouseButtonMonitor: (any MouseButtonShortcutMonitoring)?
    private var hasStarted = false
    private var initialHealthCheckTask: Task<Void, Never>?
    private var settingsHealthDebounceTask: Task<Void, Never>?
    private var refineHealthCheckTask: Task<Void, Never>?
    private var captureHealthCheckTask: Task<Void, Never>?
    private var dictateHealthCheckTask: Task<Void, Never>?
    private var fixedShortcutRegistrationMessage: String?
    private var dictateShortcutRegistrationMessage: String?

    private var isProcessing = false
    private var isScreenSelectionActive = false
    private var lastOperationFailed = false
    private var activeFeature: FeatureKind?
    private var dictateWorkflowState: DictateWorkflowState = .idle
    private var activeDictateHotKey = AppHotKey.defaultVoiceDictation

    init(
        settingsStore: any AppSettingsProviding,
        clipboardHistoryStore: ClipboardHistoryStore,
        clipboardMonitor: any ClipboardMonitoring,
        llmRouter: any LLMRouting,
        refineCoordinator: any RefineCoordinating,
        captureCoordinator: any CaptureCoordinating,
        dictateCoordinator: any DictateCoordinating,
        appSystemServices: AppSystemServices
    ) {
        self.settingsStore = settingsStore
        self.clipboardHistoryStore = clipboardHistoryStore
        self.clipboardMonitor = clipboardMonitor
        self.llmRouter = llmRouter
        self.refineCoordinator = refineCoordinator
        self.captureCoordinator = captureCoordinator
        self.dictateCoordinator = dictateCoordinator
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
            if dictateWorkflowState == .recording {
                return "Status: Listening..."
            }
            if dictateWorkflowState == .transcribing {
                return "Status: Transcribing..."
            }
            return "Status: Processing..."
        case .error:
            if lastOperationFailed {
                return "Status: Last operation failed"
            }
            return "Status: Provider configuration required"
        }
    }

    var shouldShowActivityStatusTitle: Bool {
        switch activityStatus {
        case .ready:
            return false
        case .processing, .error:
            return true
        }
    }

    var providerMenuStatuses: [ProviderMenuStatus] {
        LLMProviderID.allCases.compactMap { providerID in
            guard let title = providerMenuStatusTitle(for: providerID) else {
                return nil
            }

            return ProviderMenuStatus(providerID: providerID, title: title)
        }
    }

    var refineStatusTitle: String {
        featureStatusTitle(prefix: FeatureKind.refine.statusPrefix, status: refineStatus)
    }

    var captureStatusTitle: String {
        featureStatusTitle(prefix: FeatureKind.capture.statusPrefix, status: captureStatus)
    }

    var dictateStatusTitle: String {
        featureStatusTitle(prefix: FeatureKind.dictate.statusPrefix, status: dictateStatus)
    }

    var accessibilityStatusTitle: String {
        accessibilityPermissionGranted ? "Accessibility: Granted" : "Accessibility: Open Privacy Settings"
    }

    var microphoneStatusTitle: String {
        microphonePermissionGranted ? "Microphone: Granted" : "Microphone: Open Privacy Settings"
    }

    var screenRecordingStatusTitle: String {
        screenRecordingPermissionGranted ? "Screen Recording: Granted" : "Screen Recording: Open Privacy Settings"
    }

    var shouldShowPermissionActions: Bool {
        !accessibilityPermissionGranted || !microphonePermissionGranted || !screenRecordingPermissionGranted
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

        captureCoordinator.onSelectionActivityChanged = { [weak self] isActive in
            Task { @MainActor in
                guard let self else {
                    return
                }

                self.isScreenSelectionActive = isActive
                self.refreshStatusUI()
            }
        }

        dictateCoordinator.onStateChanged = { [weak self] state in
            Task { @MainActor in
                self?.handleDictateWorkflowStateChanged(state)
            }
        }

        dictateCoordinator.onError = { [weak self] error in
            Task { @MainActor in
                self?.handleCoordinatorError(for: .dictate, error: error)
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

            self.checkRefineProviderStatus()
            self.checkCaptureProviderStatus()
            self.checkDictateProviderStatus()
        }
    }

    func runRefineAction() {
        handleHotKeyPress(for: .refine)
    }

    func runCaptureAction() {
        handleHotKeyPress(for: .capture)
    }

    func runDictateAction() {
        handleHotKeyPress(for: .dictate)
    }

    func checkRefineProviderStatus() {
        checkProviderStatus(for: .refine)
    }

    func checkCaptureProviderStatus() {
        checkProviderStatus(for: .capture)
    }

    func checkDictateProviderStatus() {
        checkProviderStatus(for: .dictate)
    }

    func checkProviderStatus(for providerID: LLMProviderID) {
        for feature in features(using: providerID) {
            checkProviderStatus(for: feature)
        }
    }

    func validateDictateHotKey(_ hotKey: AppHotKey) -> AppHotKeyValidationError? {
        AppHotKeyValidator.validateDictateHotKey(
            hotKey,
            isShortcutAvailable: appSystemServices.isShortcutAvailable
        )
    }

    func settingsDidChange() {
        applyClipboardHistorySettings()
        registerDictateHotKey(using: settingsStore.loadSettings().voice.hotKey)
        initialHealthCheckTask?.cancel()
        settingsHealthDebounceTask?.cancel()
        settingsHealthDebounceTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self, !Task.isCancelled else {
                return
            }

            self.checkRefineProviderStatus()
            self.checkCaptureProviderStatus()
            self.checkDictateProviderStatus()
        }
    }

    func refreshPermissionStatuses() {
        accessibilityPermissionGranted = appSystemServices.isAccessibilityPermissionGranted()
        microphonePermissionGranted = appSystemServices.isMicrophonePermissionGranted()
        screenRecordingPermissionGranted = appSystemServices.isScreenRecordingPermissionGranted()
    }

    func openAccessibilityPrivacySettings() {
        appSystemServices.openAccessibilityPrivacySettings()
    }

    func openMicrophonePrivacySettings() {
        appSystemServices.openMicrophonePrivacySettings()
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
        let refineShortcut = AppShortcut(
            title: "Refine",
            key: .f,
            modifiers: [.command, .shift],
            displayValue: AppHotKey.refine.readableDisplayValue
        )
        let captureShortcut = AppShortcut(
            title: "Capture",
            key: .r,
            modifiers: [.command, .shift],
            displayValue: AppHotKey.screenTextCapture.readableDisplayValue
        )

        var unavailableShortcuts: [AppShortcut] = []

        if let hotKey = makeHotKey(
            for: refineShortcut,
            action: { [weak self] in
                self?.handleHotKeyPress(for: .refine)
            })
        {
            refineHotKey = hotKey
        } else {
            unavailableShortcuts.append(refineShortcut)
        }

        if let hotKey = makeHotKey(
            for: captureShortcut,
            action: { [weak self] in
                self?.handleHotKeyPress(for: .capture)
            })
        {
            captureHotKey = hotKey
        } else {
            unavailableShortcuts.append(captureShortcut)
        }

        fixedShortcutRegistrationMessage = shortcutConflictMessage(for: unavailableShortcuts)
        registerDictateHotKey(using: settingsStore.loadSettings().voice.hotKey)
    }

    private func checkProviderStatus(for feature: FeatureKind) {
        guard let selection = modelSelection(for: feature) else {
            setStatus(.error(providerID: nil, message: StatusSymbolName.needsSetupMessage), for: feature)
            refreshStatusUI()
            return
        }

        let providerID = selection.providerID
        setStatus(.processing(providerID: providerID), for: feature)
        refreshStatusUI()

        healthCheckTask(for: feature)?.cancel()
        setHealthCheckTask(
            Task { @MainActor [weak self] in
                guard let self else {
                    return
                }

                do {
                    let health = try await self.llmRouter.checkAccess(for: selection)
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
        guard canRun(feature: feature) else {
            return
        }

        lastOperationFailed = false
        isProcessing = true
        activeFeature = feature

        setStatus(.processing(providerID: modelSelection(for: feature)?.providerID), for: feature)
        refreshStatusUI()

        Task {
            do {
                try await performOperation(for: feature)
                if feature != .dictate || self.dictateWorkflowState == .idle {
                    self.lastOperationFailed = false
                    self.activeFeature = nil
                    self.markStatusFromCurrentConfiguration(for: feature, asError: false, message: nil)
                }
            } catch {
                if feature == .dictate && self.dictateWorkflowState != .idle {
                    return
                }

                self.handleCoordinatorError(for: feature, error: error)
            }

            if feature != .dictate || self.dictateWorkflowState == .idle {
                self.isProcessing = false
            }
            self.refreshStatusUI()
        }
    }

    private func markStatusFromCurrentConfiguration(for feature: FeatureKind, asError: Bool, message: String?) {
        let status: ProviderStatus
        if asError {
            status = .error(providerID: modelSelection(for: feature)?.providerID, message: message ?? "Error")
        } else if let providerID = modelSelection(for: feature)?.providerID {
            status = .ok(providerID: providerID)
        } else {
            status = .error(providerID: nil, message: StatusSymbolName.needsSetupMessage)
        }
        setStatus(status, for: feature)
    }

    private func modelSelection(for feature: FeatureKind) -> LLMModelSelection? {
        switch feature {
        case .refine:
            return settingsStore.loadSettings().refine.selectedModel
        case .capture:
            return settingsStore.loadSettings().screenText.selectedModel
        case .dictate:
            return settingsStore.loadSettings().voice.selectedModel
        }
    }

    private func setStatus(_ status: ProviderStatus, for feature: FeatureKind) {
        switch feature {
        case .refine:
            refineStatus = status
        case .capture:
            captureStatus = status
        case .dictate:
            dictateStatus = status
        }
    }

    private func status(for feature: FeatureKind) -> ProviderStatus {
        switch feature {
        case .refine:
            return refineStatus
        case .capture:
            return captureStatus
        case .dictate:
            return dictateStatus
        }
    }

    private func healthCheckTask(for feature: FeatureKind) -> Task<Void, Never>? {
        switch feature {
        case .refine:
            return refineHealthCheckTask
        case .capture:
            return captureHealthCheckTask
        case .dictate:
            return dictateHealthCheckTask
        }
    }

    private func setHealthCheckTask(_ task: Task<Void, Never>, for feature: FeatureKind) {
        switch feature {
        case .refine:
            refineHealthCheckTask = task
        case .capture:
            captureHealthCheckTask = task
        case .dictate:
            dictateHealthCheckTask = task
        }
    }

    private func performOperation(for feature: FeatureKind) async throws {
        switch feature {
        case .refine:
            try await refineCoordinator.handleHotKeyPress()
        case .capture:
            try await captureCoordinator.handleHotKeyPress()
        case .dictate:
            try await dictateCoordinator.handleManualToggleAction()
        }
    }

    private func shouldIgnoreFailure(for feature: FeatureKind, error: Error) -> Bool {
        switch feature {
        case .refine:
            if case RefineCoordinatorError.noSelectedText = error {
                return true
            }
        case .capture:
            if case CaptureCoordinatorError.cancelled = error {
                return true
            }
        case .dictate:
            break
        }

        return false
    }

    private func refreshStatusUI() {
        if isScreenSelectionActive || isProcessing || dictateWorkflowState != .idle {
            activityStatus = .processing
            return
        }

        if lastOperationFailed || hasErrorStatus(refineStatus) || hasErrorStatus(captureStatus)
            || hasErrorStatus(dictateStatus)
        {
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

    private func isProcessingStatus(_ status: ProviderStatus) -> Bool {
        if case .processing = status {
            return true
        }

        return false
    }

    private func errorMessage(from status: ProviderStatus) -> String? {
        if case .error(_, let message) = status {
            return message
        }

        return nil
    }

    private func features(using providerID: LLMProviderID) -> [FeatureKind] {
        FeatureKind.allCases.filter { modelSelection(for: $0)?.providerID == providerID }
    }

    private func canRun(feature: FeatureKind) -> Bool {
        activeFeature == nil || (feature == .dictate && activeFeature == .dictate)
    }

    private func handleDictateWorkflowStateChanged(_ state: DictateWorkflowState) {
        dictateWorkflowState = state

        switch state {
        case .idle:
            activeFeature = nil
            isProcessing = false

            if case .processing = dictateStatus {
                markStatusFromCurrentConfiguration(for: .dictate, asError: false, message: nil)
            }
        case .recording, .transcribing:
            activeFeature = .dictate
            isProcessing = true
            setStatus(.processing(providerID: modelSelection(for: .dictate)?.providerID), for: .dictate)
        }

        refreshStatusUI()
    }

    private func handleCoordinatorError(for feature: FeatureKind, error: Error) {
        if feature == .dictate {
            dictateWorkflowState = .idle
        }

        activeFeature = nil
        isProcessing = false

        if shouldIgnoreFailure(for: feature, error: error) {
            lastOperationFailed = false
            markStatusFromCurrentConfiguration(for: feature, asError: false, message: nil)
        } else {
            lastOperationFailed = true
            markStatusFromCurrentConfiguration(for: feature, asError: true, message: error.localizedDescription)

            logger.error("\(feature.logLabel) error: \(error.localizedDescription)")
        }

        refreshStatusUI()
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

    private func featureStatusTitle(prefix: String, status: ProviderStatus) -> String {
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

    private func providerMenuStatusTitle(for providerID: LLMProviderID) -> String? {
        let statuses = features(using: providerID).map(status(for:))
        guard !statuses.isEmpty else {
            return nil
        }

        if statuses.contains(where: isProcessingStatus) {
            return "\(providerID.displayName): Checking..."
        }

        if let message = statuses.compactMap(errorMessage(from:)).first {
            return "\(providerID.displayName): \(message)"
        }

        return "\(providerID.displayName): Ready"
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
            return StatusSymbolName.needsSetupMessage
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

    private func registerDictateHotKey(using requestedHotKey: AppHotKey) {
        if let validationError = AppHotKeyValidator.validateDictateHotKey(
            requestedHotKey,
            isShortcutAvailable: appSystemServices.isShortcutAvailable
        ) {
            dictateShortcutRegistrationMessage = dictateShortcutMessage(for: requestedHotKey, error: validationError)
            refreshShortcutRegistrationMessage()
            return
        }

        guard requestedHotKey != activeDictateHotKey || !hasRegisteredDictateShortcut(for: requestedHotKey) else {
            dictateShortcutRegistrationMessage = nil
            refreshShortcutRegistrationMessage()
            return
        }

        if requestedHotKey.isMouseButton {
            let mouseButtonMonitor = appSystemServices.makeMouseButtonMonitor(
                requestedHotKey.mouseButtonNumber,
                requestedHotKey.modifiers,
                { [weak self] in
                    Task { @MainActor [weak self] in
                        do {
                            try await self?.dictateCoordinator.handlePushToTalkKeyDown()
                        } catch {
                            self?.handleCoordinatorError(for: .dictate, error: error)
                        }
                    }
                },
                { [weak self] in
                    Task { @MainActor [weak self] in
                        do {
                            try await self?.dictateCoordinator.handlePushToTalkKeyUp()
                        } catch {
                            self?.handleCoordinatorError(for: .dictate, error: error)
                        }
                    }
                }
            )

            dictateHotKey = nil
            dictateMouseButtonMonitor?.stop()
            dictateMouseButtonMonitor = mouseButtonMonitor
            activeDictateHotKey = requestedHotKey
            dictateShortcutRegistrationMessage = nil
            refreshShortcutRegistrationMessage()
            return
        }

        let dictateShortcut = AppShortcut(
            title: "Dictate",
            key: requestedHotKey.key ?? .d,
            modifiers: requestedHotKey.modifiers,
            displayValue: requestedHotKey.readableDisplayValue
        )

        guard
            let hotKey = makeHotKey(
                for: dictateShortcut,
                action: { [weak self] in
                    Task { @MainActor [weak self] in
                        do {
                            try await self?.dictateCoordinator.handlePushToTalkKeyDown()
                        } catch {
                            self?.handleCoordinatorError(for: .dictate, error: error)
                        }
                    }
                },
                keyUpAction: { [weak self] in
                    Task { @MainActor [weak self] in
                        do {
                            try await self?.dictateCoordinator.handlePushToTalkKeyUp()
                        } catch {
                            self?.handleCoordinatorError(for: .dictate, error: error)
                        }
                    }
                })
        else {
            dictateShortcutRegistrationMessage = dictateShortcutMessage(for: requestedHotKey, error: .unavailable)
            refreshShortcutRegistrationMessage()
            return
        }

        dictateMouseButtonMonitor?.stop()
        dictateMouseButtonMonitor = nil
        dictateHotKey = hotKey
        activeDictateHotKey = requestedHotKey
        dictateShortcutRegistrationMessage = nil
        refreshShortcutRegistrationMessage()
    }

    private func hasRegisteredDictateShortcut(for hotKey: AppHotKey) -> Bool {
        if hotKey.isMouseButton {
            return dictateMouseButtonMonitor != nil
        }

        return dictateHotKey != nil
    }

    private func dictateShortcutMessage(for hotKey: AppHotKey, error: AppHotKeyValidationError) -> String {
        switch error {
        case .conflictsWithFeature(let featureName):
            return "Shortcut unavailable: Dictate (\(hotKey.readableDisplayValue)) conflicts with \(featureName)."
        case .unavailable:
            return "Shortcut unavailable: Dictate (\(hotKey.readableDisplayValue)) is already in use by another app."
        case .requiresModifier, .requiresNonModifierKey, .requiresMouseButton:
            return error.localizedDescription
        }
    }

    private func refreshShortcutRegistrationMessage() {
        let messages = [fixedShortcutRegistrationMessage, dictateShortcutRegistrationMessage].compactMap { $0 }
        shortcutRegistrationMessage = messages.isEmpty ? nil : messages.joined(separator: "\n")
    }

    private func makeHotKey(
        for shortcut: AppShortcut,
        action: @escaping @MainActor () -> Void,
        keyUpAction: (@MainActor () -> Void)? = nil
    ) -> HotKey? {
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
        hotKey.keyUpHandler = {
            guard let keyUpAction else {
                return
            }

            Task { @MainActor in
                keyUpAction()
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
