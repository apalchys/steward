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
        settings.providerProfiles[.gemini] = LLMProviderProfile(apiKey: "key", modelID: "model", baseURL: "")
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
}

private final class FakeCaptureService: ScreenCaptureProviding, @unchecked Sendable {
    let permissionGranted: Bool
    let imageData: Data?

    init(permissionGranted: Bool, imageData: Data?) {
        self.permissionGranted = permissionGranted
        self.imageData = imageData
    }

    func ensureScreenCaptureAccess() -> Bool {
        permissionGranted
    }

    func captureSelectionImageData(
        request: ScreenCaptureRequest,
        selectionRect: CGRect
    ) async -> Data? {
        imageData
    }
}

private final class ScreenFakeRouter: LLMRouting, @unchecked Sendable {
    let supportedProviderIDs: [LLMProviderID] = [.gemini]
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
        LLMProviderHealth(providerID: providerID, hasAccess: true)
    }
}

private final class ScreenFakeTextInteraction: TextInteractionPerforming, @unchecked Sendable {
    var copiedText: String?

    func getSelectedText() async -> String? {
        nil
    }

    func replaceSelectedText(with newText: String) {}

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

    func endSelection() {
        didEndSelection = true
    }
}
