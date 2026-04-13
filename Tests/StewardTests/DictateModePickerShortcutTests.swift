import AppKit
import XCTest
@testable import Steward

@MainActor
final class DictateModePickerShortcutTests: XCTestCase {
    func testModeNumberUsesKeyCodeForShiftModifiedNumberRowShortcut() {
        let event = makeKeyEvent(
            keyCode: 18,
            modifierFlags: [.shift, .control],
            characters: "!",
            charactersIgnoringModifiers: "!"
        )

        XCTAssertEqual(DictateModePickerShortcut.modeNumber(for: event), 1)
    }

    func testModeNumberSupportsKeypadDigits() {
        let event = makeKeyEvent(
            keyCode: 85,
            modifierFlags: [],
            characters: "3",
            charactersIgnoringModifiers: "3"
        )

        XCTAssertEqual(DictateModePickerShortcut.modeNumber(for: event), 3)
    }

    func testModeNumberRejectsZeroAndNonDigits() {
        let zeroEvent = makeKeyEvent(
            keyCode: 29,
            modifierFlags: [],
            characters: "0",
            charactersIgnoringModifiers: "0"
        )
        let letterEvent = makeKeyEvent(
            keyCode: 0,
            modifierFlags: [],
            characters: "a",
            charactersIgnoringModifiers: "a"
        )

        XCTAssertNil(DictateModePickerShortcut.modeNumber(for: zeroEvent))
        XCTAssertNil(DictateModePickerShortcut.modeNumber(for: letterEvent))
    }

    private func makeKeyEvent(
        keyCode: UInt16,
        modifierFlags: NSEvent.ModifierFlags,
        characters: String,
        charactersIgnoringModifiers: String
    ) -> NSEvent {
        guard let event = NSEvent.keyEvent(
            with: .keyDown,
            location: .zero,
            modifierFlags: modifierFlags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            characters: characters,
            charactersIgnoringModifiers: charactersIgnoringModifiers,
            isARepeat: false,
            keyCode: keyCode
        ) else {
            XCTFail("Failed to create key event")
            fatalError("Failed to create key event")
        }

        return event
    }
}
