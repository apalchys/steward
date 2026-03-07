import AppKit
import Foundation
import HotKey
import OSLog
import SwiftUI

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.steward", category: "app")

@MainActor
final class AppState: ObservableObject {
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

    private lazy var clipboardMonitor = ClipboardMonitor { [weak self] record in
        self?.clipboardHistoryStore.append(record)
    }
    private lazy var textInteractionService = SystemTextInteractionService(suppression: clipboardMonitor)
    private let screenCaptureService = SystemScreenCaptureService()
    private let selectionOverlayController = ScreenSelectionOverlayController()

    private lazy var llmRouter = LLMRouter(
        providers: [
            OpenAILLMProvider(),
            GeminiLLMProvider(),
        ],
        settingsStore: settingsStore
    )

    private lazy var grammarCoordinator = GrammarCoordinator(
        router: llmRouter,
        textInteraction: textInteractionService,
        settingsStore: settingsStore
    )

    private lazy var screenOCRCoordinator = ScreenOCRCoordinator(
        router: llmRouter,
        textInteraction: textInteractionService,
        captureService: screenCaptureService,
        selectionPresenter: selectionOverlayController,
        settingsStore: settingsStore
    )

    private var grammarHotKey: HotKey?
    private var screenOCRHotKey: HotKey?
    private var hasStarted = false

    private var isProcessing = false
    private var isScreenSelectionActive = false
    private var lastOperationFailed = false

    init(
        settingsStore: any LLMSettingsProviding & ClipboardHistorySettingsProviding = UserDefaultsLLMSettingsStore(),
        clipboardHistoryStore: ClipboardHistoryStore = ClipboardHistoryStore()
    ) {
        self.settingsStore = settingsStore
        self.clipboardHistoryStore = clipboardHistoryStore

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

    func start() {
        guard !hasStarted else {
            return
        }
        hasStarted = true

        settingsStore.migrateLegacySettingsIfNeeded()
        NSApp.setActivationPolicy(.accessory)

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

        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard let self else {
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

        Task {
            do {
                let health = try await llmRouter.checkAccess(for: providerID)
                self.grammarStatus =
                    health.hasAccess
                    ? .ok(providerID: health.providerID)
                    : .error(providerID: health.providerID, message: "Access check failed")
            } catch {
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

        Task {
            do {
                let health = try await llmRouter.checkAccess(for: providerID)
                self.ocrStatus =
                    health.hasAccess
                    ? .ok(providerID: health.providerID)
                    : .error(providerID: health.providerID, message: "Access check failed")
            } catch {
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
        checkGrammarProviderStatus()
        checkOCRProviderStatus()
    }

    func openPreferences() {
        openSettingsWindow()
    }

    private func setupHotKeys() {
        grammarHotKey = HotKey(key: .f, modifiers: [.command, .shift])
        grammarHotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.handleGrammarHotKeyPress()
            }
        }

        screenOCRHotKey = HotKey(key: .r, modifiers: [.command, .shift])
        screenOCRHotKey?.keyDownHandler = { [weak self] in
            Task { @MainActor in
                self?.handleScreenOCRHotKeyPress()
            }
        }
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
        NSApp.activate(ignoringOtherApps: true)
        _ = NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
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
            return "\(prefix): \(providerID.displayName) OK"
        case .processing(let providerID):
            if let providerID {
                return "\(prefix): \(providerID.displayName) Checking..."
            }

            return "\(prefix): Checking..."
        case .error(let providerID, let message):
            if let providerID {
                return "\(prefix): \(providerID.displayName) Error - Click to retry"
            }

            return "\(prefix): \(message)"
        }
    }
}
