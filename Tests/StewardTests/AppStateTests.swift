import AppKit
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
        let appState = AppState(
            settingsStore: settingsStore,
            clipboardHistoryStore: clipboardHistoryStore,
            clipboardMonitor: clipboardMonitor,
            llmRouter: router,
            grammarCoordinator: grammarCoordinator,
            screenOCRCoordinator: screenOCRCoordinator
        )

        appState.start()
        appState.start()
        await Task.yield()

        XCTAssertEqual(clipboardMonitor.startCallCount, 1)
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
    let supportedProviderIDs: [LLMProviderID] = [.openAI, .gemini]

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

private final class FakeAppSettingsStore: LLMSettingsProviding, ClipboardHistorySettingsProviding {
    private var settings = LLMSettings.empty()
    private var historySettings = ClipboardHistorySettings()

    init(historySettings: ClipboardHistorySettings = ClipboardHistorySettings()) {
        self.historySettings = historySettings
    }

    func loadSettings() -> LLMSettings {
        settings
    }

    func saveSettings(_ settings: LLMSettings) {
        self.settings = settings
    }

    func migrateLegacySettingsIfNeeded() {}

    func customGrammarInstructions() -> String { "" }

    func setCustomGrammarInstructions(_ value: String) {}

    func customScreenshotInstructions() -> String { "" }

    func setCustomScreenshotInstructions(_ value: String) {}

    func clipboardHistorySettings() -> ClipboardHistorySettings {
        historySettings
    }

    func setClipboardHistorySettings(_ settings: ClipboardHistorySettings) {
        historySettings = settings
    }
}
