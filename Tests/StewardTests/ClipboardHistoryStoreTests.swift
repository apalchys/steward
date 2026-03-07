import Foundation
import XCTest
@testable import Steward

final class ClipboardHistoryStoreTests: XCTestCase {
    private var temporaryDirectoryURL: URL!
    private var historyFileURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("StewardTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
        historyFileURL = temporaryDirectoryURL.appendingPathComponent("clipboard-history.jsonl", isDirectory: false)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
        historyFileURL = nil
        try super.tearDownWithError()
    }

    func testAppendAndReloadPersistsRecords() throws {
        let store = makeStore()
        waitForStoreOperation("load") { done in store.load(completion: done) }

        let firstRecord = ClipboardHistoryRecord(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: "hello"
        )
        let secondRecord = ClipboardHistoryRecord(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_123),
            text: "world"
        )

        waitForStoreOperation("append first") { done in
            store.append(firstRecord, completion: done)
        }
        waitForStoreOperation("append second") { done in
            store.append(secondRecord, completion: done)
        }

        XCTAssertEqual(store.records, [firstRecord, secondRecord])

        let reloadedStore = makeStore()
        waitForStoreOperation("reload") { done in reloadedStore.load(completion: done) }
        XCTAssertEqual(reloadedStore.records, [firstRecord, secondRecord])
    }

    func testLoadSkipsMalformedJSONLines() throws {
        let validRecordA = ClipboardHistoryRecord(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: "first"
        )
        let validRecordB = ClipboardHistoryRecord(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_060),
            text: "second"
        )

        let malformedLine = #"{"id":"not-a-valid-line""#
        let payload = try [
            jsonLine(for: validRecordA),
            malformedLine,
            jsonLine(for: validRecordB),
            "",
        ].joined(separator: "\n")
        try payload.write(to: historyFileURL, atomically: true, encoding: .utf8)

        let store = makeStore()
        waitForStoreOperation("load malformed") { done in store.load(completion: done) }

        XCTAssertEqual(store.records, [validRecordA, validRecordB])
    }

    func testDeleteRecordRewritesFile() {
        let store = makeStore()
        waitForStoreOperation("load") { done in store.load(completion: done) }

        let firstRecord = ClipboardHistoryRecord(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: "first"
        )
        let secondRecord = ClipboardHistoryRecord(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_001),
            text: "second"
        )

        waitForStoreOperation("append first") { done in
            store.append(firstRecord, completion: done)
        }
        waitForStoreOperation("append second") { done in
            store.append(secondRecord, completion: done)
        }
        waitForStoreOperation("delete first") { done in
            store.deleteRecord(id: firstRecord.id, completion: done)
        }

        XCTAssertEqual(store.records, [secondRecord])

        let reloadedStore = makeStore()
        waitForStoreOperation("reload") { done in reloadedStore.load(completion: done) }
        XCTAssertEqual(reloadedStore.records, [secondRecord])
    }

    func testClearAllRemovesHistoryFile() {
        let store = makeStore()
        waitForStoreOperation("load") { done in store.load(completion: done) }

        let record = ClipboardHistoryRecord(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: "record"
        )
        waitForStoreOperation("append") { done in
            store.append(record, completion: done)
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: historyFileURL.path))

        waitForStoreOperation("clear all") { done in
            store.clearAll(completion: done)
        }

        XCTAssertEqual(store.records, [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: historyFileURL.path))
    }

    private func makeStore() -> ClipboardHistoryStore {
        ClipboardHistoryStore(
            fileManager: .default,
            historyFileURL: historyFileURL,
            ioQueue: DispatchQueue(label: "StewardTests.ClipboardHistoryStore.\(UUID().uuidString)"),
            autoLoad: false
        )
    }

    private func waitForStoreOperation(_ description: String, operation: (@escaping () -> Void) -> Void) {
        let completionExpectation = expectation(description: description)
        operation {
            completionExpectation.fulfill()
        }
        wait(for: [completionExpectation], timeout: 2.0)
    }

    private func jsonLine(for record: ClipboardHistoryRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        return String(decoding: data, as: UTF8.self)
    }
}
