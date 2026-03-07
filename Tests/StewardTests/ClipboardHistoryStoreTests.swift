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

    func testAppendAndReloadPersistsRecords() async throws {
        let store = makeStore()
        store.load()

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

        store.append(firstRecord)
        await waitUntil("append first") {
            store.records == [firstRecord]
        }

        store.append(secondRecord)
        await waitUntil("append second") {
            store.records == [firstRecord, secondRecord]
        }

        let reloadedStore = makeStore()
        reloadedStore.load()
        await waitUntil("reload") {
            reloadedStore.records == [firstRecord, secondRecord]
        }
    }

    func testLoadSkipsMalformedJSONLines() async throws {
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
        store.load()

        await waitUntil("load malformed") {
            store.records == [validRecordA, validRecordB]
        }
    }

    func testDeleteRecordRewritesFile() async {
        let store = makeStore()
        store.load()

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

        store.append(firstRecord)
        await waitUntil("append first") {
            store.records == [firstRecord]
        }

        store.append(secondRecord)
        await waitUntil("append second") {
            store.records == [firstRecord, secondRecord]
        }

        store.deleteRecord(id: firstRecord.id)
        await waitUntil("delete first") {
            store.records == [secondRecord]
        }

        let reloadedStore = makeStore()
        reloadedStore.load()
        await waitUntil("reload") {
            reloadedStore.records == [secondRecord]
        }
    }

    func testClearAllRemovesHistoryFile() async {
        let store = makeStore()
        store.load()

        let record = ClipboardHistoryRecord(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_000),
            text: "record"
        )
        store.append(record)
        await waitUntil("append") {
            store.records == [record]
        }

        XCTAssertTrue(FileManager.default.fileExists(atPath: historyFileURL.path))

        store.clearAll()
        await waitUntil("clear all") {
            store.records.isEmpty && !FileManager.default.fileExists(atPath: self.historyFileURL.path)
        }
    }

    func testAppendTrimsOldestRecordsWhenRetentionLimitIsReached() async {
        let store = makeStore(maxStoredRecords: 2)
        store.load()

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
        let thirdRecord = ClipboardHistoryRecord(
            id: UUID(),
            capturedAt: Date(timeIntervalSince1970: 1_700_000_002),
            text: "third"
        )

        store.append(firstRecord)
        await waitUntil("append first") {
            store.records == [firstRecord]
        }

        store.append(secondRecord)
        await waitUntil("append second") {
            store.records == [firstRecord, secondRecord]
        }

        store.append(thirdRecord)
        await waitUntil("append third") {
            store.records == [secondRecord, thirdRecord]
        }

        let reloadedStore = makeStore(maxStoredRecords: 2)
        reloadedStore.load()
        await waitUntil("reload") {
            reloadedStore.records == [secondRecord, thirdRecord]
        }
    }

    func testUpdateMaxStoredRecordsTrimsExistingHistory() async {
        let store = makeStore(maxStoredRecords: 4)
        store.load()

        let records = (0..<3).map { index in
            ClipboardHistoryRecord(
                id: UUID(),
                capturedAt: Date(timeIntervalSince1970: 1_700_000_000 + TimeInterval(index)),
                text: "record-\(index)"
            )
        }

        for (index, record) in records.enumerated() {
            store.append(record)
            await waitUntil("append \(index)") {
                store.records == Array(records.prefix(index + 1))
            }
        }

        store.updateMaxStoredRecords(2)
        await waitUntil("trim to two") {
            store.records == Array(records.suffix(2))
        }

        let reloadedStore = makeStore(maxStoredRecords: 2)
        reloadedStore.load()
        await waitUntil("reload") {
            reloadedStore.records == Array(records.suffix(2))
        }
    }

    private func makeStore(maxStoredRecords: Int = ClipboardHistorySettings.default.maxStoredRecords) -> ClipboardHistoryStore {
        ClipboardHistoryStore(
            fileManager: .default,
            historyFileURL: historyFileURL,
            ioQueue: DispatchQueue(label: "StewardTests.ClipboardHistoryStore.\(UUID().uuidString)"),
            maxStoredRecords: maxStoredRecords,
            autoLoad: false
        )
    }

    private func waitUntil(
        _ description: String,
        timeout: Duration = .seconds(2),
        pollInterval: Duration = .milliseconds(10),
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping () -> Bool
    ) async {
        let deadline = ContinuousClock.now + timeout

        while ContinuousClock.now < deadline {
            if condition() {
                return
            }

            try? await Task.sleep(for: pollInterval)
        }

        XCTAssertTrue(condition(), "Timed out waiting for \(description)", file: file, line: line)
    }

    private func jsonLine(for record: ClipboardHistoryRecord) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(record)
        return String(decoding: data, as: UTF8.self)
    }
}
