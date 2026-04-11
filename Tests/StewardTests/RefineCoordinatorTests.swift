import Foundation
import XCTest
@testable import Steward

@MainActor
final class RefineCoordinatorTests: XCTestCase {
    func testHandleHotKeyPressSendsRequestThroughRouterAndReplacesTextOnSuccess() async throws {
        let router = FakeRouter(result: .success(.text("corrected")))
        let textInteraction = FakeTextInteraction(selectedText: "bad")
        var settings = LLMSettings.empty()
        settings.providerSettings[.openAI] = LLMProviderSettings(apiKey: "key")
        settings.refine = RefineSettings(
            selectedModel: LLMModelSelection(providerID: .openAI, modelID: "gpt-5.4"),
            customInstructions: "Use concise language"
        )
        let settingsStore = CoordinatorSettingsStore(settings: settings)

        let coordinator = RefineCoordinator(router: router, textInteraction: textInteraction, settingsStore: settingsStore)

        try await coordinator.handleHotKeyPress()

        XCTAssertEqual(textInteraction.replacedText, "corrected")
        guard let request = router.lastRequest else {
            XCTFail("Expected request to be routed")
            return
        }

        guard case let .refineText(text, customInstructions) = request.task else {
            XCTFail("Expected refine task")
            return
        }

        XCTAssertEqual(request.selection, LLMModelSelection(providerID: .openAI, modelID: "gpt-5.4"))
        XCTAssertEqual(text, "bad")
        XCTAssertEqual(customInstructions, "Use concise language")
    }

    func testHandleHotKeyPressFailsWhenNoSelectedText() async {
        let router = FakeRouter(result: .success(.text("ignored")))
        let textInteraction = FakeTextInteraction(selectedText: nil)
        let settingsStore = CoordinatorSettingsStore(settings: .empty())

        let coordinator = RefineCoordinator(router: router, textInteraction: textInteraction, settingsStore: settingsStore)

        do {
            try await coordinator.handleHotKeyPress()
            XCTFail("Expected failure")
        } catch {
            guard case RefineCoordinatorError.noSelectedText = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertNil(router.lastRequest)
            XCTAssertNil(textInteraction.replacedText)
        }
    }

    func testHandleHotKeyPressPropagatesRouterError() async {
        enum TestError: Error {
            case failed
        }

        let router = FakeRouter(result: .failure(TestError.failed))
        let textInteraction = FakeTextInteraction(selectedText: "bad")
        var settings = LLMSettings.empty()
        settings.refine.selectedModel = LLMModelSelection(providerID: .openAI, modelID: "gpt-5.4")
        let settingsStore = CoordinatorSettingsStore(settings: settings)

        let coordinator = RefineCoordinator(router: router, textInteraction: textInteraction, settingsStore: settingsStore)

        do {
            try await coordinator.handleHotKeyPress()
            XCTFail("Expected failure")
        } catch {
            guard case TestError.failed = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertNil(textInteraction.replacedText)
        }
    }
}

@MainActor
private final class FakeRouter: LLMRouting {
    var lastRequest: LLMRequest?
    let result: Result<LLMResult, Error>

    init(result: Result<LLMResult, Error>) {
        self.result = result
    }

    func perform(_ request: LLMRequest) async throws -> LLMResult {
        lastRequest = request
        return try result.get()
    }

    func checkAccess(for selection: LLMModelSelection) async throws -> LLMProviderHealth {
        LLMProviderHealth(providerID: selection.providerID, state: .available, message: "Ready")
    }
}

private final class FakeTextInteraction: TextInteractionPerforming, @unchecked Sendable {
    var selectedText: String?
    var replacedText: String?
    var copiedText: String?

    init(selectedText: String?) {
        self.selectedText = selectedText
    }

    func getSelectedText() async throws -> String? {
        selectedText
    }

    func replaceSelectedText(with newText: String) async throws {
        replacedText = newText
    }

    func copyTextToClipboard(_ text: String) {
        copiedText = text
    }
}

final class CoordinatorSettingsStore: AppSettingsProviding {
    var settings: LLMSettings

    init(settings: LLMSettings) {
        self.settings = settings
    }

    func loadSettings() -> LLMSettings { settings }

    func saveSettings(_ settings: LLMSettings) {
        self.settings = settings
    }
}
