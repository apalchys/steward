import AppKit
import Foundation
import XCTest
@testable import Steward

@MainActor
final class ScreenOCRCoordinatorTests: XCTestCase {
    func testHandleHotKeyPressFailsWhenPermissionDenied() async {
        let router = ScreenFakeRouter(result: .success(.text("ok")))
        let textInteraction = ScreenFakeTextInteraction()
        let captureService = FakeCaptureService(permissionGranted: false, imageData: Data())
        let selectionPresenter = FakeSelectionPresenter()
        let settingsStore = CoordinatorSettingsStore(settings: .empty(), customInstructions: "")
        let coordinator = ScreenOCRCoordinator(
            router: router,
            textInteraction: textInteraction,
            captureService: captureService,
            selectionPresenter: selectionPresenter,
            settingsStore: settingsStore
        )

        do {
            try await coordinator.handleHotKeyPress()
            XCTFail("Expected permission error")
        } catch {
            guard case ScreenOCRCoordinatorError.permissionDenied = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertFalse(selectionPresenter.didBeginSelection)
        }
    }

    func testHandleHotKeyPressPropagatesCancellation() async {
        let router = ScreenFakeRouter(result: .success(.text("ok")))
        let textInteraction = ScreenFakeTextInteraction()
        let captureService = FakeCaptureService(permissionGranted: true, imageData: Data("image".utf8))
        let selectionPresenter = FakeSelectionPresenter(mode: .cancel)
        let settingsStore = CoordinatorSettingsStore(settings: .empty(), customInstructions: "")
        let coordinator = ScreenOCRCoordinator(
            router: router,
            textInteraction: textInteraction,
            captureService: captureService,
            selectionPresenter: selectionPresenter,
            settingsStore: settingsStore
        )

        do {
            try await coordinator.handleHotKeyPress()
            XCTFail("Expected cancellation")
        } catch {
            guard case ScreenOCRCoordinatorError.cancelled = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertTrue(selectionPresenter.didBeginSelection)
            XCTAssertTrue(selectionPresenter.didEndSelection)
        }
    }

    func testHandleHotKeyPressSendsOCRTaskThroughRouterAndCopiesOutput() async throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No screen available in test environment")
        }

        let router = ScreenFakeRouter(result: .success(.text("ocr text")))
        let textInteraction = ScreenFakeTextInteraction()
        let captureService = FakeCaptureService(permissionGranted: true, imageData: Data("image".utf8))
        let selectionPresenter = FakeSelectionPresenter(mode: .finish(screen: screen, rect: CGRect(x: 10, y: 10, width: 120, height: 80)))

        var settings = LLMSettings.empty()
        settings.screenshotProviderID = .openAI
        settings.providerProfiles[.gemini] = LLMProviderProfile(apiKey: "key", modelID: "model")
        let settingsStore = CoordinatorSettingsStore(
            settings: settings,
            customInstructions: "",
            screenshotInstructions: "Keep table structure."
        )

        let coordinator = ScreenOCRCoordinator(
            router: router,
            textInteraction: textInteraction,
            captureService: captureService,
            selectionPresenter: selectionPresenter,
            settingsStore: settingsStore
        )

        try await coordinator.handleHotKeyPress()

        XCTAssertEqual(textInteraction.copiedText, "ocr text")
        guard let request = router.lastRequest else {
            XCTFail("Expected OCR request")
            return
        }

        guard case .screenOCR(_, _, let customInstructions) = request.task else {
            XCTFail("Expected OCR task")
            return
        }
        XCTAssertEqual(request.providerID, .openAI)
        XCTAssertEqual(customInstructions, "Keep table structure.")
        XCTAssertTrue(selectionPresenter.didBeginSelection)
        XCTAssertTrue(selectionPresenter.didEndSelection)
    }

    func testHandleHotKeyPressDismissesOverlayBeforeCapture() async throws {
        guard let screen = NSScreen.screens.first else {
            throw XCTSkip("No screen available in test environment")
        }

        let router = ScreenFakeRouter(result: .success(.text("ocr text")))
        let textInteraction = ScreenFakeTextInteraction()
        let selectionPresenter = FakeSelectionPresenter(
            mode: .finish(screen: screen, rect: CGRect(x: 20, y: 20, width: 80, height: 60))
        )
        let captureService = FakeCaptureService(permissionGranted: true, imageData: Data("image".utf8)) {
            XCTAssertTrue(selectionPresenter.didEndSelection)
        }
        let settingsStore = CoordinatorSettingsStore(settings: .empty(), customInstructions: "")
        let coordinator = ScreenOCRCoordinator(
            router: router,
            textInteraction: textInteraction,
            captureService: captureService,
            selectionPresenter: selectionPresenter,
            settingsStore: settingsStore
        )

        try await coordinator.handleHotKeyPress()

        XCTAssertEqual(captureService.captureCallCount, 1)
        XCTAssertTrue(selectionPresenter.didEndSelection)
    }
}

private final class FakeCaptureService: ScreenCaptureProviding, @unchecked Sendable {
    let permissionGranted: Bool
    let imageData: Data?
    let onCapture: (() -> Void)?
    private(set) var captureCallCount = 0

    init(permissionGranted: Bool, imageData: Data?, onCapture: (() -> Void)? = nil) {
        self.permissionGranted = permissionGranted
        self.imageData = imageData
        self.onCapture = onCapture
    }

    func ensureScreenCaptureAccess() -> Bool {
        permissionGranted
    }

    func captureSelectionImageData(
        request: ScreenCaptureRequest,
        selectionRect: CGRect
    ) async -> Data? {
        captureCallCount += 1
        onCapture?()
        return imageData
    }
}

@MainActor
private final class ScreenFakeRouter: LLMRouting {
    let result: Result<LLMResult, Error>
    var lastRequest: LLMRequest?

    init(result: Result<LLMResult, Error>) {
        self.result = result
    }

    func perform(_ request: LLMRequest) async throws -> LLMResult {
        lastRequest = request
        return try result.get()
    }

    func checkAccess(for providerID: LLMProviderID) async throws -> LLMProviderHealth {
        LLMProviderHealth(providerID: providerID, state: .available, message: "Ready")
    }
}

private final class ScreenFakeTextInteraction: TextInteractionPerforming, @unchecked Sendable {
    var copiedText: String?

    func getSelectedText() async throws -> String? {
        nil
    }

    func replaceSelectedText(with newText: String) async throws {}

    func copyTextToClipboard(_ text: String) {
        copiedText = text
    }
}

private final class FakeSelectionPresenter: ScreenSelectionPresenting {
    enum Mode {
        case finish(screen: NSScreen, rect: CGRect)
        case cancel
    }

    let mode: Mode
    private(set) var didBeginSelection = false
    private(set) var didEndSelection = false

    init(mode: Mode = .cancel) {
        self.mode = mode
    }

    func beginSelection(
        onSelectionFinished: @escaping (NSScreen, CGRect) -> Void,
        onSelectionCancelled: @escaping () -> Void
    ) {
        didBeginSelection = true

        switch mode {
        case .finish(let screen, let rect):
            onSelectionFinished(screen, rect)
        case .cancel:
            onSelectionCancelled()
        }
    }

    func endSelection() async {
        didEndSelection = true
    }
}
