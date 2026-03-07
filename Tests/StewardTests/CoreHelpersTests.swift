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
}
