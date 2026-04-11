import XCTest
@testable import StewardCore

final class CoreHelpersTests: XCTestCase {
    func testBuildRefinePromptReturnsBasePromptWhenRulesAreEmpty() {
        let defaultPrompt = buildRefinePrompt(customInstructions: "")
        let whitespacePrompt = buildRefinePrompt(customInstructions: "  \n\t")

        XCTAssertEqual(whitespacePrompt, defaultPrompt)
    }

    func testBuildRefinePromptAppendsCustomInstructions() {
        let customInstructions = "Prefer short sentences."
        let prompt = buildRefinePrompt(customInstructions: customInstructions)

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
