import Foundation

final class GrammarCoordinator {
    private let router: LLMRouting
    private let textInteraction: TextInteractionPerforming
    private let settingsStore: LLMSettingsProviding

    init(router: LLMRouting, textInteraction: TextInteractionPerforming, settingsStore: LLMSettingsProviding) {
        self.router = router
        self.textInteraction = textInteraction
        self.settingsStore = settingsStore
    }

    func handleHotKeyPress(completion: @escaping (Result<Void, Error>) -> Void) {
        guard let selectedText = textInteraction.getSelectedText(), !selectedText.isEmpty else {
            completion(.failure(GrammarCoordinatorError.noSelectedText))
            return
        }

        let settings = settingsStore.loadSettings()
        let request = LLMRequest(
            task: .grammarCorrection(text: selectedText, customRules: settingsStore.customGrammarRules()),
            featureOverrideProviderID: settings.grammarProviderOverrideID
        )

        router.perform(request) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let llmResult):
                guard let correctedText = llmResult.textValue else {
                    completion(.failure(GrammarCoordinatorError.invalidProviderResponse))
                    return
                }

                self.textInteraction.replaceSelectedText(with: correctedText)
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
