import AppKit
import Foundation

@MainActor
protocol CaptureCoordinating: AnyObject {
    var onSelectionActivityChanged: ((Bool) -> Void)? { get set }
    func handleHotKeyPress() async throws
}

@MainActor
final class CaptureCoordinator: CaptureCoordinating {
    var onSelectionActivityChanged: ((Bool) -> Void)?

    private let router: any LLMRouting
    private let textInteraction: any TextInteractionPerforming
    private let captureService: any ScreenCaptureProviding
    private let selectionPresenter: any ScreenSelectionPresenting
    private let settingsStore: any AppSettingsProviding

    init(
        router: any LLMRouting,
        textInteraction: any TextInteractionPerforming,
        captureService: any ScreenCaptureProviding,
        selectionPresenter: any ScreenSelectionPresenting,
        settingsStore: any AppSettingsProviding
    ) {
        self.router = router
        self.textInteraction = textInteraction
        self.captureService = captureService
        self.selectionPresenter = selectionPresenter
        self.settingsStore = settingsStore
    }

    func handleHotKeyPress() async throws {
        guard captureService.ensureScreenCaptureAccess() else {
            throw CaptureCoordinatorError.permissionDenied
        }

        onSelectionActivityChanged?(true)

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
                        continuation.resume(throwing: CaptureCoordinatorError.cancelled)
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
            throw CaptureCoordinatorError.couldNotCaptureImage
        }

        guard let captureRequest = ScreenCaptureRequest(screen: screen) else {
            throw CaptureCoordinatorError.couldNotCaptureImage
        }

        guard
            let imageData = await captureService.captureSelectionImageData(
                request: captureRequest,
                selectionRect: rect
            )
        else {
            throw CaptureCoordinatorError.couldNotCaptureImage
        }

        let settings = settingsStore.loadSettings()
        guard let selection = settings.screenText.selectedModel else {
            throw LLMRouterError.featureNotConfigured(LLMFeature.screenText.displayName)
        }

        let request = LLMRequest(
            selection: selection,
            task: .screenOCR(
                imageData: imageData,
                mimeType: "image/png",
                customInstructions: settings.screenText.customInstructions
            )
        )

        let llmResult = try await router.perform(request)

        guard let extractedText = llmResult.textValue else {
            throw CaptureCoordinatorError.invalidProviderResponse
        }

        textInteraction.copyTextToClipboard(extractedText)
    }
}
