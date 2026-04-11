import Foundation

public struct VoiceTranscriptionOptions: Equatable, Sendable {
    public let preferredRecognitionLanguages: [VoiceLanguage]
    public let translateToLanguageEnabled: Bool
    public let translationTargetLanguage: VoiceLanguage?
    public let customInstructions: String

    public init(
        preferredRecognitionLanguages: [VoiceLanguage] = [],
        translateToLanguageEnabled: Bool = false,
        translationTargetLanguage: VoiceLanguage? = nil,
        customInstructions: String = ""
    ) {
        self.preferredRecognitionLanguages = preferredRecognitionLanguages
        self.translateToLanguageEnabled = translateToLanguageEnabled
        self.translationTargetLanguage = translationTargetLanguage
        self.customInstructions = customInstructions
    }
}
