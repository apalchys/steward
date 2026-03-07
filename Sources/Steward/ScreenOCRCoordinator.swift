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

        // Local mutable state to bridge the callback-based selection presenter
        // into structured concurrency without instance-level mutable properties.
        // Both the callback and continuation run on @MainActor, so access is safe.
        var selectionScreen: NSScreen?
        var selectionRect: CGRect?

        do {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                selectionPresenter.beginSelection(
                    onSelectionFinished: { screen, rect in
                        selectionScreen = screen
                        selectionRect = rect
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

        guard let screen = selectionScreen, let rect = selectionRect else {
            throw ScreenOCRCoordinatorError.couldNotCaptureImage
        }

        // Extract NSScreen properties into a Sendable struct on @MainActor
        // before crossing into the async capture method.
        guard let captureRequest = ScreenCaptureRequest(screen: screen) else {
            throw ScreenOCRCoordinatorError.couldNotCaptureImage
        }

        guard
            let imageData = await captureService.captureSelectionImageData(
                request: captureRequest, selectionRect: rect)
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
