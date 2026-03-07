import AppKit
import Foundation

@MainActor
protocol ScreenOCRCoordinating: AnyObject {
    var onSelectionActivityChanged: ((Bool) -> Void)? { get set }
    func handleHotKeyPress() async throws
}

@MainActor
final class ScreenOCRCoordinator: ScreenOCRCoordinating {
    var onSelectionActivityChanged: ((Bool) -> Void)?

    private let router: LLMRouting
    private let textInteraction: TextInteractionPerforming
    private let captureService: ScreenCaptureProviding
    private let selectionPresenter: ScreenSelectionPresenting
    private let settingsStore: AppSettingsProviding

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
        settingsStore: AppSettingsProviding
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

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                selectionPresenter.beginSelection(
                    onSelectionFinished: { [weak self] screen, selectionRect in
                        guard let self else { return }
                        self.pendingSelectionScreen = screen
                        self.pendingSelectionRect = selectionRect
                        continuation.resume()
                    },
                    onSelectionCancelled: {
                        continuation.resume(throwing: ScreenOCRCoordinatorError.cancelled)
                    }
                )
            }
        } catch {
            await selectionPresenter.endSelection()
            onSelectionActivityChanged?(false)
            throw error
        }

        await selectionPresenter.endSelection()
        onSelectionActivityChanged?(false)

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

        guard
            let imageData = await captureService.captureSelectionImageData(
                request: captureRequest, selectionRect: selectionRect)
        else {
            throw ScreenOCRCoordinatorError.couldNotCaptureImage
        }

        let settings = settingsStore.loadSettings()
        let request = LLMRequest(
            providerID: LLMSettings.screenshotProvider,
            task: .screenOCR(
                imageData: imageData,
                mimeType: "image/png",
                customInstructions: settings.screenshotCustomInstructions
            )
        )

        let llmResult = try await router.perform(request)

        guard let extractedText = llmResult.textValue else {
            throw ScreenOCRCoordinatorError.invalidProviderResponse
        }

        textInteraction.copyTextToClipboard(extractedText)
    }
}
