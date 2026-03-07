import AppKit
import Foundation
import HotKey

extension Notification.Name {
    static let checkGrammarProviderStatus = Notification.Name("checkGrammarProviderStatus")
    static let checkOCRProviderStatus = Notification.Name("checkOCRProviderStatus")
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private enum MenuItemTag {
        static let activityStatus = 1
        static let grammarProviderStatus = 2
        static let ocrProviderStatus = 3
    }

    private enum StatusIcon {
        static let ready = NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: "Steward")
        static let error = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "Error")
        static let processing = NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Processing")
    }

    private var statusItem: NSStatusItem!
    private let settingsStore = UserDefaultsLLMSettingsStore()
    private let clipboardHistoryStore = ClipboardHistoryStore()
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
            OpenAICompatibleLLMProvider(),
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

    private lazy var historyCoordinator = HistoryCoordinator(store: clipboardHistoryStore)
    private let preferencesCoordinator = PreferencesCoordinator()

    private var grammarHotKey: HotKey?
    private var screenOCRHotKey: HotKey?

    private var isProcessing = false
    private var isScreenSelectionActive = false
    private var lastOperationFailed = false
    private var activityStatus: ActivityStatus = .ready
    private var grammarStatus: ProviderStatus = .error(providerID: nil, message: "Not checked")
    private var ocrStatus: ProviderStatus = .error(providerID: nil, message: "Not checked")

    func applicationDidFinishLaunching(_ notification: Notification) {
        settingsStore.migrateLegacySettingsIfNeeded()

        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon()

        setupMenu()
        setupHotKeys()
        clipboardMonitor.start()

        screenOCRCoordinator.onSelectionActivityChanged = { [weak self] isActive in
            guard let self else {
                return
            }

            self.isScreenSelectionActive = isActive
            self.refreshStatusUI()
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkGrammarProviderStatus),
            name: .checkGrammarProviderStatus,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkOCRProviderStatus),
            name: .checkOCRProviderStatus,
            object: nil
        )

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.checkGrammarProviderStatus()
            self?.checkOCRProviderStatus()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        clipboardMonitor.stop()
    }

    private func setupMenu() {
        let menu = NSMenu()

        menu.addItem(NSMenuItem(title: "Grammar Check (⌘⇧F)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Screen Text Capture (⌘⇧R)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())

        let activityStatusItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        activityStatusItem.tag = MenuItemTag.activityStatus
        menu.addItem(activityStatusItem)

        let grammarStatusItem = NSMenuItem(title: "Grammar: Checking...", action: #selector(checkGrammarProviderStatus), keyEquivalent: "")
        grammarStatusItem.target = self
        grammarStatusItem.tag = MenuItemTag.grammarProviderStatus
        menu.addItem(grammarStatusItem)

        let ocrStatusItem = NSMenuItem(title: "OCR: Checking...", action: #selector(checkOCRProviderStatus), keyEquivalent: "")
        ocrStatusItem.target = self
        ocrStatusItem.tag = MenuItemTag.ocrProviderStatus
        menu.addItem(ocrStatusItem)

        menu.addItem(NSMenuItem.separator())

        let historyMenuItem = NSMenuItem(title: "History", action: #selector(openHistory), keyEquivalent: "")
        historyMenuItem.target = self
        menu.addItem(historyMenuItem)

        let preferencesMenuItem = NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ",")
        preferencesMenuItem.target = self
        menu.addItem(preferencesMenuItem)

        menu.addItem(NSMenuItem.separator())

        let quitMenuItem = NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q")
        quitMenuItem.target = self
        menu.addItem(quitMenuItem)

        statusItem.menu = menu

        refreshStatusUI()
        updateGrammarProviderMenuItem()
        updateOCRProviderMenuItem()
    }

    private func setupHotKeys() {
        grammarHotKey = HotKey(key: .f, modifiers: [.command, .shift])
        grammarHotKey?.keyDownHandler = { [weak self] in
            self?.handleGrammarHotKeyPress()
        }

        screenOCRHotKey = HotKey(key: .r, modifiers: [.command, .shift])
        screenOCRHotKey?.keyDownHandler = { [weak self] in
            self?.handleScreenOCRHotKeyPress()
        }
    }

    private func handleGrammarHotKeyPress() {
        guard !isProcessing else {
            return
        }

        lastOperationFailed = false
        isProcessing = true

        let settings = settingsStore.loadSettings()
        grammarStatus = .processing(
            providerID: llmRouter.resolvedProviderID(
                for: .textCorrection,
                featureOverrideProviderID: settings.grammarProviderOverrideID
            )
        )
        refreshStatusUI()
        updateGrammarProviderMenuItem()

        grammarCoordinator.handleHotKeyPress { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.lastOperationFailed = false
                    self.markGrammarStatusFromCurrentConfiguration(asError: false, message: nil)
                case .failure(let error):
                    if case GrammarCoordinatorError.noSelectedText = error {
                        self.lastOperationFailed = false
                    } else {
                        self.lastOperationFailed = true
                        self.markGrammarStatusFromCurrentConfiguration(asError: true, message: error.localizedDescription)
                        if self.shouldOpenPreferences(for: error) {
                            self.preferencesCoordinator.openPreferencesWindow()
                        }
                        print("Grammar error: \(error.localizedDescription)")
                    }
                }

                self.isProcessing = false
                self.refreshStatusUI()
                self.updateGrammarProviderMenuItem()
            }
        }
    }

    private func handleScreenOCRHotKeyPress() {
        guard !isProcessing else {
            return
        }

        lastOperationFailed = false
        isProcessing = true

        let settings = settingsStore.loadSettings()
        ocrStatus = .processing(
            providerID: llmRouter.resolvedProviderID(
                for: .visionOCR,
                featureOverrideProviderID: settings.ocrProviderOverrideID
            )
        )
        refreshStatusUI()
        updateOCRProviderMenuItem()

        screenOCRCoordinator.handleHotKeyPress { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch result {
                case .success:
                    self.lastOperationFailed = false
                    self.markOCRStatusFromCurrentConfiguration(asError: false, message: nil)
                case .failure(let error):
                    if case ScreenOCRCoordinatorError.cancelled = error {
                        self.lastOperationFailed = false
                    } else {
                        self.lastOperationFailed = true
                        self.markOCRStatusFromCurrentConfiguration(asError: true, message: error.localizedDescription)
                        if self.shouldOpenPreferences(for: error) {
                            self.preferencesCoordinator.openPreferencesWindow()
                        }
                        print("OCR error: \(error.localizedDescription)")
                    }
                }

                self.isProcessing = false
                self.refreshStatusUI()
                self.updateOCRProviderMenuItem()
            }
        }
    }

    @objc private func checkGrammarProviderStatus() {
        let settings = settingsStore.loadSettings()
        grammarStatus = .processing(
            providerID: llmRouter.resolvedProviderID(
                for: .textCorrection,
                featureOverrideProviderID: settings.grammarProviderOverrideID
            )
        )
        refreshStatusUI()
        updateGrammarProviderMenuItem()

        llmRouter.checkAccess(
            for: .textCorrection,
            featureOverrideProviderID: settings.grammarProviderOverrideID
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch result {
                case .success(let health):
                    self.grammarStatus = health.hasAccess
                        ? .ok(providerID: health.providerID)
                        : .error(providerID: health.providerID, message: "Access check failed")
                case .failure(let error):
                    self.grammarStatus = .error(
                        providerID: self.llmRouter.resolvedProviderID(
                            for: .textCorrection,
                            featureOverrideProviderID: settings.grammarProviderOverrideID
                        ),
                        message: error.localizedDescription
                    )
                }

                self.refreshStatusUI()
                self.updateGrammarProviderMenuItem()
            }
        }
    }

    @objc private func checkOCRProviderStatus() {
        let settings = settingsStore.loadSettings()
        ocrStatus = .processing(
            providerID: llmRouter.resolvedProviderID(
                for: .visionOCR,
                featureOverrideProviderID: settings.ocrProviderOverrideID
            )
        )
        refreshStatusUI()
        updateOCRProviderMenuItem()

        llmRouter.checkAccess(
            for: .visionOCR,
            featureOverrideProviderID: settings.ocrProviderOverrideID
        ) { [weak self] result in
            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                switch result {
                case .success(let health):
                    self.ocrStatus = health.hasAccess
                        ? .ok(providerID: health.providerID)
                        : .error(providerID: health.providerID, message: "Access check failed")
                case .failure(let error):
                    self.ocrStatus = .error(
                        providerID: self.llmRouter.resolvedProviderID(
                            for: .visionOCR,
                            featureOverrideProviderID: settings.ocrProviderOverrideID
                        ),
                        message: error.localizedDescription
                    )
                }

                self.refreshStatusUI()
                self.updateOCRProviderMenuItem()
            }
        }
    }

    private func shouldOpenPreferences(for error: Error) -> Bool {
        switch error {
        case is LLMRouterError:
            return true
        default:
            return false
        }
    }

    private func markGrammarStatusFromCurrentConfiguration(asError: Bool, message: String?) {
        let settings = settingsStore.loadSettings()
        let providerID = llmRouter.resolvedProviderID(
            for: .textCorrection,
            featureOverrideProviderID: settings.grammarProviderOverrideID
        )

        if asError {
            grammarStatus = .error(providerID: providerID, message: message ?? "Error")
        } else if let providerID {
            grammarStatus = .ok(providerID: providerID)
        }
    }

    private func markOCRStatusFromCurrentConfiguration(asError: Bool, message: String?) {
        let settings = settingsStore.loadSettings()
        let providerID = llmRouter.resolvedProviderID(
            for: .visionOCR,
            featureOverrideProviderID: settings.ocrProviderOverrideID
        )

        if asError {
            ocrStatus = .error(providerID: providerID, message: message ?? "Error")
        } else if let providerID {
            ocrStatus = .ok(providerID: providerID)
        }
    }

    private func refreshStatusUI() {
        refreshOverallStatus()
        updateStatusItemIcon()
        updateActivityStatusMenuItem()
    }

    private func refreshOverallStatus() {
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

    private func updateStatusItemIcon() {
        guard let button = statusItem.button else {
            return
        }

        switch activityStatus {
        case .ready:
            button.image = StatusIcon.ready
        case .processing:
            button.image = StatusIcon.processing
        case .error:
            button.image = StatusIcon.error
        }
    }

    private func updateActivityStatusMenuItem() {
        guard let menu = statusItem.menu,
            let activityStatusItem = menu.items.first(where: { $0.tag == MenuItemTag.activityStatus })
        else {
            return
        }

        switch activityStatus {
        case .ready:
            activityStatusItem.title = "Status: Ready"
        case .processing:
            if isScreenSelectionActive {
                activityStatusItem.title = "Status: Select an area..."
            } else {
                activityStatusItem.title = "Status: Processing..."
            }
        case .error:
            if lastOperationFailed {
                activityStatusItem.title = "Status: Last operation failed"
            } else {
                activityStatusItem.title = "Status: Provider configuration required"
            }
        }
    }

    private func updateGrammarProviderMenuItem() {
        guard let menu = statusItem.menu,
            let item = menu.items.first(where: { $0.tag == MenuItemTag.grammarProviderStatus })
        else {
            return
        }

        item.title = providerStatusTitle(prefix: "Grammar", status: grammarStatus)
    }

    private func updateOCRProviderMenuItem() {
        guard let menu = statusItem.menu,
            let item = menu.items.first(where: { $0.tag == MenuItemTag.ocrProviderStatus })
        else {
            return
        }

        item.title = providerStatusTitle(prefix: "OCR", status: ocrStatus)
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

    @objc private func openHistory() {
        historyCoordinator.openHistoryWindow()
    }

    @objc private func openPreferences() {
        preferencesCoordinator.openPreferencesWindow()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
