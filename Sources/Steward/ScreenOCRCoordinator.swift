import AppKit
import Foundation

final class ScreenOCRCoordinator {
    var onSelectionActivityChanged: ((Bool) -> Void)?

    private let router: LLMRouting
    private let textInteraction: TextInteractionPerforming
    private let captureService: ScreenCaptureProviding
    private let selectionPresenter: ScreenSelectionPresenting
    private let settingsStore: LLMSettingsProviding

    init(
        router: LLMRouting,
        textInteraction: TextInteractionPerforming,
        captureService: ScreenCaptureProviding,
        selectionPresenter: ScreenSelectionPresenting,
        settingsStore: LLMSettingsProviding
    ) {
        self.router = router
        self.textInteraction = textInteraction
        self.captureService = captureService
        self.selectionPresenter = selectionPresenter
        self.settingsStore = settingsStore
    }

    func handleHotKeyPress(completion: @escaping (Result<Void, Error>) -> Void) {
        guard captureService.ensureScreenCaptureAccess() else {
            completion(.failure(ScreenOCRCoordinatorError.permissionDenied))
            return
        }

        onSelectionActivityChanged?(true)

        selectionPresenter.beginSelection(
            onSelectionFinished: { [weak self] screen, selectionRect in
                guard let self else {
                    return
                }

                self.selectionPresenter.endSelection()
                self.onSelectionActivityChanged?(false)

                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    self.extractText(on: screen, selectionRect: selectionRect, completion: completion)
                }
            },
            onSelectionCancelled: { [weak self] in
                guard let self else {
                    return
                }

                self.selectionPresenter.endSelection()
                self.onSelectionActivityChanged?(false)
                completion(.failure(ScreenOCRCoordinatorError.cancelled))
            }
        )
    }

    private func extractText(on screen: NSScreen, selectionRect: CGRect, completion: @escaping (Result<Void, Error>) -> Void) {
        guard let imageData = captureService.captureSelectionImageData(on: screen, selectionRect: selectionRect) else {
            completion(.failure(ScreenOCRCoordinatorError.couldNotCaptureImage))
            return
        }

        let settings = settingsStore.loadSettings()
        let request = LLMRequest(
            task: .screenOCR(imageData: imageData, mimeType: "image/png"),
            featureOverrideProviderID: settings.ocrProviderOverrideID
        )

        router.perform(request) { [weak self] result in
            guard let self else {
                return
            }

            switch result {
            case .success(let llmResult):
                guard let extractedText = llmResult.textValue else {
                    completion(.failure(ScreenOCRCoordinatorError.invalidProviderResponse))
                    return
                }

                self.textInteraction.copyTextToClipboard(extractedText)
                completion(.success(()))
            case .failure(let error):
                completion(.failure(error))
            }
        }
    }
}
