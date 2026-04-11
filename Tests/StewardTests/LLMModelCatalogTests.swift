import XCTest
@testable import Steward

final class LLMModelCatalogTests: XCTestCase {
    func testEntriesAreDerivedFromProviderCatalogs() {
        XCTAssertEqual(
            LLMModelCatalog.entries,
            [
                LLMModelCatalogEntry(
                    providerID: .openAI,
                    modelID: "gpt-5.4",
                    supportedFeatures: [.grammar]
                ),
                LLMModelCatalogEntry(
                    providerID: .openAI,
                    modelID: "gpt-4o-mini-transcribe",
                    supportedFeatures: [.voice]
                ),
                LLMModelCatalogEntry(
                    providerID: .gemini,
                    modelID: "gemini-3.1-flash-lite-preview",
                    supportedFeatures: [.grammar, .screenText, .voice]
                ),
            ]
        )
    }

    func testCompatibleSelectionsIncludeOnlyEnabledProvidersAndSupportedFeatures() {
        let selections = LLMModelCatalog.compatibleSelections(
            for: .voice,
            enabledProviders: [.openAI]
        )

        XCTAssertEqual(selections, [LLMModelSelection(providerID: .openAI, modelID: "gpt-4o-mini-transcribe")])
    }

    func testDefaultSelectionPrefersProviderDefault() {
        let selection = LLMModelCatalog.defaultSelection(
            for: .grammar,
            preferredProviderID: .openAI,
            enabledProviders: [.openAI, .gemini]
        )

        XCTAssertEqual(selection, LLMModelSelection(providerID: .openAI, modelID: "gpt-5.4"))
    }

    func testSanitizedSelectionFallsBackToPreferredProviderDefaultWhenSelectionInvalid() {
        let selection = LLMModelCatalog.sanitizedSelection(
            LLMModelSelection(providerID: .openAI, modelID: "not-in-catalog"),
            for: .voice,
            enabledProviders: [.openAI, .gemini]
        )

        XCTAssertEqual(selection, LLMModelSelection(providerID: .openAI, modelID: "gpt-4o-mini-transcribe"))
    }

    func testSanitizedSelectionFallsBackToCrossProviderDefaultWhenPreferredProviderDisabled() {
        let selection = LLMModelCatalog.sanitizedSelection(
            LLMModelSelection(providerID: .openAI, modelID: "not-in-catalog"),
            for: .screenText,
            enabledProviders: [.gemini]
        )

        XCTAssertEqual(
            selection,
            LLMModelSelection(providerID: .gemini, modelID: "gemini-3.1-flash-lite-preview")
        )
    }

    func testSanitizedSelectionReturnsNilWhenNoCompatibleEnabledModelsExist() {
        let selection = LLMModelCatalog.sanitizedSelection(
            LLMModelSelection(providerID: .gemini, modelID: "not-in-catalog"),
            for: .screenText,
            enabledProviders: [.openAI]
        )

        XCTAssertNil(selection)
    }

    func testValidationErrorsIncludeDuplicateModelIDs() {
        let errors = LLMModelCatalog.validationErrors(
            in: [
                LLMProviderCatalog(
                    providerID: .openAI,
                    models: [
                        LLMProviderModel(modelID: "dup", capabilities: [.grammar]),
                        LLMProviderModel(modelID: "dup", capabilities: [.voice]),
                    ]
                )
            ]
        )

        XCTAssertEqual(
            errors,
            [.duplicateModelID(providerID: .openAI, modelID: "dup")]
        )
    }

    func testValidationErrorsIncludeUnsupportedDefaultCapabilities() {
        let errors = LLMModelCatalog.validationErrors(
            in: [
                LLMProviderCatalog(
                    providerID: .gemini,
                    models: [
                        LLMProviderModel(
                            modelID: "gemini-test",
                            capabilities: [.grammar],
                            defaultCapabilities: [.voice]
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(
            errors,
            [.invalidDefaultCapability(providerID: .gemini, modelID: "gemini-test", feature: .voice)]
        )
    }

    func testValidationErrorsIncludeDuplicateDefaultsForFeature() {
        let errors = LLMModelCatalog.validationErrors(
            in: [
                LLMProviderCatalog(
                    providerID: .openAI,
                    models: [
                        LLMProviderModel(
                            modelID: "grammar-a",
                            capabilities: [.grammar],
                            defaultCapabilities: [.grammar]
                        ),
                        LLMProviderModel(
                            modelID: "grammar-b",
                            capabilities: [.grammar],
                            defaultCapabilities: [.grammar]
                        ),
                    ]
                )
            ]
        )

        XCTAssertEqual(
            errors,
            [
                .duplicateDefault(
                    providerID: .openAI,
                    feature: .grammar,
                    modelIDs: ["grammar-a", "grammar-b"]
                )
            ]
        )
    }
}
