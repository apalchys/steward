import Foundation
import StewardCore

struct LLMModelSelection: Equatable, Hashable, Codable {
    let providerID: LLMProviderID
    let modelID: String

    init(providerID: LLMProviderID, modelID: String) {
        self.providerID = providerID
        self.modelID = modelID.trimmed
    }

    var pickerLabel: String {
        "\(providerID.displayName) / \(modelID)"
    }
}

struct LLMProviderModel: Equatable {
    let modelID: String
    let capabilities: Set<LLMFeature>

    init(
        modelID: String,
        capabilities: Set<LLMFeature>
    ) {
        self.modelID = modelID.trimmed
        self.capabilities = capabilities
    }

    func supports(_ feature: LLMFeature) -> Bool {
        capabilities.contains(feature)
    }
}

struct LLMProviderCatalog: Equatable {
    let providerID: LLMProviderID
    let defaultModelID: String
    let models: [LLMProviderModel]

    init(
        providerID: LLMProviderID,
        defaultModelID: String,
        models: [LLMProviderModel]
    ) {
        self.providerID = providerID
        self.defaultModelID = defaultModelID.trimmed
        self.models = models
    }
}

struct LLMModelCatalogEntry: Equatable, Identifiable {
    let providerID: LLMProviderID
    let modelID: String
    let supportedFeatures: Set<LLMFeature>

    var id: String {
        "\(providerID.rawValue):\(modelID)"
    }

    var selection: LLMModelSelection {
        LLMModelSelection(providerID: providerID, modelID: modelID)
    }

    func supports(_ feature: LLMFeature) -> Bool {
        supportedFeatures.contains(feature)
    }

    var capabilitySummary: String {
        supportedFeatures
            .sorted { $0.displayName < $1.displayName }
            .map(\.displayName)
            .joined(separator: ", ")
    }
}

enum LLMModelCatalogValidationError: Error, Equatable, CustomStringConvertible {
    case duplicateModelID(providerID: LLMProviderID, modelID: String)
    case missingDefaultModel(providerID: LLMProviderID, defaultModelID: String)

    var description: String {
        switch self {
        case .duplicateModelID(let providerID, let modelID):
            return "\(providerID.rawValue) duplicates model \(modelID)."
        case .missingDefaultModel(let providerID, let defaultModelID):
            return "\(providerID.rawValue) default model \(defaultModelID) is not in provider models."
        }
    }
}

enum LLMModelCatalog {
    static let providers: [LLMProviderCatalog] = validated([
        LLMProviderCatalog(
            providerID: .openAI,
            defaultModelID: "gpt-5.4",
            models: [
                LLMProviderModel(
                    modelID: "gpt-5.4",
                    capabilities: [.grammar, .screenText]
                ),
                LLMProviderModel(
                    modelID: "gpt-5.4-mini",
                    capabilities: [.grammar, .screenText]
                ),
                LLMProviderModel(
                    modelID: "gpt-4o-mini-transcribe",
                    capabilities: [.voice]
                ),
            ]
        ),
        LLMProviderCatalog(
            providerID: .gemini,
            defaultModelID: "gemini-3.1-flash-lite-preview",
            models: [
                LLMProviderModel(
                    modelID: "gemini-3-flash-preview",
                    capabilities: [.grammar, .screenText, .voice]
                ),
                LLMProviderModel(
                    modelID: "gemini-3.1-flash-lite-preview",
                    capabilities: [.grammar, .screenText, .voice]
                ),
            ]
        ),
    ])

    static var entries: [LLMModelCatalogEntry] {
        providers.flatMap { provider in
            provider.models.map { model in
                LLMModelCatalogEntry(
                    providerID: provider.providerID,
                    modelID: model.modelID,
                    supportedFeatures: model.capabilities
                )
            }
        }
    }

    static func validationErrors(in providers: [LLMProviderCatalog]) -> [LLMModelCatalogValidationError] {
        var errors: [LLMModelCatalogValidationError] = []

        for provider in providers {
            var seenModelIDs = Set<String>()

            for model in provider.models {
                if !seenModelIDs.insert(model.modelID).inserted {
                    errors.append(
                        .duplicateModelID(providerID: provider.providerID, modelID: model.modelID)
                    )
                }
            }

            if !provider.models.contains(where: { $0.modelID == provider.defaultModelID }) {
                errors.append(
                    .missingDefaultModel(
                        providerID: provider.providerID,
                        defaultModelID: provider.defaultModelID
                    )
                )
            }
        }

        return errors
    }

    static func defaultModelID(for providerID: LLMProviderID) -> String {
        guard let provider = provider(for: providerID) else {
            assertionFailure("Unknown provider \(providerID.rawValue)")
            return ""
        }

        return provider.defaultModelID
    }

    static func entries(for providerID: LLMProviderID) -> [LLMModelCatalogEntry] {
        provider(for: providerID)?
            .models
            .map {
                LLMModelCatalogEntry(
                    providerID: providerID,
                    modelID: $0.modelID,
                    supportedFeatures: $0.capabilities
                )
            } ?? []
    }

    static func entries(
        for feature: LLMFeature,
        enabledProviders: Set<LLMProviderID>? = nil
    ) -> [LLMModelCatalogEntry] {
        providers
            .filter { provider in
                enabledProviders.map { $0.contains(provider.providerID) } ?? true
            }
            .flatMap { provider in
                provider.models.compactMap { model in
                    guard model.supports(feature) else {
                        return nil
                    }

                    return LLMModelCatalogEntry(
                        providerID: provider.providerID,
                        modelID: model.modelID,
                        supportedFeatures: model.capabilities
                    )
                }
            }
    }

    static func entry(for selection: LLMModelSelection) -> LLMModelCatalogEntry? {
        guard let model = model(for: selection) else {
            return nil
        }

        return LLMModelCatalogEntry(
            providerID: selection.providerID,
            modelID: model.modelID,
            supportedFeatures: model.capabilities
        )
    }

    static func supports(_ selection: LLMModelSelection, feature: LLMFeature) -> Bool {
        model(for: selection)?.supports(feature) == true
    }

    static func compatibleSelections(
        for feature: LLMFeature,
        enabledProviders: Set<LLMProviderID>
    ) -> [LLMModelSelection] {
        entries(for: feature, enabledProviders: enabledProviders).map(\.selection)
    }

    static func defaultSelection(
        for feature: LLMFeature,
        preferredProviderID: LLMProviderID? = nil,
        enabledProviders: Set<LLMProviderID>
    ) -> LLMModelSelection? {
        if let preferredProviderID,
            enabledProviders.contains(preferredProviderID)
        {
            if let providerDefault = defaultSelection(for: feature, providerID: preferredProviderID) {
                return providerDefault
            }

            if let firstCompatible = firstCompatibleSelection(for: feature, providerID: preferredProviderID) {
                return firstCompatible
            }
        }

        for provider in providers where enabledProviders.contains(provider.providerID) {
            if let providerDefault = defaultSelection(for: feature, providerID: provider.providerID) {
                return providerDefault
            }
        }

        for provider in providers where enabledProviders.contains(provider.providerID) {
            if let firstCompatible = firstCompatibleSelection(for: feature, providerID: provider.providerID) {
                return firstCompatible
            }
        }

        return nil
    }

    static func sanitizedSelection(
        _ selection: LLMModelSelection?,
        for feature: LLMFeature,
        enabledProviders: Set<LLMProviderID>
    ) -> LLMModelSelection? {
        guard let selection else {
            return defaultSelection(for: feature, enabledProviders: enabledProviders)
        }

        if enabledProviders.contains(selection.providerID), supports(selection, feature: feature) {
            return selection
        }

        return defaultSelection(
            for: feature,
            preferredProviderID: selection.providerID,
            enabledProviders: enabledProviders
        )
    }

    private static func validated(_ providers: [LLMProviderCatalog]) -> [LLMProviderCatalog] {
        let errors = validationErrors(in: providers)
        assert(errors.isEmpty, errors.map(\.description).joined(separator: " "))
        return providers
    }

    private static func provider(for providerID: LLMProviderID) -> LLMProviderCatalog? {
        providers.first { $0.providerID == providerID }
    }

    private static func model(for selection: LLMModelSelection) -> LLMProviderModel? {
        provider(for: selection.providerID)?
            .models
            .first { $0.modelID == selection.modelID }
    }

    private static func defaultSelection(
        for feature: LLMFeature,
        providerID: LLMProviderID
    ) -> LLMModelSelection? {
        guard let provider = provider(for: providerID) else {
            return nil
        }

        guard
            let defaultModel = provider.models.first(where: { $0.modelID == provider.defaultModelID }),
            defaultModel.supports(feature)
        else {
            return nil
        }

        return LLMModelSelection(providerID: providerID, modelID: defaultModel.modelID)
    }

    private static func firstCompatibleSelection(
        for feature: LLMFeature,
        providerID: LLMProviderID
    ) -> LLMModelSelection? {
        provider(for: providerID)?
            .models
            .first { $0.supports(feature) }
            .map { LLMModelSelection(providerID: providerID, modelID: $0.modelID) }
    }
}
