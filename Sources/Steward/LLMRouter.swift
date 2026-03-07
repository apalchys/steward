import Foundation
import StewardCore

protocol LLMProvider {
    var id: LLMProviderID { get }
    var capabilities: Set<LLMCapability> { get }

    func checkAccess(configuration: LLMProviderConfiguration, completion: @escaping (Bool) -> Void)
    func perform(
        task: LLMTask,
        configuration: LLMProviderConfiguration,
        completion: @escaping (Result<LLMResult, Error>) -> Void
    )
}

protocol LLMRouting {
    var supportedProviderIDs: [LLMProviderID] { get }

    func perform(_ request: LLMRequest, completion: @escaping (Result<LLMResult, Error>) -> Void)
    func checkAccess(
        for providerID: LLMProviderID,
        completion: @escaping (Result<LLMProviderHealth, Error>) -> Void
    )
}

final class LLMRouter: LLMRouting {
    let supportedProviderIDs: [LLMProviderID]

    private let providers: [LLMProviderID: LLMProvider]
    private let settingsStore: LLMSettingsProviding

    init(providers: [LLMProvider], settingsStore: LLMSettingsProviding) {
        let providerMap = Dictionary(uniqueKeysWithValues: providers.map { ($0.id, $0) })
        self.providers = providerMap
        self.settingsStore = settingsStore
        self.supportedProviderIDs = LLMProviderID.allCases.filter { providerMap[$0] != nil }
    }

    func perform(_ request: LLMRequest, completion: @escaping (Result<LLMResult, Error>) -> Void) {
        let settings = settingsStore.loadSettings()

        do {
            let providerID = request.providerID
            let provider = try providerForID(providerID)
            let configuration = try configuration(for: providerID, from: settings)
            let capability = request.task.requiredCapability

            guard provider.capabilities.contains(capability) else {
                throw LLMRouterError.providerDoesNotSupportCapability(providerID: providerID, capability: capability)
            }

            provider.perform(task: request.task, configuration: configuration, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func checkAccess(
        for providerID: LLMProviderID,
        completion: @escaping (Result<LLMProviderHealth, Error>) -> Void
    ) {
        let settings = settingsStore.loadSettings()

        do {
            let provider = try providerForID(providerID)
            let configuration = try configuration(for: providerID, from: settings)

            provider.checkAccess(configuration: configuration) { hasAccess in
                completion(.success(LLMProviderHealth(providerID: providerID, hasAccess: hasAccess)))
            }
        } catch {
            completion(.failure(error))
        }
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

    func checkAccess(configuration: LLMProviderConfiguration, completion: @escaping (Bool) -> Void) {
        client.checkAccess(apiKey: configuration.apiKey, modelID: configuration.modelID, completion: completion)
    }

    func perform(
        task: LLMTask,
        configuration: LLMProviderConfiguration,
        completion: @escaping (Result<LLMResult, Error>) -> Void
    ) {
        switch task {
        case .grammarCorrection(let text, let customInstructions):
            client.correctGrammar(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                customInstructions: customInstructions,
                text: text
            ) { result in
                completion(result.map(LLMResult.text))
            }
        case .screenOCR(let imageData, let mimeType, let customInstructions):
            client.extractMarkdownText(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                imageData: imageData,
                mimeType: mimeType,
                customInstructions: customInstructions
            ) { result in
                completion(result.map(LLMResult.text))
            }
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

    func checkAccess(configuration: LLMProviderConfiguration, completion: @escaping (Bool) -> Void) {
        client.checkAccess(apiKey: configuration.apiKey, modelID: configuration.modelID, completion: completion)
    }

    func perform(
        task: LLMTask,
        configuration: LLMProviderConfiguration,
        completion: @escaping (Result<LLMResult, Error>) -> Void
    ) {
        switch task {
        case .screenOCR(let imageData, let mimeType, let customInstructions):
            client.extractMarkdownText(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                imageData: imageData,
                mimeType: mimeType,
                customInstructions: customInstructions
            ) { result in
                completion(result.map(LLMResult.text))
            }
        case .grammarCorrection(let text, let customInstructions):
            client.correctGrammar(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                customInstructions: customInstructions,
                text: text
            ) { result in
                completion(result.map(LLMResult.text))
            }
        }
    }
}
