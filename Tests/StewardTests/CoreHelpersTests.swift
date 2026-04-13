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
        XCTAssertTrue(defaultPrompt.contains("If the audio has nothing to recognize, return an empty string."))
        XCTAssertTrue(defaultPrompt.contains("Preserve the original spoken language"))
        XCTAssertTrue(
            defaultPrompt.contains("unless additional instructions explicitly request another transformation"))
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

    func testBuildVoiceTranscriptionPromptAllowsCustomInstructionsToOverrideDefaultOutputShape() {
        let prompt = buildVoiceTranscriptionPrompt(
            options: VoiceTranscriptionOptions(
                preferredRecognitionLanguages: [.english, .spanish],
                customInstructions: "Translate final text to German."
            )
        )

        XCTAssertTrue(prompt.contains("English, Spanish"))
        XCTAssertTrue(prompt.contains("Translate final text to German."))
        XCTAssertFalse(prompt.contains("do not translate"))
    }

    func testBuildVoiceTranscriptionPromptAppendsCustomInstructions() {
        let customInstructions = "Keep sentence fragments if they sound intentional."
        let prompt = buildVoiceTranscriptionPrompt(customInstructions: customInstructions)

        XCTAssertTrue(prompt.contains("Additional instructions to follow:"))
        XCTAssertTrue(prompt.hasSuffix(customInstructions))
    }
}
