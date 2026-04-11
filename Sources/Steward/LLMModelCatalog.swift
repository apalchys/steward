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
    let defaultCapabilities: Set<LLMFeature>

    init(
        modelID: String,
        capabilities: Set<LLMFeature>,
        defaultCapabilities: Set<LLMFeature> = []
    ) {
        self.modelID = modelID.trimmed
        self.capabilities = capabilities
        self.defaultCapabilities = defaultCapabilities
    }

    func supports(_ feature: LLMFeature) -> Bool {
        capabilities.contains(feature)
    }

    func isDefault(for feature: LLMFeature) -> Bool {
        defaultCapabilities.contains(feature)
    }
}

struct LLMProviderCatalog: Equatable {
    let providerID: LLMProviderID
    let models: [LLMProviderModel]
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
    case invalidDefaultCapability(providerID: LLMProviderID, modelID: String, feature: LLMFeature)
    case duplicateDefault(providerID: LLMProviderID, feature: LLMFeature, modelIDs: [String])

    var description: String {
        switch self {
        case .duplicateModelID(let providerID, let modelID):
            return "\(providerID.rawValue) duplicates model \(modelID)."
        case .invalidDefaultCapability(let providerID, let modelID, let feature):
            return "\(providerID.rawValue) marks \(modelID) default for unsupported \(feature.rawValue)."
        case .duplicateDefault(let providerID, let feature, let modelIDs):
            return "\(providerID.rawValue) has multiple defaults for \(feature.rawValue): \(modelIDs.joined(separator: ", "))."
        }
    }
}

enum LLMModelCatalog {
    static let providers: [LLMProviderCatalog] = validated([
        LLMProviderCatalog(
            providerID: .openAI,
            models: [
                LLMProviderModel(
                    modelID: OpenAIClient.defaultModelID,
                    capabilities: [.grammar, .screenText],
                    defaultCapabilities: [.grammar]
                ),
                LLMProviderModel(
                    modelID: "gpt-4o-mini-transcribe",
                    capabilities: [.voice],
                    defaultCapabilities: [.voice]
                ),
            ]
        ),
        LLMProviderCatalog(
            providerID: .gemini,
            models: [
                LLMProviderModel(
                    modelID: "gemini-3-flash-preview",
                    capabilities: [.grammar, .screenText, .voice]
                ),
                LLMProviderModel(
                    modelID: GeminiClient.defaultModelID,
                    capabilities: [.grammar, .screenText, .voice],
                    defaultCapabilities: [.grammar, .screenText, .voice]
                )
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
            var defaultModelsByFeature: [LLMFeature: [String]] = [:]

            for model in provider.models {
                if !seenModelIDs.insert(model.modelID).inserted {
                    errors.append(
                        .duplicateModelID(providerID: provider.providerID, modelID: model.modelID)
                    )
                }

                for feature in model.defaultCapabilities {
                    guard model.capabilities.contains(feature) else {
                        errors.append(
                            .invalidDefaultCapability(
                                providerID: provider.providerID,
                                modelID: model.modelID,
                                feature: feature
                            )
                        )
                        continue
                    }

                    defaultModelsByFeature[feature, default: []].append(model.modelID)
                }
            }

            for (feature, modelIDs) in defaultModelsByFeature where modelIDs.count > 1 {
                errors.append(
                    .duplicateDefault(
                        providerID: provider.providerID,
                        feature: feature,
                        modelIDs: modelIDs
                    )
                )
            }
        }

        return errors
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
        provider(for: providerID)?
            .models
            .first { $0.isDefault(for: feature) }
            .map { LLMModelSelection(providerID: providerID, modelID: $0.modelID) }
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
