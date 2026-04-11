import XCTest
@testable import Steward

final class LLMModelCatalogTests: XCTestCase {
    func testCompatibleSelectionsIncludeOnlyEnabledProvidersAndSupportedFeatures() {
        let selections = LLMModelCatalog.compatibleSelections(
            for: .voice,
            enabledProviders: [.openAI]
        )

        XCTAssertEqual(selections, [LLMModelSelection(providerID: .openAI, modelID: "gpt-4o-mini-transcribe")])
    }

    func testSanitizedSelectionFallsBackToSameProviderWhenPossible() {
        let selection = LLMModelCatalog.sanitizedSelection(
            LLMModelSelection(providerID: .openAI, modelID: "not-in-catalog"),
            for: .voice,
            enabledProviders: [.openAI, .gemini]
        )

        XCTAssertEqual(selection, LLMModelSelection(providerID: .openAI, modelID: "gpt-4o-mini-transcribe"))
    }

    func testSanitizedSelectionReturnsNilWhenNoCompatibleEnabledModelsExist() {
        let selection = LLMModelCatalog.sanitizedSelection(
            LLMModelSelection(providerID: .gemini, modelID: "not-in-catalog"),
            for: .screenText,
            enabledProviders: [.openAI]
        )

        XCTAssertNil(selection)
    }
}
