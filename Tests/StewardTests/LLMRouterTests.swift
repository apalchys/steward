import Foundation
import XCTest
@testable import Steward

@MainActor
final class LLMRouterTests: XCTestCase {
    func testPerformUsesRequestedProviderForGrammar() async throws {
        let callTracker = CallTracker()
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: [.openAI, .gemini]))
        let router = makeRouter(
            settingsStore: settingsStore,
            providers: [
                FakeProvider(
                    id: .openAI,
                    capabilities: [.textCorrection],
                    performHandler: { task, configuration in
                        callTracker.calledOpenAI = true
                        guard case let .grammarCorrection(text, _) = task else {
                            XCTFail("Expected grammar task")
                            throw FakeProviderError.unexpectedTask
                        }
                        XCTAssertEqual(text, "text")
                        XCTAssertEqual(configuration.apiKey, "key-openAI")
                        return .text("ok")
                    }
                ),
                FakeProvider(
                    id: .gemini,
                    capabilities: [.visionOCR],
                    performHandler: { _, _ in
                        callTracker.calledGemini = true
                        return .text("ignored")
                    }
                ),
            ]
        )

        let response = try await router.perform(
            LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "text", customInstructions: ""))
        )

        XCTAssertEqual(response.textValue, "ok")
        XCTAssertTrue(callTracker.calledOpenAI)
        XCTAssertFalse(callTracker.calledGemini)
    }

    func testPerformFailsWhenProviderIsNotRegistered() async {
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: [.openAI]))
        let router = makeRouter(settingsStore: settingsStore, providers: [])

        do {
            _ = try await router.perform(
                LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "text", customInstructions: ""))
            )
            XCTFail("Expected registration error")
        } catch {
            guard case let LLMRouterError.providerNotRegistered(providerID) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(providerID, .openAI)
        }
    }

    func testPerformFailsWhenProviderIsNotConfigured() async {
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: []))
        let router = makeRouter(settingsStore: settingsStore)

        do {
            _ = try await router.perform(
                LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "text", customInstructions: ""))
            )
            XCTFail("Expected configuration error")
        } catch {
            guard case let LLMRouterError.providerNotConfigured(providerID) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(providerID, .openAI)
        }
    }

    func testPerformFailsWhenRequestedProviderDoesNotSupportCapability() async {
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: [.openAI]))
        let router = makeRouter(
            settingsStore: settingsStore,
            providers: [FakeProvider(id: .openAI, capabilities: [.visionOCR])]
        )

        do {
            _ = try await router.perform(
                LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "text", customInstructions: ""))
            )
            XCTFail("Expected capability error")
        } catch {
            guard case let LLMRouterError.providerDoesNotSupportCapability(providerID, capability) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(providerID, .openAI)
            XCTAssertEqual(capability, .textCorrection)
        }
    }

    func testCheckAccessReturnsRequestedProviderHealth() async throws {
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: [.openAI, .gemini]))
        let router = makeRouter(
            settingsStore: settingsStore,
            providers: [
                FakeProvider(
                    id: .openAI,
                    capabilities: [.textCorrection],
                    checkAccessResult: LLMProviderHealth(
                        providerID: .openAI,
                        state: .available,
                        message: "Ready"
                    )
                )
            ]
        )

        let health = try await router.checkAccess(for: .openAI)

        XCTAssertEqual(health.providerID, .openAI)
        XCTAssertEqual(health.state, .available)
        XCTAssertTrue(health.hasAccess)
    }

    func testCheckAccessReturnsNotConfiguredDiagnostic() async throws {
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: []))
        let router = makeRouter(settingsStore: settingsStore)

        let health = try await router.checkAccess(for: .openAI)

        XCTAssertEqual(health.providerID, .openAI)
        XCTAssertEqual(health.state, .notConfigured)
    }

    private func makeRouter(
        settingsStore: FakeSettingsStore,
        providers: [FakeProvider] = [
            FakeProvider(id: .openAI, capabilities: [.textCorrection, .visionOCR]),
            FakeProvider(id: .gemini, capabilities: [.textCorrection, .visionOCR]),
        ]
    ) -> LLMRouter {
        LLMRouter(
            providers: providers,
            settingsStore: settingsStore
        )
    }

    private func makeSettings(configured: Set<LLMProviderID>) -> LLMSettings {
        var settings = LLMSettings.empty()

        for providerID in configured {
            settings.providerProfiles[providerID] = LLMProviderProfile(
                apiKey: "key-\(providerID.rawValue)",
                modelID: "model-\(providerID.rawValue)"
            )
        }

        return settings
    }
}

private final class CallTracker: @unchecked Sendable {
    var calledOpenAI = false
    var calledGemini = false
}

private enum FakeProviderError: Error {
    case unexpectedTask
}

private final class FakeSettingsStore: LLMSettingsProviding {
    var settings: LLMSettings

    init(settings: LLMSettings) {
        self.settings = settings
    }

    func loadSettings() -> LLMSettings { settings }

    func saveSettings(_ settings: LLMSettings) {
        self.settings = settings
    }

    func customGrammarInstructions() -> String { "" }

    func setCustomGrammarInstructions(_ value: String) {}

    func customScreenshotInstructions() -> String { "" }

    func setCustomScreenshotInstructions(_ value: String) {}
}

private struct FakeProvider: LLMProvider, @unchecked Sendable {
    let id: LLMProviderID
    let capabilities: Set<LLMCapability>
    let checkAccessResult: LLMProviderHealth
    let performHandler: (@Sendable (LLMTask, LLMProviderConfiguration) async throws -> LLMResult)?

    init(
        id: LLMProviderID,
        capabilities: Set<LLMCapability>,
        checkAccessResult: LLMProviderHealth? = nil,
        performHandler: (@Sendable (LLMTask, LLMProviderConfiguration) async throws -> LLMResult)? = nil
    ) {
        self.id = id
        self.capabilities = capabilities
        self.checkAccessResult = checkAccessResult
            ?? LLMProviderHealth(providerID: id, state: .available, message: "Ready")
        self.performHandler = performHandler
    }

    func checkAccess(configuration: LLMProviderConfiguration) async -> LLMProviderHealth {
        checkAccessResult
    }

    func perform(
        task: LLMTask,
        configuration: LLMProviderConfiguration
    ) async throws -> LLMResult {
        if let performHandler {
            return try await performHandler(task, configuration)
        }

        return .text("ok")
    }
}
