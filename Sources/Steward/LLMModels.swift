import Foundation
import StewardCore

enum LLMProviderID: String, CaseIterable, Codable, Identifiable {
    case openAI
    case gemini

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        }
    }
}

enum LLMFeature: String, CaseIterable, Hashable {
    case grammar
    case screenText
    case voice

    var displayName: String {
        switch self {
        case .grammar:
            return "Grammar"
        case .screenText:
            return "Screen Text"
        case .voice:
            return "Voice Dictation"
        }
    }
}

enum LLMTask {
    case grammarCorrection(text: String, customInstructions: String)
    case screenOCR(imageData: Data, mimeType: String, customInstructions: String)
    case voiceTranscription(audioData: Data, mimeType: String, customInstructions: String)
}

struct LLMRequest {
    let selection: LLMModelSelection
    let task: LLMTask

    var providerID: LLMProviderID {
        selection.providerID
    }

    var modelID: String {
        selection.modelID
    }
}

enum LLMResult {
    case text(String)

    var textValue: String? {
        switch self {
        case .text(let value):
            return value
        }
    }
}

struct LLMProviderConfiguration: Equatable {
    let apiKey: String
    let modelID: String

    var isConfigured: Bool {
        !apiKey.trimmed.isEmpty && !modelID.trimmed.isEmpty
    }
}

struct LLMProviderHealth {
    let providerID: LLMProviderID
    let state: LLMHealthCheckStatus
    let message: String

    var hasAccess: Bool {
        state == .available
    }
}

enum LLMRouterError: LocalizedError {
    case providerNotConfigured(LLMProviderID)
    case featureNotConfigured(String)
    case unsupportedTask(String)

    var errorDescription: String? {
        switch self {
        case .providerNotConfigured(let providerID):
            return "Provider \(providerID.displayName) is missing an API key in Preferences."
        case .featureNotConfigured(let featureName):
            return "\(featureName) is missing a compatible model in Preferences."
        case .unsupportedTask(let taskName):
            return "\(taskName) is not supported yet."
        }
    }
}

enum GrammarCoordinatorError: LocalizedError {
    case noSelectedText
    case invalidProviderResponse

    var errorDescription: String? {
        switch self {
        case .noSelectedText:
            return "No selected text was found."
        case .invalidProviderResponse:
            return "Provider returned an invalid response for grammar correction."
        }
    }
}

enum ScreenOCRCoordinatorError: LocalizedError {
    case permissionDenied
    case cancelled
    case couldNotCaptureImage
    case invalidProviderResponse

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Screen Recording permission is required for Screen Text."
        case .cancelled:
            return "Screen Text capture was cancelled."
        case .couldNotCaptureImage:
            return "Could not capture the selected screen region."
        case .invalidProviderResponse:
            return "Provider returned an invalid Screen Text response."
        }
    }
}

enum ProviderStatus {
    case ok(providerID: LLMProviderID)
    case error(providerID: LLMProviderID?, message: String)
    case processing(providerID: LLMProviderID?)
}

enum ActivityStatus {
    case ready
    case processing
    case error
}
