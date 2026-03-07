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

    // Temporary storage for the selection result, used to bridge the
    // @MainActor selection presenter callback into structured concurrency
    // without sending non-Sendable NSScreen across isolation boundaries.
    private var pendingSelectionScreen: NSScreen?
    private var pendingSelectionRect: CGRect?

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

    func handleHotKeyPress() async throws {
        guard captureService.ensureScreenCaptureAccess() else {
            throw ScreenOCRCoordinatorError.permissionDenied
        }

        onSelectionActivityChanged?(true)

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            selectionPresenter.beginSelection(
                onSelectionFinished: { [weak self] screen, selectionRect in
                    guard let self else { return }
                    self.selectionPresenter.endSelection()
                    self.onSelectionActivityChanged?(false)
                    self.pendingSelectionScreen = screen
                    self.pendingSelectionRect = selectionRect
                    continuation.resume()
                },
                onSelectionCancelled: { [weak self] in
                    guard let self else { return }
                    self.selectionPresenter.endSelection()
                    self.onSelectionActivityChanged?(false)
                    continuation.resume(throwing: ScreenOCRCoordinatorError.cancelled)
                }
            )
        }

        guard let screen = pendingSelectionScreen, let selectionRect = pendingSelectionRect else {
            throw ScreenOCRCoordinatorError.couldNotCaptureImage
        }
        pendingSelectionScreen = nil
        pendingSelectionRect = nil

        // Extract NSScreen properties into a Sendable struct on @MainActor
        // before crossing into the async capture method.
        guard let captureRequest = ScreenCaptureRequest(screen: screen) else {
            throw ScreenOCRCoordinatorError.couldNotCaptureImage
        }

        // Brief delay to allow the overlay window to dismiss before capturing the screen.
        try await Task.sleep(for: .milliseconds(100))

        guard
            let imageData = await captureService.captureSelectionImageData(
                request: captureRequest, selectionRect: selectionRect)
        else {
            throw ScreenOCRCoordinatorError.couldNotCaptureImage
        }

        let settings = settingsStore.loadSettings()
        let request = LLMRequest(
            providerID: settings.screenshotProviderID,
            task: .screenOCR(
                imageData: imageData,
                mimeType: "image/png",
                customInstructions: settingsStore.customScreenshotInstructions()
            )
        )

        let llmResult = try await router.perform(request)

        guard let extractedText = llmResult.textValue else {
            throw ScreenOCRCoordinatorError.invalidProviderResponse
        }

        textInteraction.copyTextToClipboard(extractedText)
    }
}
