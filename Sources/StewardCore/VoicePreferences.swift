import Foundation

private let voiceTranscriptionPrompt =
    """
    You are a dictation transcription assistant. Transcribe the spoken audio faithfully, preserve the original spoken language or language mix, do not translate, and return only the final cleaned text. Add punctuation, casing, and paragraph breaks when they improve readability, but do not add commentary or extra content.
    """

public func buildVoiceTranscriptionPrompt(customInstructions: String) -> String {
    if customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return voiceTranscriptionPrompt
    } else {
        return voiceTranscriptionPrompt + "\n\nAdditional instructions to follow:\n" + customInstructions
    }
}
