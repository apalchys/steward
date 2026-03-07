import Foundation
import XCTest
@testable import Steward

final class LLMRouterTests: XCTestCase {
    func testResolvedProviderPrefersFeatureOverrideOverGlobalDefault() {
        let settingsStore = FakeSettingsStore(
            settings: makeSettings(
                globalDefault: .openAI,
                grammarOverride: .openAICompatible,
                configured: [.openAI, .openAICompatible]
            )
        )
        let router = LLMRouter(
            providers: [
                FakeProvider(id: .openAI, capabilities: [.textCorrection]),
                FakeProvider(id: .openAICompatible, capabilities: [.textCorrection]),
            ],
            settingsStore: settingsStore
        )

        let providerID = router.resolvedProviderID(
            for: .textCorrection,
            featureOverrideProviderID: .openAICompatible
        )

        XCTAssertEqual(providerID, .openAICompatible)
    }

    func testResolvedProviderFallsBackToGlobalDefaultWhenNoOverride() {
        let settingsStore = FakeSettingsStore(
            settings: makeSettings(
                globalDefault: .openAI,
                grammarOverride: nil,
                configured: [.openAI, .openAICompatible]
            )
        )
        let router = LLMRouter(
            providers: [
                FakeProvider(id: .openAI, capabilities: [.textCorrection]),
                FakeProvider(id: .openAICompatible, capabilities: [.textCorrection]),
            ],
            settingsStore: settingsStore
        )

        let providerID = router.resolvedProviderID(
            for: .textCorrection,
            featureOverrideProviderID: nil
        )

        XCTAssertEqual(providerID, .openAI)
    }

    func testResolvedProviderUsesFirstConfiguredCapableWhenOverrideAndDefaultMissing() {
        let settingsStore = FakeSettingsStore(
            settings: makeSettings(
                globalDefault: nil,
                grammarOverride: nil,
                configured: [.openAICompatible]
            )
        )
        let router = LLMRouter(
            providers: [
                FakeProvider(id: .openAI, capabilities: [.textCorrection]),
                FakeProvider(id: .openAICompatible, capabilities: [.textCorrection]),
            ],
            settingsStore: settingsStore
        )

        let providerID = router.resolvedProviderID(
            for: .textCorrection,
            featureOverrideProviderID: nil
        )

        XCTAssertEqual(providerID, .openAICompatible)
    }

    func testPerformFailsWhenOverrideProviderDoesNotSupportCapability() {
        let settingsStore = FakeSettingsStore(
            settings: makeSettings(
                globalDefault: nil,
                grammarOverride: .gemini,
                configured: [.gemini]
            )
        )
        let router = LLMRouter(
            providers: [
                FakeProvider(id: .gemini, capabilities: [.visionOCR]),
            ],
            settingsStore: settingsStore
        )

        let result: Result<LLMResult, Error> = waitForValue { completion in
            router.perform(
                LLMRequest(
                    task: .grammarCorrection(text: "text", customRules: ""),
                    featureOverrideProviderID: .gemini
                ),
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
            XCTAssertEqual(providerID, .gemini)
            XCTAssertEqual(capability, .textCorrection)
        }
    }

    func testPerformFailsWhenNoConfiguredProviderExists() {
        let settingsStore = FakeSettingsStore(settings: makeSettings(globalDefault: nil, grammarOverride: nil, configured: []))
        let router = LLMRouter(
            providers: [
                FakeProvider(id: .openAI, capabilities: [.textCorrection])
            ],
            settingsStore: settingsStore
        )

        let result: Result<LLMResult, Error> = waitForValue { completion in
            router.perform(
                LLMRequest(task: .grammarCorrection(text: "text", customRules: ""), featureOverrideProviderID: nil),
                completion: completion
            )
        }

        switch result {
        case .success:
            XCTFail("Expected missing provider error")
        case .failure(let error):
            guard case let LLMRouterError.noConfiguredProvider(capability) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertEqual(capability, .textCorrection)
        }
    }

    func testCheckAccessReturnsSelectedProviderHealth() {
        let settingsStore = FakeSettingsStore(
            settings: makeSettings(
                globalDefault: .openAI,
                grammarOverride: nil,
                configured: [.openAI]
            )
        )
        let router = LLMRouter(
            providers: [
                FakeProvider(id: .openAI, capabilities: [.textCorrection], checkAccessResult: true)
            ],
            settingsStore: settingsStore
        )

        let result: Result<LLMProviderHealth, Error> = waitForValue { completion in
            router.checkAccess(for: .textCorrection, featureOverrideProviderID: nil, completion: completion)
        }

        switch result {
        case .success(let health):
            XCTAssertEqual(health.providerID, .openAI)
            XCTAssertTrue(health.hasAccess)
        case .failure(let error):
            XCTFail("Expected success, got error: \(error)")
        }
    }

    private func makeSettings(
        globalDefault: LLMProviderID?,
        grammarOverride: LLMProviderID?,
        configured: Set<LLMProviderID>
    ) -> LLMSettings {
        var settings = LLMSettings.empty()
        settings.globalDefaultProviderID = globalDefault
        settings.grammarProviderOverrideID = grammarOverride

        for providerID in configured {
            settings.providerProfiles[providerID] = LLMProviderProfile(
                apiKey: "key-\(providerID.rawValue)",
                modelID: "model-\(providerID.rawValue)",
                baseURL: providerID == .openAICompatible ? "https://compatible.example" : ""
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

    func customGrammarRules() -> String { "" }

    func setCustomGrammarRules(_ value: String) {}
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
