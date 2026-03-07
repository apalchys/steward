import AppKit
import XCTest
@testable import Steward

@MainActor
final class TextInteractionServiceTests: XCTestCase {
    func testGetSelectedTextPrefersAccessibilityValue() async throws {
        let pasteboard = FakePasteboard(initialText: "clipboard")
        let accessibility = FakeAccessibilityTextInteraction(selectedTextValue: "ax selection")
        let eventPoster = FakeEventPoster()
        let service = SystemTextInteractionService(
            pasteboard: pasteboard,
            suppression: nil,
            accessibilityTextInteraction: accessibility,
            eventPoster: eventPoster,
            sleeper: { _ in }
        )

        let selectedText = try await service.getSelectedText()

        XCTAssertEqual(selectedText, "ax selection")
        XCTAssertEqual(eventPoster.copyCommandCount, 0)
        XCTAssertEqual(pasteboard.currentText, "clipboard")
    }

    func testGetSelectedTextFallsBackToClipboardAndRestoresOriginalContents() async throws {
        let pasteboard = FakePasteboard(initialText: "original clipboard")
        let suppression = FakeClipboardChangeSuppressor()
        let accessibility = FakeAccessibilityTextInteraction(selectedTextValue: nil)
        let eventPoster = FakeEventPoster {
            pasteboard.setExternalText("selected via copy")
        }
        let service = SystemTextInteractionService(
            pasteboard: pasteboard,
            suppression: suppression,
            accessibilityTextInteraction: accessibility,
            eventPoster: eventPoster,
            sleeper: { _ in }
        )

        let selectedText = try await service.getSelectedText()

        XCTAssertEqual(selectedText, "selected via copy")
        XCTAssertEqual(pasteboard.currentText, "original clipboard")
        XCTAssertEqual(eventPoster.copyCommandCount, 1)
        XCTAssertEqual(suppression.suppressedCounts, [1, 2])
    }

    func testReplaceSelectedTextFallbackDoesNotOverwriteUserClipboardChange() async throws {
        let pasteboard = FakePasteboard(initialText: "original clipboard")
        let accessibility = FakeAccessibilityTextInteraction(selectedTextValue: nil, replaceSucceeds: false)
        let eventPoster = FakeEventPoster()
        let service = SystemTextInteractionService(
            pasteboard: pasteboard,
            suppression: nil,
            accessibilityTextInteraction: accessibility,
            eventPoster: eventPoster,
            sleeper: { _ in
                pasteboard.setExternalText("user changed clipboard")
            }
        )

        try await service.replaceSelectedText(with: "corrected text")

        XCTAssertEqual(eventPoster.pasteCommandCount, 1)
        XCTAssertEqual(pasteboard.currentText, "user changed clipboard")
    }

    func testGetSelectedTextThrowsWhenAccessibilityPermissionIsMissing() async {
        let pasteboard = FakePasteboard(initialText: "clipboard")
        let accessibility = FakeAccessibilityTextInteraction(isTrusted: false)
        let service = SystemTextInteractionService(
            pasteboard: pasteboard,
            suppression: nil,
            accessibilityTextInteraction: accessibility,
            eventPoster: FakeEventPoster(),
            sleeper: { _ in }
        )

        do {
            _ = try await service.getSelectedText()
            XCTFail("Expected accessibility permission error")
        } catch {
            guard case TextInteractionError.accessibilityPermissionDenied = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }
        }
    }
}

private final class FakePasteboard: PasteboardControlling, @unchecked Sendable {
    private(set) var changeCount: Int
    private(set) var currentText: String?

    init(initialText: String?, changeCount: Int = 1) {
        self.currentText = initialText
        self.changeCount = changeCount
    }

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        currentText
    }

    @discardableResult
    func clearContents() -> Int {
        currentText = nil
        changeCount += 1
        return changeCount
    }

    @discardableResult
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool {
        currentText = string
        changeCount += 1
        return true
    }

    func setExternalText(_ text: String?) {
        currentText = text
        changeCount += 1
    }
}

@MainActor
private final class FakeClipboardChangeSuppressor: ClipboardChangeSuppressing {
    private(set) var suppressedCounts: [Int] = []

    func suppressNextClipboardChanges(_ count: Int) {
        suppressedCounts.append(count)
    }
}

private struct FakeAccessibilityTextInteraction: AccessibilityTextInteracting {
    var isTrusted: Bool = true
    var selectedTextValue: String?
    var replaceSucceeds: Bool = true

    func isProcessTrusted() -> Bool {
        isTrusted
    }

    func selectedText() -> String? {
        selectedTextValue
    }

    func replaceSelectedText(with newText: String) -> Bool {
        replaceSucceeds
    }
}

private final class FakeEventPoster: TextInteractionEventPosting {
    private let onCopy: () -> Void
    private let onPaste: () -> Void

    private(set) var copyCommandCount = 0
    private(set) var pasteCommandCount = 0

    init(onCopy: @escaping () -> Void = {}, onPaste: @escaping () -> Void = {}) {
        self.onCopy = onCopy
        self.onPaste = onPaste
    }

    func postCopyCommand() {
        copyCommandCount += 1
        onCopy()
    }

    func postPasteCommand() {
        pasteCommandCount += 1
        onPaste()
    }
}
