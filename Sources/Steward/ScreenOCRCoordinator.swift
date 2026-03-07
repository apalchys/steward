import AppKit
import Foundation

@MainActor
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

    private func extractText(
        on screen: NSScreen, selectionRect: CGRect, completion: @escaping (Result<Void, Error>) -> Void
    ) {
        captureService.captureSelectionImageData(on: screen, selectionRect: selectionRect) { [weak self] imageData in
            guard let self else {
                return
            }

            guard let imageData else {
                completion(.failure(ScreenOCRCoordinatorError.couldNotCaptureImage))
                return
            }

            let settings = self.settingsStore.loadSettings()
            let request = LLMRequest(
                providerID: settings.screenshotProviderID,
                task: .screenOCR(
                    imageData: imageData,
                    mimeType: "image/png",
                    customInstructions: self.settingsStore.customScreenshotInstructions()
                )
            )

            self.router.perform(request) { [weak self] result in
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
}
