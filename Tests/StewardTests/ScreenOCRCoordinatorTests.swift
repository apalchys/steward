import AppKit
import Foundation
import XCTest
@testable import Steward

@MainActor
final class ScreenOCRCoordinatorTests: XCTestCase {
    func testHandleHotKeyPressFailsWhenPermissionDenied() {
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

        let result: Result<Void, Error> = waitForValue(timeout: 2) { completion in
            coordinator.handleHotKeyPress(completion: completion)
        }

        switch result {
        case .success:
            XCTFail("Expected permission error")
        case .failure(let error):
            guard case ScreenOCRCoordinatorError.permissionDenied = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertFalse(selectionPresenter.didBeginSelection)
        }
    }

    func testHandleHotKeyPressPropagatesCancellation() {
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

        let result: Result<Void, Error> = waitForValue(timeout: 2) { completion in
            coordinator.handleHotKeyPress(completion: completion)
        }

        switch result {
        case .success:
            XCTFail("Expected cancellation")
        case .failure(let error):
            guard case ScreenOCRCoordinatorError.cancelled = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
            XCTAssertTrue(selectionPresenter.didBeginSelection)
            XCTAssertTrue(selectionPresenter.didEndSelection)
        }
    }

    func testHandleHotKeyPressSendsOCRTaskThroughRouterAndCopiesOutput() throws {
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

        let result: Result<Void, Error> = waitForValue(timeout: 2) { completion in
            coordinator.handleHotKeyPress(completion: completion)
        }

        switch result {
        case .success:
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
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }
}

private final class FakeCaptureService: ScreenCaptureProviding {
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
        on screen: NSScreen,
        selectionRect: CGRect,
        completion: @escaping (Data?) -> Void
    ) {
        completion(imageData)
    }
}

private final class ScreenFakeRouter: LLMRouting {
    var supportedProviderIDs: [LLMProviderID] = [.gemini]
    var result: Result<LLMResult, Error>
    var lastRequest: LLMRequest?

    init(result: Result<LLMResult, Error>) {
        self.result = result
    }

    func perform(_ request: LLMRequest, completion: @escaping (Result<LLMResult, Error>) -> Void) {
        lastRequest = request
        completion(result)
    }

    func checkAccess(
        for providerID: LLMProviderID,
        completion: @escaping (Result<LLMProviderHealth, Error>) -> Void
    ) {
        completion(.success(LLMProviderHealth(providerID: providerID, hasAccess: true)))
    }
}

private final class ScreenFakeTextInteraction: TextInteractionPerforming {
    var copiedText: String?

    func getSelectedText() -> String? {
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
