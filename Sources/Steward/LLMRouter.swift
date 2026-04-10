import Foundation
import StewardCore

@MainActor
protocol LLMRouting: AnyObject {
    func perform(_ request: LLMRequest) async throws -> LLMResult
    func checkAccess(for providerID: LLMProviderID) async throws -> LLMProviderHealth
}

@MainActor
final class LLMRouter: LLMRouting {
    private let settingsStore: AppSettingsProviding
    private let openAIClient: OpenAIClient
    private let geminiClient: GeminiClient

    init(
        settingsStore: AppSettingsProviding,
        openAIClient: OpenAIClient = OpenAIClient(),
        geminiClient: GeminiClient = GeminiClient()
    ) {
        self.settingsStore = settingsStore
        self.openAIClient = openAIClient
        self.geminiClient = geminiClient
    }

    func perform(_ request: LLMRequest) async throws -> LLMResult {
        let settings = settingsStore.loadSettings()
        let providerID = request.providerID
        let configuration = try configuration(for: request, from: settings)
        return try await perform(request.task, providerID: providerID, configuration: configuration)
    }

    func checkAccess(for providerID: LLMProviderID) async throws -> LLMProviderHealth {
        let settings = settingsStore.loadSettings()

        guard let configuration = settings.configuration(for: providerID) else {
            return LLMProviderHealth(
                providerID: providerID,
                state: .notConfigured,
                message: "Provider \(providerID.displayName) is missing API key or model ID in Preferences."
            )
        }

        return await healthCheck(for: providerID, configuration: configuration)
    }

    private func configuration(for request: LLMRequest, from settings: LLMSettings) throws
        -> LLMProviderConfiguration
    {
        let providerID = request.providerID

        guard let configuration = settings.configuration(for: providerID) else {
            throw LLMRouterError.providerNotConfigured(providerID)
        }

        guard let modelIDOverride = request.modelIDOverride else {
            return configuration
        }

        return LLMProviderConfiguration(apiKey: configuration.apiKey, modelID: modelIDOverride)
    }

    private func perform(
        _ task: LLMTask,
        providerID: LLMProviderID,
        configuration: LLMProviderConfiguration
    ) async throws -> LLMResult {
        switch providerID {
        case .openAI:
            return try await performOpenAI(task, configuration: configuration)
        case .gemini:
            return try await performGemini(task, configuration: configuration)
        }
    }

    private func performOpenAI(
        _ task: LLMTask,
        configuration: LLMProviderConfiguration
    ) async throws -> LLMResult {
        switch task {
        case .grammarCorrection(let text, let customInstructions):
            let correctedText = try await openAIClient.correctGrammar(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                customInstructions: customInstructions,
                text: text
            )
            return .text(correctedText)
        case .screenOCR(let imageData, let mimeType, let customInstructions):
            let extractedText = try await openAIClient.extractMarkdownText(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                imageData: imageData,
                mimeType: mimeType,
                customInstructions: customInstructions
            )
            return .text(extractedText)
        case .voiceTranscription:
            throw LLMRouterError.unsupportedTask("Voice dictation")
        }
    }

    private func performGemini(
        _ task: LLMTask,
        configuration: LLMProviderConfiguration
    ) async throws -> LLMResult {
        switch task {
        case .grammarCorrection(let text, let customInstructions):
            let correctedText = try await geminiClient.correctGrammar(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                customInstructions: customInstructions,
                text: text
            )
            return .text(correctedText)
        case .screenOCR(let imageData, let mimeType, let customInstructions):
            let extractedText = try await geminiClient.extractMarkdownText(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                imageData: imageData,
                mimeType: mimeType,
                customInstructions: customInstructions
            )
            return .text(extractedText)
        case .voiceTranscription:
            throw LLMRouterError.unsupportedTask("Voice dictation")
        }
    }

    private func healthCheck(
        for providerID: LLMProviderID,
        configuration: LLMProviderConfiguration
    ) async -> LLMProviderHealth {
        let result: LLMHealthCheckResult

        switch providerID {
        case .openAI:
            result = await openAIClient.checkAccessStatus(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID
            )
        case .gemini:
            result = await geminiClient.checkAccessStatus(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID
            )
        }

        return LLMProviderHealth(
            providerID: providerID,
            state: result.status,
            message: result.message
        )
    }
}
