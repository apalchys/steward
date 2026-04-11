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

    func testBuildVoiceTranscriptionPromptIncludesRecognitionLanguageHints() {
        let prompt = buildVoiceTranscriptionPrompt(
            options: VoiceTranscriptionOptions(
                preferredRecognitionLanguages: [.english, .spanish, .french]
            )
        )

        XCTAssertTrue(prompt.contains("Recognition language hints"))
        XCTAssertTrue(prompt.contains("English, Spanish, French"))
        XCTAssertTrue(prompt.contains("transcribe what was actually said"))
    }

    func testBuildVoiceTranscriptionPromptIncludesTranslationInstructions() {
        let prompt = buildVoiceTranscriptionPrompt(
            options: VoiceTranscriptionOptions(
                preferredRecognitionLanguages: [.english, .spanish],
                translateToLanguageEnabled: true,
                translationTargetLanguage: .german
            )
        )

        XCTAssertTrue(prompt.contains("translate the final result into German"))
        XCTAssertTrue(prompt.contains("Return only the translated final text in German"))
        XCTAssertTrue(prompt.contains("English, Spanish"))
        XCTAssertFalse(prompt.contains("do not translate"))
    }

    func testBuildVoiceTranscriptionPromptAppendsCustomInstructions() {
        let customInstructions = "Keep sentence fragments if they sound intentional."
        let prompt = buildVoiceTranscriptionPrompt(customInstructions: customInstructions)

        XCTAssertTrue(prompt.contains("Additional instructions to follow:"))
        XCTAssertTrue(prompt.hasSuffix(customInstructions))
    }
}
