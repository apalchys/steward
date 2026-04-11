import Foundation

private let voiceTranscriptionPrompt =
    """
    You are a dictation transcription assistant. Transcribe the spoken audio faithfully, preserve the original spoken language or language mix, do not translate, and return only the final cleaned text. Add punctuation, casing, and paragraph breaks when they improve readability, but do not add commentary or extra content.
    """

private func translationPrompt(for language: VoiceLanguage) -> String {
    """
    You are a dictation transcription assistant. Transcribe the spoken audio faithfully, then translate the final result into \(language.displayName). Return only the translated final text in \(language.displayName). Do not include the source transcript, commentary, labels, or extra content. Add punctuation, casing, and paragraph breaks when they improve readability.
    """
}

public func buildVoiceTranscriptionPrompt(customInstructions: String) -> String {
    buildVoiceTranscriptionPrompt(
        options: VoiceTranscriptionOptions(customInstructions: customInstructions)
    )
}

public func buildVoiceTranscriptionPrompt(options: VoiceTranscriptionOptions) -> String {
    var sections: [String] = []

    if options.translateToLanguageEnabled, let translationTargetLanguage = options.translationTargetLanguage {
        sections.append(translationPrompt(for: translationTargetLanguage))
    } else {
        sections.append(voiceTranscriptionPrompt)
    }

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
