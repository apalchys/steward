import XCTest
@testable import StewardCore

final class CoreHelpersTests: XCTestCase {
    func testBuildGrammarPromptReturnsBasePromptWhenRulesAreEmpty() {
        let defaultPrompt = buildGrammarPrompt(customInstructions: "")
        let whitespacePrompt = buildGrammarPrompt(customInstructions: "  \n\t")

        XCTAssertEqual(whitespacePrompt, defaultPrompt)
    }

    func testBuildGrammarPromptAppendsCustomInstructions() {
        let customInstructions = "Prefer short sentences."
        let prompt = buildGrammarPrompt(customInstructions: customInstructions)

        XCTAssertTrue(prompt.contains("Additional instructions to follow:"))
        XCTAssertTrue(prompt.hasSuffix(customInstructions))
    }

    func testBuildVoiceTranscriptionPromptReturnsBasePromptWhenRulesAreEmpty() {
        let defaultPrompt = buildVoiceTranscriptionPrompt(customInstructions: "")
        let whitespacePrompt = buildVoiceTranscriptionPrompt(customInstructions: "  \n\t")

        XCTAssertEqual(whitespacePrompt, defaultPrompt)
        XCTAssertTrue(defaultPrompt.contains("preserve the original spoken language"))
        XCTAssertTrue(defaultPrompt.contains("do not translate"))
    }

    func testBuildVoiceTranscriptionPromptAppendsCustomInstructions() {
        let customInstructions = "Keep sentence fragments if they sound intentional."
        let prompt = buildVoiceTranscriptionPrompt(customInstructions: customInstructions)

        XCTAssertTrue(prompt.contains("Additional instructions to follow:"))
        XCTAssertTrue(prompt.hasSuffix(customInstructions))
    }
}
