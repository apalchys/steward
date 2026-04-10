import AppKit
import XCTest
@testable import Steward

@MainActor
final class VoiceRecordingPillTests: XCTestCase {
    func testShowRecordingUpdatesStateAndShowsWindow() {
        let window = FakeVoiceRecordingPillWindow()
        let screen = NSScreen.main ?? NSScreen.screens.first
        let controller = VoiceRecordingPillController(
            windowFactory: { window },
            screenProvider: { screen }
        )

        controller.showRecording(level: 1.4)

        XCTAssertEqual(controller.currentState, .recording(level: 1))
        XCTAssertEqual(window.orderFrontRegardlessCallCount, 1)
    }

    func testShowTranscribingUpdatesStateAndShowsWindow() {
        let window = FakeVoiceRecordingPillWindow()
        let controller = VoiceRecordingPillController(
            windowFactory: { window },
            screenProvider: { NSScreen.main ?? NSScreen.screens.first }
        )

        controller.showTranscribing()

        XCTAssertEqual(controller.currentState, .transcribing)
        XCTAssertEqual(window.orderFrontRegardlessCallCount, 1)
    }

    func testHideOrdersWindowOut() {
        let window = FakeVoiceRecordingPillWindow()
        let controller = VoiceRecordingPillController(
            windowFactory: { window },
            screenProvider: { NSScreen.main ?? NSScreen.screens.first }
        )

        controller.showRecording(level: 0.3)
        controller.hide()

        XCTAssertEqual(window.orderOutCallCount, 1)
    }

    func testViewModelInvokesCallbacks() {
        let model = VoiceRecordingPillViewModel()
        var cancelCount = 0
        var confirmCount = 0
        model.onCancel = { cancelCount += 1 }
        model.onConfirm = { confirmCount += 1 }

        model.handleCancel()
        model.handleConfirm()

        XCTAssertEqual(cancelCount, 1)
        XCTAssertEqual(confirmCount, 1)
    }
}

@MainActor
private final class FakeVoiceRecordingPillWindow: VoiceRecordingPillWindowing {
    var contentView: NSView?
    var isVisible = false
    private(set) var frame: NSRect?
    private(set) var orderFrontRegardlessCallCount = 0
    private(set) var orderOutCallCount = 0

    func setFrame(_ frame: NSRect, display: Bool) {
        self.frame = frame
    }

    func orderFrontRegardless() {
        isVisible = true
        orderFrontRegardlessCallCount += 1
    }

    func orderOut(_ sender: Any?) {
        isVisible = false
        orderOutCallCount += 1
    }
}
