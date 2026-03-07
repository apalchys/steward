import Foundation
import StewardCore

protocol LLMProvider: Sendable {
    var id: LLMProviderID { get }
    var capabilities: Set<LLMCapability> { get }

    func checkAccess(configuration: LLMProviderConfiguration) async -> LLMProviderHealth
    func perform(task: LLMTask, configuration: LLMProviderConfiguration) async throws -> LLMResult
}

protocol LLMRouting: AnyObject, Sendable {
    var supportedProviderIDs: [LLMProviderID] { get }

    func perform(_ request: LLMRequest) async throws -> LLMResult
    func checkAccess(for providerID: LLMProviderID) async throws -> LLMProviderHealth
}

final class LLMRouter: LLMRouting, @unchecked Sendable {
    let supportedProviderIDs: [LLMProviderID]

    private let providers: [LLMProviderID: LLMProvider]
    private let settingsStore: LLMSettingsProviding

    init(providers: [LLMProvider], settingsStore: LLMSettingsProviding) {
        let providerMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.providers = providerMap
        self.settingsStore = settingsStore
        self.supportedProviderIDs = LLMProviderID.allCases.filter { providerMap[$0] != nil }
    }

    func perform(_ request: LLMRequest) async throws -> LLMResult {
        let settings = settingsStore.loadSettings()

        let providerID = request.providerID
        let provider = try providerForID(providerID)
        let configuration = try configuration(for: providerID, from: settings)
        let capability = request.task.requiredCapability

        guard provider.capabilities.contains(capability) else {
            throw LLMRouterError.providerDoesNotSupportCapability(providerID: providerID, capability: capability)
        }

        return try await provider.perform(task: request.task, configuration: configuration)
    }

    func checkAccess(for providerID: LLMProviderID) async throws -> LLMProviderHealth {
        let settings = settingsStore.loadSettings()

        let provider = try providerForID(providerID)
        guard let configuration = settings.configuration(for: providerID) else {
            return LLMProviderHealth(
                providerID: providerID,
                state: .notConfigured,
                message: "Provider \(providerID.displayName) is missing API key or model ID in Preferences."
            )
        }

        return await provider.checkAccess(configuration: configuration)
    }

    private func providerForID(_ providerID: LLMProviderID) throws -> LLMProvider {
        guard let provider = providers[providerID] else {
            throw LLMRouterError.providerNotRegistered(providerID)
        }

        return provider
    }

    private func configuration(for providerID: LLMProviderID, from settings: LLMSettings) throws
        -> LLMProviderConfiguration
    {
        guard let configuration = settings.configuration(for: providerID) else {
            throw LLMRouterError.providerNotConfigured(providerID)
        }

        return configuration
    }
}

struct OpenAILLMProvider: LLMProvider {
    let id: LLMProviderID = .openAI
    let capabilities: Set<LLMCapability> = [.textCorrection, .visionOCR]

    private let client: OpenAIClient

    init(client: OpenAIClient = OpenAIClient()) {
        self.client = client
    }

    func checkAccess(configuration: LLMProviderConfiguration) async -> LLMProviderHealth {
        health(from: await client.checkAccessStatus(apiKey: configuration.apiKey, modelID: configuration.modelID))
    }

    func perform(task: LLMTask, configuration: LLMProviderConfiguration) async throws -> LLMResult {
        switch task {
        case .grammarCorrection(let text, let customInstructions):
            let correctedText = try await client.correctGrammar(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                customInstructions: customInstructions,
                text: text
            )
            return .text(correctedText)
        case .screenOCR(let imageData, let mimeType, let customInstructions):
            let extractedText = try await client.extractMarkdownText(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                imageData: imageData,
                mimeType: mimeType,
                customInstructions: customInstructions
            )
            return .text(extractedText)
        }
    }

    private func health(from result: LLMHealthCheckResult) -> LLMProviderHealth {
        LLMProviderHealth(
            providerID: id,
            state: mapHealthState(result.status),
            message: result.message
        )
    }

    private func mapHealthState(_ status: LLMHealthCheckStatus) -> LLMProviderHealthState {
        switch status {
        case .available:
            return .available
        case .invalidCredentials:
            return .invalidCredentials
        case .invalidModel:
            return .invalidModel
        case .networkIssue:
            return .networkIssue
        case .rateLimited:
            return .rateLimited
        case .serviceIssue:
            return .serviceIssue
        case .unknown:
            return .unknown
        }
    }
}

struct GeminiLLMProvider: LLMProvider {
    let id: LLMProviderID = .gemini
    let capabilities: Set<LLMCapability> = [.textCorrection, .visionOCR]

    private let client: GeminiClient

    init(client: GeminiClient = GeminiClient()) {
        self.client = client
    }

    func checkAccess(configuration: LLMProviderConfiguration) async -> LLMProviderHealth {
        health(from: await client.checkAccessStatus(apiKey: configuration.apiKey, modelID: configuration.modelID))
    }

    func perform(task: LLMTask, configuration: LLMProviderConfiguration) async throws -> LLMResult {
        switch task {
        case .screenOCR(let imageData, let mimeType, let customInstructions):
            let extractedText = try await client.extractMarkdownText(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                imageData: imageData,
                mimeType: mimeType,
                customInstructions: customInstructions
            )
            return .text(extractedText)
        case .grammarCorrection(let text, let customInstructions):
            let correctedText = try await client.correctGrammar(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                customInstructions: customInstructions,
                text: text
            )
            return .text(correctedText)
        }
    }

    private func health(from result: LLMHealthCheckResult) -> LLMProviderHealth {
        LLMProviderHealth(
            providerID: id,
            state: mapHealthState(result.status),
            message: result.message
        )
    }

    private func mapHealthState(_ status: LLMHealthCheckStatus) -> LLMProviderHealthState {
        switch status {
        case .available:
            return .available
        case .invalidCredentials:
            return .invalidCredentials
        case .invalidModel:
            return .invalidModel
        case .networkIssue:
            return .networkIssue
        case .rateLimited:
            return .rateLimited
        case .serviceIssue:
            return .serviceIssue
        case .unknown:
            return .unknown
        }
    }
}
