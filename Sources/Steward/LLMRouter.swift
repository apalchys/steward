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
    func resolvedProviderID(
        for capability: LLMCapability,
        featureOverrideProviderID: LLMProviderID?
    ) -> LLMProviderID?
    func checkAccess(
        for capability: LLMCapability,
        featureOverrideProviderID: LLMProviderID?,
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
        let capability = request.task.requiredCapability
        let settings = settingsStore.loadSettings()

        do {
            let providerID = try resolveProviderID(
                for: capability,
                featureOverrideProviderID: request.featureOverrideProviderID,
                settings: settings
            )
            let provider = try providerForID(providerID)
            let configuration = try configuration(for: providerID, from: settings)

            provider.perform(task: request.task, configuration: configuration, completion: completion)
        } catch {
            completion(.failure(error))
        }
    }

    func resolvedProviderID(for capability: LLMCapability, featureOverrideProviderID: LLMProviderID?) -> LLMProviderID? {
        let settings = settingsStore.loadSettings()

        return try? resolveProviderID(
            for: capability,
            featureOverrideProviderID: featureOverrideProviderID,
            settings: settings
        )
    }

    func checkAccess(
        for capability: LLMCapability,
        featureOverrideProviderID: LLMProviderID?,
        completion: @escaping (Result<LLMProviderHealth, Error>) -> Void
    ) {
        let settings = settingsStore.loadSettings()

        do {
            let providerID = try resolveProviderID(
                for: capability,
                featureOverrideProviderID: featureOverrideProviderID,
                settings: settings
            )
            let provider = try providerForID(providerID)
            let configuration = try configuration(for: providerID, from: settings)

            provider.checkAccess(configuration: configuration) { hasAccess in
                completion(.success(LLMProviderHealth(providerID: providerID, hasAccess: hasAccess)))
            }
        } catch {
            completion(.failure(error))
        }
    }

    private func resolveProviderID(
        for capability: LLMCapability,
        featureOverrideProviderID: LLMProviderID?,
        settings: LLMSettings
    ) throws -> LLMProviderID {
        if let featureOverrideProviderID {
            return try validateProvider(
                providerID: featureOverrideProviderID,
                capability: capability,
                settings: settings
            )
        }

        if let globalDefaultProviderID = settings.globalDefaultProviderID,
            (try? validateProvider(providerID: globalDefaultProviderID, capability: capability, settings: settings)) != nil
        {
            return globalDefaultProviderID
        }

        for providerID in supportedProviderIDs {
            if (try? validateProvider(providerID: providerID, capability: capability, settings: settings)) != nil {
                return providerID
            }
        }

        throw LLMRouterError.noConfiguredProvider(capability)
    }

    @discardableResult
    private func validateProvider(
        providerID: LLMProviderID,
        capability: LLMCapability,
        settings: LLMSettings
    ) throws -> LLMProviderID {
        let provider = try providerForID(providerID)

        guard provider.capabilities.contains(capability) else {
            throw LLMRouterError.providerDoesNotSupportCapability(providerID: providerID, capability: capability)
        }

        guard settings.configuration(for: providerID) != nil else {
            throw LLMRouterError.providerNotConfigured(providerID)
        }

        return providerID
    }

    private func providerForID(_ providerID: LLMProviderID) throws -> LLMProvider {
        guard let provider = providers[providerID] else {
            throw LLMRouterError.providerNotRegistered(providerID)
        }

        return provider
    }

    private func configuration(for providerID: LLMProviderID, from settings: LLMSettings) throws -> LLMProviderConfiguration {
        guard let configuration = settings.configuration(for: providerID) else {
            throw LLMRouterError.providerNotConfigured(providerID)
        }

        return configuration
    }
}

struct OpenAILLMProvider: LLMProvider {
    let id: LLMProviderID = .openAI
    let capabilities: Set<LLMCapability> = [.textCorrection]

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
        case .grammarCorrection(let text, let customRules):
            client.correctGrammar(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                customRules: customRules,
                text: text
            ) { result in
                completion(result.map(LLMResult.text))
            }
        case .screenOCR:
            completion(.failure(LLMProviderError.unsupportedTask(providerID: id)))
        }
    }
}

struct GeminiLLMProvider: LLMProvider {
    let id: LLMProviderID = .gemini
    let capabilities: Set<LLMCapability> = [.visionOCR]

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
        case .screenOCR(let imageData, let mimeType):
            client.extractMarkdownText(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                imageData: imageData,
                mimeType: mimeType
            ) { result in
                completion(result.map(LLMResult.text))
            }
        case .grammarCorrection:
            completion(.failure(LLMProviderError.unsupportedTask(providerID: id)))
        }
    }
}

struct OpenAICompatibleLLMProvider: LLMProvider {
    let id: LLMProviderID = .openAICompatible
    let capabilities: Set<LLMCapability> = [.textCorrection]

    private let callbackQueue: DispatchQueue
    private let session: URLSession

    init(session: URLSession = .shared, callbackQueue: DispatchQueue = .main) {
        self.session = session
        self.callbackQueue = callbackQueue
    }

    func checkAccess(configuration: LLMProviderConfiguration, completion: @escaping (Bool) -> Void) {
        guard let baseURL = configuration.baseURL, !baseURL.trimmed.isEmpty else {
            completion(false)
            return
        }

        let client = OpenAIClient(session: session, callbackQueue: callbackQueue, apiBaseURL: baseURL)
        client.checkAccess(apiKey: configuration.apiKey, modelID: configuration.modelID, completion: completion)
    }

    func perform(
        task: LLMTask,
        configuration: LLMProviderConfiguration,
        completion: @escaping (Result<LLMResult, Error>) -> Void
    ) {
        guard let baseURL = configuration.baseURL, !baseURL.trimmed.isEmpty else {
            completion(.failure(LLMProviderError.missingBaseURL))
            return
        }

        let client = OpenAIClient(session: session, callbackQueue: callbackQueue, apiBaseURL: baseURL)

        switch task {
        case .grammarCorrection(let text, let customRules):
            client.correctGrammar(
                apiKey: configuration.apiKey,
                modelID: configuration.modelID,
                customRules: customRules,
                text: text
            ) { result in
                completion(result.map(LLMResult.text))
            }
        case .screenOCR:
            completion(.failure(LLMProviderError.unsupportedTask(providerID: id)))
        }
    }
}
