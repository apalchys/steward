import AppKit
import Foundation
import XCTest
@testable import Steward

final class ClipboardMonitorTests: XCTestCase {
    func testPollAcceptsNonEmptyTextWithinSizeLimit() {
        let fakePasteboard = FakePasteboard()
        var acceptedRecords: [ClipboardHistoryRecord] = []
        let monitor = ClipboardMonitor(
            pasteboard: fakePasteboard,
            pollInterval: 60,
            maxRecordSize: 4096,
            suppressionExpiration: 5
        ) { record in
            acceptedRecords.append(record)
        }

        fakePasteboard.currentText = "hello"
        fakePasteboard.changeCount = 1
        monitor.pollPasteboardIfNeeded()

        XCTAssertEqual(acceptedRecords.count, 1)
        XCTAssertEqual(acceptedRecords.first?.text, "hello")
        XCTAssertEqual(acceptedRecords.first?.size, 5)
    }

    func testPollIgnoresOversizedAndEmptyText() {
        let fakePasteboard = FakePasteboard()
        var acceptedRecords: [ClipboardHistoryRecord] = []
        let monitor = ClipboardMonitor(
            pasteboard: fakePasteboard,
            pollInterval: 60,
            maxRecordSize: 4096,
            suppressionExpiration: 5
        ) { record in
            acceptedRecords.append(record)
        }

        fakePasteboard.currentText = ""
        fakePasteboard.changeCount = 1
        monitor.pollPasteboardIfNeeded()

        fakePasteboard.currentText = String(repeating: "a", count: 4097)
        fakePasteboard.changeCount = 2
        monitor.pollPasteboardIfNeeded()

        XCTAssertTrue(acceptedRecords.isEmpty)
    }

    func testSuppressionSkipsConfiguredInternalChange() {
        let fakePasteboard = FakePasteboard()
        var acceptedRecords: [ClipboardHistoryRecord] = []
        let monitor = ClipboardMonitor(
            pasteboard: fakePasteboard,
            pollInterval: 60,
            maxRecordSize: 4096,
            suppressionExpiration: 5
        ) { record in
            acceptedRecords.append(record)
        }

        monitor.suppressNextClipboardChanges(1)
        fakePasteboard.currentText = "internal"
        fakePasteboard.changeCount = 1
        monitor.pollPasteboardIfNeeded()

        fakePasteboard.currentText = "user copy"
        fakePasteboard.changeCount = 2
        monitor.pollPasteboardIfNeeded()

        XCTAssertEqual(acceptedRecords.map(\.text), ["user copy"])
    }

    func testSuppressionStillCapturesWhenUnsuppressedChangesRemainInDelta() {
        let fakePasteboard = FakePasteboard()
        var acceptedRecords: [ClipboardHistoryRecord] = []
        let monitor = ClipboardMonitor(
            pasteboard: fakePasteboard,
            pollInterval: 60,
            maxRecordSize: 4096,
            suppressionExpiration: 5
        ) { record in
            acceptedRecords.append(record)
        }

        monitor.suppressNextClipboardChanges(1)
        fakePasteboard.currentText = "visible text"
        fakePasteboard.changeCount = 2
        monitor.pollPasteboardIfNeeded()

        XCTAssertEqual(acceptedRecords.count, 1)
        XCTAssertEqual(acceptedRecords.first?.text, "visible text")
    }
}

private final class FakePasteboard: ClipboardTextReading {
    var changeCount = 0
    var currentText: String?

    func string(forType dataType: NSPasteboard.PasteboardType) -> String? {
        currentText
    }
}
