import Foundation
import StewardCore

@MainActor
protocol LLMRouting: AnyObject {
    func perform(_ request: LLMRequest) async throws -> LLMResult
    func checkAccess(for selection: LLMModelSelection) async throws -> LLMProviderHealth
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
        let configuration = try configuration(for: request.selection, from: settings)
        return try await perform(request.task, providerID: request.providerID, configuration: configuration)
    }

    func checkAccess(for selection: LLMModelSelection) async throws -> LLMProviderHealth {
        let settings = settingsStore.loadSettings()

        guard let configuration = availableConfiguration(for: selection, from: settings) else {
            return LLMProviderHealth(
                providerID: selection.providerID,
                state: .notConfigured,
                message: "Provider \(selection.providerID.displayName) is missing an API key in Preferences."
            )
        }

        return await healthCheck(for: selection.providerID, configuration: configuration)
    }

    private func configuration(for selection: LLMModelSelection, from settings: LLMSettings) throws
        -> LLMProviderConfiguration
    {
        guard let configuration = availableConfiguration(for: selection, from: settings) else {
            throw LLMRouterError.providerNotConfigured(selection.providerID)
        }

        return configuration
    }

    private func availableConfiguration(for selection: LLMModelSelection, from settings: LLMSettings)
        -> LLMProviderConfiguration?
    {
        let apiKey = settings.providerSettings(for: selection.providerID).apiKey.trimmed
        let configuration = LLMProviderConfiguration(
            apiKey: apiKey,
            modelID: selection.modelID
        )

        return configuration.isConfigured ? configuration : nil
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
        case .voiceTranscription(let audioData, let mimeType, let customInstructions):
            let transcript = try await openAIClient.transcribeAudio(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                audioData: audioData,
                mimeType: mimeType,
                customInstructions: customInstructions
            )
            return .text(transcript)
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
        case .voiceTranscription(let audioData, let mimeType, let customInstructions):
            let transcript = try await geminiClient.transcribeAudio(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                audioData: audioData,
                mimeType: mimeType,
                customInstructions: customInstructions
            )
            return .text(transcript)
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
