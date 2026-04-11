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
                    supportedFeatures: [.refine, .screenText]
                ),
                LLMModelCatalogEntry(
                    providerID: .openAI,
                    modelID: "gpt-5.4-mini",
                    supportedFeatures: [.refine, .screenText]
                ),
                LLMModelCatalogEntry(
                    providerID: .openAI,
                    modelID: "gpt-4o-mini-transcribe",
                    supportedFeatures: [.voice]
                ),
                LLMModelCatalogEntry(
                    providerID: .gemini,
                    modelID: "gemini-3-flash-preview",
                    supportedFeatures: [.refine, .screenText, .voice]
                ),
                LLMModelCatalogEntry(
                    providerID: .gemini,
                    modelID: "gemini-3.1-flash-lite-preview",
                    supportedFeatures: [.refine, .screenText, .voice]
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
            for: .refine,
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

    func testSanitizedSelectionFallsBackToOpenAIDefaultForCaptureWhenOnlyOpenAIEnabled() {
        let selection = LLMModelCatalog.sanitizedSelection(
            LLMModelSelection(providerID: .gemini, modelID: "not-in-catalog"),
            for: .screenText,
            enabledProviders: [.openAI]
        )

        XCTAssertEqual(selection, LLMModelSelection(providerID: .openAI, modelID: "gpt-5.4"))
    }

    func testValidationErrorsIncludeDuplicateModelIDs() {
        let errors = LLMModelCatalog.validationErrors(
            in: [
                LLMProviderCatalog(
                    providerID: .openAI,
                    defaultModelID: "dup",
                    models: [
                        LLMProviderModel(modelID: "dup", capabilities: [.refine]),
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

    func testValidationErrorsIncludeMissingDefaultModel() {
        let errors = LLMModelCatalog.validationErrors(
            in: [
                LLMProviderCatalog(
                    providerID: .gemini,
                    defaultModelID: "missing-default",
                    models: [
                        LLMProviderModel(
                            modelID: "gemini-test",
                            capabilities: [.refine]
                        )
                    ]
                )
            ]
        )

        XCTAssertEqual(
            errors,
            [.missingDefaultModel(providerID: .gemini, defaultModelID: "missing-default")]
        )
    }

    func testDefaultModelIDReturnsConfiguredProviderDefault() {
        XCTAssertEqual(
            LLMModelCatalog.defaultModelID(for: .openAI),
            "gpt-5.4"
        )
    }
}
