import Foundation
import XCTest
@testable import Steward

final class ClipboardHistorySearchTests: XCTestCase {
    func testFilterReturnsAllRecordsForEmptyQuery() {
        let records = makeRecords()

        XCTAssertEqual(ClipboardHistorySearch.filter(records: records, query: ""), records)
        XCTAssertEqual(ClipboardHistorySearch.filter(records: records, query: "   "), records)
    }

    func testFilterMatchesCaseInsensitiveSubstringAcrossEntries() {
        let records = makeRecords()

        let filtered = ClipboardHistorySearch.filter(records: records, query: "alpHA")

        XCTAssertEqual(filtered.map(\.text), ["Alpha one", "third alpha line"])
    }

    func testFilterReturnsEmptyWhenNoEntriesMatch() {
        let records = makeRecords()

        let filtered = ClipboardHistorySearch.filter(records: records, query: "missing")

        XCTAssertTrue(filtered.isEmpty)
    }

    private func makeRecords() -> [ClipboardHistoryRecord] {
        [
            ClipboardHistoryRecord(
                id: UUID(),
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
                text: "Alpha one"
            ),
            ClipboardHistoryRecord(
                id: UUID(),
                capturedAt: Date(timeIntervalSince1970: 1_700_000_100),
                text: "Beta two"
            ),
            ClipboardHistoryRecord(
                id: UUID(),
                capturedAt: Date(timeIntervalSince1970: 1_700_000_200),
                text: "third alpha line"
            ),
        ]
    }
}
