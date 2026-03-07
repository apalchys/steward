import Foundation
import StewardCore

enum LLMProviderID: String, CaseIterable, Codable, Identifiable {
    case openAI
    case gemini
    case anthropic
    case openAICompatible

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openAI:
            return "OpenAI"
        case .gemini:
            return "Gemini"
        case .anthropic:
            return "Anthropic"
        case .openAICompatible:
            return "OpenAI-Compatible"
        }
    }

    var capabilities: Set<LLMCapability> {
        switch self {
        case .openAI:
            return [.textCorrection]
        case .gemini:
            return [.visionOCR]
        case .anthropic:
            return [.textCorrection]
        case .openAICompatible:
            return [.textCorrection]
        }
    }

    var defaultModelID: String {
        switch self {
        case .openAI:
            return OpenAIClient.defaultModelID
        case .gemini:
            return GeminiClient.defaultModelID
        case .anthropic:
            return "claude-3-5-haiku-latest"
        case .openAICompatible:
            return OpenAIClient.defaultModelID
        }
    }
}

enum LLMCapability: String, Codable {
    case textCorrection
    case visionOCR
}

enum LLMTask {
    case grammarCorrection(text: String, customRules: String)
    case screenOCR(imageData: Data, mimeType: String)

    var requiredCapability: LLMCapability {
        switch self {
        case .grammarCorrection:
            return .textCorrection
        case .screenOCR:
            return .visionOCR
        }
    }
}

struct LLMRequest {
    let task: LLMTask
    let featureOverrideProviderID: LLMProviderID?
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
    let baseURL: String?

    var isConfigured: Bool {
        !apiKey.trimmed.isEmpty && !modelID.trimmed.isEmpty
    }
}

struct LLMProviderHealth {
    let providerID: LLMProviderID
    let hasAccess: Bool
}

enum LLMRouterError: LocalizedError {
    case providerNotRegistered(LLMProviderID)
    case providerDoesNotSupportCapability(providerID: LLMProviderID, capability: LLMCapability)
    case providerNotConfigured(LLMProviderID)
    case noConfiguredProvider(LLMCapability)

    var errorDescription: String? {
        switch self {
        case .providerNotRegistered(let providerID):
            return "Provider \(providerID.displayName) is not available in this app build."
        case .providerDoesNotSupportCapability(let providerID, let capability):
            switch capability {
            case .textCorrection:
                return "Provider \(providerID.displayName) does not support grammar correction."
            case .visionOCR:
                return "Provider \(providerID.displayName) does not support screen OCR."
            }
        case .providerNotConfigured(let providerID):
            return "Provider \(providerID.displayName) is missing API key or model ID in Preferences."
        case .noConfiguredProvider(let capability):
            switch capability {
            case .textCorrection:
                return "No configured provider is available for grammar correction."
            case .visionOCR:
                return "No configured provider is available for screen OCR."
            }
        }
    }
}

enum LLMProviderError: LocalizedError {
    case unsupportedTask(providerID: LLMProviderID)
    case missingBaseURL

    var errorDescription: String? {
        switch self {
        case .unsupportedTask(let providerID):
            return "Provider \(providerID.displayName) cannot handle this task."
        case .missingBaseURL:
            return "OpenAI-compatible provider requires a Base URL in Preferences."
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
            return "Screen Recording permission is required for OCR."
        case .cancelled:
            return "Screen OCR was cancelled."
        case .couldNotCaptureImage:
            return "Could not capture the selected screen region."
        case .invalidProviderResponse:
            return "Provider returned an invalid OCR response."
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

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
