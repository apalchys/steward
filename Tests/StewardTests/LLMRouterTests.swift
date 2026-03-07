import Foundation
import XCTest
@testable import Steward

final class LLMRouterTests: XCTestCase {
    func testPerformUsesRequestedProviderForGrammar() {
        var didCallOpenAI = false
        var didCallGemini = false
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: [.openAI, .gemini]))
        let router = makeRouter(
            settingsStore: settingsStore,
            providers: [
                FakeProvider(
                    id: .openAI,
                    capabilities: [.textCorrection],
                    performHandler: { task, configuration, completion in
                        didCallOpenAI = true
                        guard case let .grammarCorrection(text, _) = task else {
                            XCTFail("Expected grammar task")
                            return
                        }
                        XCTAssertEqual(text, "text")
                        XCTAssertEqual(configuration.apiKey, "key-openAI")
                        completion(.success(.text("ok")))
                    }
                ),
                FakeProvider(
                    id: .gemini,
                    capabilities: [.visionOCR],
                    performHandler: { _, _, _ in
                        didCallGemini = true
                    }
                ),
            ]
        )

        let result: Result<LLMResult, Error> = waitForValue { completion in
            router.perform(
                LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "text", customInstructions: "")),
                completion: completion
            )
        }

        switch result {
        case .success(let response):
            XCTAssertEqual(response.textValue, "ok")
            XCTAssertTrue(didCallOpenAI)
            XCTAssertFalse(didCallGemini)
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testPerformFailsWhenProviderIsNotRegistered() {
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: [.openAI]))
        let router = makeRouter(settingsStore: settingsStore, providers: [])

        let result: Result<LLMResult, Error> = waitForValue { completion in
            router.perform(
                LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "text", customInstructions: "")),
                completion: completion
            )
        }

        switch result {
        case .success:
            XCTFail("Expected registration error")
        case .failure(let error):
            guard case let LLMRouterError.providerNotRegistered(providerID) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(providerID, .openAI)
        }
    }

    func testPerformFailsWhenProviderIsNotConfigured() {
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: []))
        let router = makeRouter(settingsStore: settingsStore)

        let result: Result<LLMResult, Error> = waitForValue { completion in
            router.perform(
                LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "text", customInstructions: "")),
                completion: completion
            )
        }

        switch result {
        case .success:
            XCTFail("Expected configuration error")
        case .failure(let error):
            guard case let LLMRouterError.providerNotConfigured(providerID) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(providerID, .openAI)
        }
    }

    func testPerformFailsWhenRequestedProviderDoesNotSupportCapability() {
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: [.openAI]))
        let router = makeRouter(
            settingsStore: settingsStore,
            providers: [FakeProvider(id: .openAI, capabilities: [.visionOCR])]
        )

        let result: Result<LLMResult, Error> = waitForValue { completion in
            router.perform(
                LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "text", customInstructions: "")),
                completion: completion
            )
        }

        switch result {
        case .success:
            XCTFail("Expected capability error")
        case .failure(let error):
            guard case let LLMRouterError.providerDoesNotSupportCapability(providerID, capability) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(providerID, .openAI)
            XCTAssertEqual(capability, .textCorrection)
        }
    }

    func testCheckAccessReturnsRequestedProviderHealth() {
        let settingsStore = FakeSettingsStore(settings: makeSettings(configured: [.openAI, .gemini]))
        let router = makeRouter(
            settingsStore: settingsStore,
            providers: [FakeProvider(id: .openAI, capabilities: [.textCorrection], checkAccessResult: true)]
        )

        let result: Result<LLMProviderHealth, Error> = waitForValue { completion in
            router.checkAccess(for: .openAI, completion: completion)
        }

        switch result {
        case .success(let health):
            XCTAssertEqual(health.providerID, .openAI)
            XCTAssertTrue(health.hasAccess)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
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
                modelID: "model-\(providerID.rawValue)",
                baseURL: ""
            )
        }

        return settings
    }
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

    func migrateLegacySettingsIfNeeded() {}

    func customGrammarInstructions() -> String { "" }

    func setCustomGrammarInstructions(_ value: String) {}

    func customScreenshotInstructions() -> String { "" }

    func setCustomScreenshotInstructions(_ value: String) {}
}

private struct FakeProvider: LLMProvider {
    let id: LLMProviderID
    let capabilities: Set<LLMCapability>
    let checkAccessResult: Bool
    let performHandler: ((LLMTask, LLMProviderConfiguration, @escaping (Result<LLMResult, Error>) -> Void) -> Void)?

    init(
        id: LLMProviderID,
        capabilities: Set<LLMCapability>,
        checkAccessResult: Bool = true,
        performHandler: ((LLMTask, LLMProviderConfiguration, @escaping (Result<LLMResult, Error>) -> Void) -> Void)? = nil
    ) {
        self.id = id
        self.capabilities = capabilities
        self.checkAccessResult = checkAccessResult
        self.performHandler = performHandler
    }

    func checkAccess(configuration: LLMProviderConfiguration, completion: @escaping (Bool) -> Void) {
        completion(checkAccessResult)
    }

    func perform(
        task: LLMTask,
        configuration: LLMProviderConfiguration,
        completion: @escaping (Result<LLMResult, Error>) -> Void
    ) {
        if let performHandler {
            performHandler(task, configuration, completion)
            return
        }

        completion(.success(.text("ok")))
    }
}
