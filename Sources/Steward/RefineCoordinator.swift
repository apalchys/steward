import Foundation

@MainActor
protocol RefineCoordinating: AnyObject {
    func handleHotKeyPress() async throws
}

@MainActor
final class RefineCoordinator: RefineCoordinating {
    private let router: LLMRouting
    private let textInteraction: TextInteractionPerforming
    private let settingsStore: AppSettingsProviding

    init(router: LLMRouting, textInteraction: TextInteractionPerforming, settingsStore: AppSettingsProviding) {
        self.router = router
        self.textInteraction = textInteraction
        self.settingsStore = settingsStore
    }

    func handleHotKeyPress() async throws {
        guard let selectedText = try await textInteraction.getSelectedText(), !selectedText.isEmpty else {
            throw RefineCoordinatorError.noSelectedText
        }

        let settings = settingsStore.loadSettings()
        guard let selection = settings.refine.selectedModel else {
            throw LLMRouterError.featureNotConfigured(LLMFeature.refine.displayName)
        }

        let request = LLMRequest(
            selection: selection,
            task: .refineText(
                text: selectedText,
                customInstructions: settings.refine.customInstructions
            )
        )

        let llmResult = try await router.perform(request)

        guard let correctedText = llmResult.textValue else {
            throw RefineCoordinatorError.invalidProviderResponse
        }

        try await textInteraction.replaceSelectedText(with: correctedText)
    }
}
