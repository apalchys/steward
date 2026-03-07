import Foundation

@MainActor
final class GrammarCoordinator {
    private let router: LLMRouting
    private let textInteraction: TextInteractionPerforming
    private let settingsStore: LLMSettingsProviding

    init(router: LLMRouting, textInteraction: TextInteractionPerforming, settingsStore: LLMSettingsProviding) {
        self.router = router
        self.textInteraction = textInteraction
        self.settingsStore = settingsStore
    }

    func handleHotKeyPress() async throws {
        guard let selectedText = try await textInteraction.getSelectedText(), !selectedText.isEmpty else {
            throw GrammarCoordinatorError.noSelectedText
        }

        let settings = settingsStore.loadSettings()
        let request = LLMRequest(
            providerID: settings.grammarProviderID,
            task: .grammarCorrection(text: selectedText, customInstructions: settingsStore.customGrammarInstructions())
        )

        let llmResult = try await router.perform(request)

        guard let correctedText = llmResult.textValue else {
            throw GrammarCoordinatorError.invalidProviderResponse
        }

        try await textInteraction.replaceSelectedText(with: correctedText)
    }
}
