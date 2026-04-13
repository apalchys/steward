import Foundation

public struct VoiceTranscriptionOptions: Equatable, Sendable {
    public let preferredRecognitionLanguages: [VoiceLanguage]
    public let customInstructions: String

    public init(
        preferredRecognitionLanguages: [VoiceLanguage] = [],
        customInstructions: String = ""
    ) {
        self.preferredRecognitionLanguages = preferredRecognitionLanguages
        self.customInstructions = customInstructions
    }
}
