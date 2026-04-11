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

enum LLMModelCatalog {
    static let entries: [LLMModelCatalogEntry] = [
        LLMModelCatalogEntry(
            providerID: .openAI,
            modelID: OpenAIClient.defaultModelID,
            supportedFeatures: [.grammar]
        ),
        LLMModelCatalogEntry(
            providerID: .gemini,
            modelID: GeminiClient.defaultModelID,
            supportedFeatures: [.grammar, .screenText, .voice]
        ),
        LLMModelCatalogEntry(
            providerID: .openAI,
            modelID: "gpt-4o-mini-transcribe",
            supportedFeatures: [.voice]
        ),
    ]

    static func entries(for providerID: LLMProviderID) -> [LLMModelCatalogEntry] {
        entries.filter { $0.providerID == providerID }
    }

    static func entries(
        for feature: LLMFeature,
        enabledProviders: Set<LLMProviderID>? = nil
    ) -> [LLMModelCatalogEntry] {
        entries.filter { entry in
            entry.supports(feature)
                && (enabledProviders.map { $0.contains(entry.providerID) } ?? true)
        }
    }

    static func entry(for selection: LLMModelSelection) -> LLMModelCatalogEntry? {
        entries.first { $0.providerID == selection.providerID && $0.modelID == selection.modelID }
    }

    static func supports(_ selection: LLMModelSelection, feature: LLMFeature) -> Bool {
        entry(for: selection)?.supports(feature) == true
    }

    static func compatibleSelections(
        for feature: LLMFeature,
        enabledProviders: Set<LLMProviderID>
    ) -> [LLMModelSelection] {
        entries(for: feature, enabledProviders: enabledProviders).map(\.selection)
    }

    static func fallbackSelection(
        for feature: LLMFeature,
        preferredProviderID: LLMProviderID? = nil,
        enabledProviders: Set<LLMProviderID>
    ) -> LLMModelSelection? {
        let compatibleSelections = compatibleSelections(for: feature, enabledProviders: enabledProviders)

        if let preferredProviderID,
            let providerSpecificFallback = compatibleSelections.first(where: { $0.providerID == preferredProviderID })
        {
            return providerSpecificFallback
        }

        return compatibleSelections.first
    }

    static func sanitizedSelection(
        _ selection: LLMModelSelection?,
        for feature: LLMFeature,
        enabledProviders: Set<LLMProviderID>
    ) -> LLMModelSelection? {
        guard let selection else {
            return fallbackSelection(for: feature, enabledProviders: enabledProviders)
        }

        if enabledProviders.contains(selection.providerID), supports(selection, feature: feature) {
            return selection
        }

        return fallbackSelection(
            for: feature,
            preferredProviderID: selection.providerID,
            enabledProviders: enabledProviders
        )
    }
}
