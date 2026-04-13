import Foundation

private let voiceTranscriptionPrompt =
    """
    You are a dictation transcription assistant. Transcribe the spoken audio faithfully and return only the final cleaned text. Preserve the original spoken language or language mix unless additional instructions explicitly request another transformation. Add punctuation, casing, and paragraph breaks when they improve readability, but do not add commentary or extra content.
    """

public func buildVoiceTranscriptionPrompt(customInstructions: String) -> String {
    buildVoiceTranscriptionPrompt(
        options: VoiceTranscriptionOptions(customInstructions: customInstructions)
    )
}

public func buildVoiceTranscriptionPrompt(options: VoiceTranscriptionOptions) -> String {
    var sections: [String] = [voiceTranscriptionPrompt]

    if !options.preferredRecognitionLanguages.isEmpty {
        let languageList = options.preferredRecognitionLanguages.map(\.displayName).joined(separator: ", ")
        sections.append(
            """
            Recognition language hints: prioritize recognition for these languages when the audio is ambiguous: \(languageList). If the speaker uses another language or a language mix, transcribe what was actually said.
            """
        )
    }

    let customInstructions = options.customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    if !customInstructions.isEmpty {
        sections.append("Additional instructions to follow:\n\(customInstructions)")
    }

    return sections.joined(separator: "\n\n")
}
