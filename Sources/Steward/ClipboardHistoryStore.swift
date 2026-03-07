import Foundation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.steward", category: "clipboard")

@MainActor
final class ClipboardHistoryStore: ObservableObject {
    static let maxRecordSize = 4096

    @Published private(set) var records: [ClipboardHistoryRecord] = []
    @Published private(set) var lastErrorMessage: String?

    private let historyFileURL: URL
    private var maxStoredRecords: Int
    private var pendingDiskTask: Task<Void, Never>?

    init(
        fileManager: FileManager = .default,
        historyFileURL: URL? = nil,
        maxStoredRecords: Int = ClipboardHistorySettings.default.maxStoredRecords,
        autoLoad: Bool = true
    ) {
        self.historyFileURL = historyFileURL ?? Self.defaultHistoryFileURL(fileManager: fileManager)
        self.maxStoredRecords = ClipboardHistorySettings.sanitizedMaxStoredRecords(maxStoredRecords)

        if autoLoad {
            load()
        }
    }

    func load() {
        let fileURL = historyFileURL
        let maxRecords = maxStoredRecords
        let previousTask = pendingDiskTask

        pendingDiskTask = Task.detached { [weak self] in
            await previousTask?.value
            let loaded = clipboardDiskLoad(fileURL: fileURL, maxStoredRecords: maxRecords)
            await self?.applyLoadResult(loaded)
        }
    }

    func append(_ record: ClipboardHistoryRecord) {
        records.append(record)
        let didTrim = trimRecordsIfNeeded()
        lastErrorMessage = nil

        let snapshot = records
        let fileURL = historyFileURL
        let previousTask = pendingDiskTask

        pendingDiskTask = Task.detached { [weak self] in
            await previousTask?.value
            do {
                if didTrim {
                    try clipboardDiskRewriteOrClear(records: snapshot, fileURL: fileURL)
                } else {
                    try clipboardDiskAppend(record, fileURL: fileURL)
                }
            } catch {
                await self?.setError("Could not save clipboard history.")
            }
        }
    }

    func deleteRecord(id: ClipboardHistoryRecord.ID) {
        guard let index = records.firstIndex(where: { $0.id == id }) else {
            return
        }

        records.remove(at: index)
        lastErrorMessage = nil

        let snapshot = records
        let fileURL = historyFileURL
        let previousTask = pendingDiskTask

        pendingDiskTask = Task.detached { [weak self] in
            await previousTask?.value
            do {
                if snapshot.isEmpty {
                    try clipboardDiskClear(fileURL: fileURL)
                } else {
                    try clipboardDiskRewrite(records: snapshot, fileURL: fileURL)
                }
            } catch {
                await self?.setError("Could not update clipboard history.")
            }
        }
    }

    func clearAll() {
        records.removeAll()
        lastErrorMessage = nil

        let fileURL = historyFileURL
        let previousTask = pendingDiskTask

        pendingDiskTask = Task.detached { [weak self] in
            await previousTask?.value
            do {
                try clipboardDiskClear(fileURL: fileURL)
            } catch {
                await self?.setError("Could not clear clipboard history.")
            }
        }
    }

    func updateMaxStoredRecords(_ maxStoredRecords: Int) {
        self.maxStoredRecords = ClipboardHistorySettings.sanitizedMaxStoredRecords(maxStoredRecords)
        let didTrim = trimRecordsIfNeeded()
        lastErrorMessage = nil

        guard didTrim else {
            return
        }

        let snapshot = records
        let fileURL = historyFileURL
        let previousTask = pendingDiskTask

        pendingDiskTask = Task.detached { [weak self] in
            await previousTask?.value
            do {
                try clipboardDiskRewriteOrClear(records: snapshot, fileURL: fileURL)
            } catch {
                await self?.setError("Could not update clipboard history.")
            }
        }
    }

    // MARK: - Private Helpers

    private func applyLoadResult(_ result: ClipboardDiskLoadResult) {
        records = result.records
        lastErrorMessage = result.errorMessage
    }

    private func setError(_ message: String) {
        lastErrorMessage = message
    }

    private func trimRecordsIfNeeded() -> Bool {
        guard records.count > maxStoredRecords else {
            return false
        }

        records.removeFirst(records.count - maxStoredRecords)
        return true
    }

    // MARK: - Testing Support

    /// Waits for all pending disk operations to finish. Intended for tests only.
    func waitForPendingDiskWrites() async {
        await pendingDiskTask?.value
    }
}

extension ClipboardHistoryStore {
    static func defaultHistoryFileURL(fileManager: FileManager = .default) -> URL {
        if let appSupportURL = try? fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        ) {
            return
                appSupportURL
                .appendingPathComponent("Steward", isDirectory: true)
                .appendingPathComponent("clipboard-history.jsonl", isDirectory: false)
        }

        let fallbackDirectory = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent("Library/Application Support/Steward", isDirectory: true)
        return fallbackDirectory.appendingPathComponent("clipboard-history.jsonl", isDirectory: false)
    }
}

// MARK: - File-private Disk I/O (nonisolated free functions)

private struct ClipboardDiskLoadResult: Sendable {
    let records: [ClipboardHistoryRecord]
    let errorMessage: String?
}

private func clipboardDiskLoad(fileURL: URL, maxStoredRecords: Int) -> ClipboardDiskLoadResult {
    let fileManager = FileManager.default
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601

    do {
        try clipboardDiskEnsureParentDirectory(for: fileURL, fileManager: fileManager)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return ClipboardDiskLoadResult(records: [], errorMessage: nil)
        }

        let data = try Data(contentsOf: fileURL)
        guard !data.isEmpty else {
            return ClipboardDiskLoadResult(records: [], errorMessage: nil)
        }

        guard let fileContents = String(data: data, encoding: .utf8) else {
            return ClipboardDiskLoadResult(records: [], errorMessage: nil)
        }

        var loadedRecords: [ClipboardHistoryRecord] = []
        fileContents.enumerateLines { line, _ in
            guard !line.isEmpty, let lineData = line.data(using: .utf8) else {
                return
            }

            guard let record = try? decoder.decode(ClipboardHistoryRecord.self, from: lineData) else {
                return
            }

            loadedRecords.append(record)
        }

        if loadedRecords.count > maxStoredRecords {
            loadedRecords.removeFirst(loadedRecords.count - maxStoredRecords)
        }

        return ClipboardDiskLoadResult(records: loadedRecords, errorMessage: nil)
    } catch {
        logger.error("ClipboardHistoryStore load failed: \(error)")
        return ClipboardDiskLoadResult(records: [], errorMessage: nil)
    }
}

private func clipboardDiskAppend(_ record: ClipboardHistoryRecord, fileURL: URL) throws {
    let fileManager = FileManager.default
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    try clipboardDiskEnsureParentDirectory(for: fileURL, fileManager: fileManager)
    let lineData = try clipboardDiskEncodedLine(for: record, encoder: encoder)

    if fileManager.fileExists(atPath: fileURL.path) {
        let fileHandle = try FileHandle(forWritingTo: fileURL)
        defer { try? fileHandle.close() }

        try fileHandle.seekToEnd()
        try fileHandle.write(contentsOf: lineData)
        return
    }

    let created = fileManager.createFile(atPath: fileURL.path, contents: lineData)
    if !created {
        throw ClipboardDiskError.couldNotCreateFile
    }
}

private func clipboardDiskRewrite(records: [ClipboardHistoryRecord], fileURL: URL) throws {
    let fileManager = FileManager.default
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    try clipboardDiskEnsureParentDirectory(for: fileURL, fileManager: fileManager)

    var fileData = Data()
    for record in records {
        fileData.append(try clipboardDiskEncodedLine(for: record, encoder: encoder))
    }

    try fileData.write(to: fileURL, options: .atomic)
}

private func clipboardDiskRewriteOrClear(records: [ClipboardHistoryRecord], fileURL: URL) throws {
    if records.isEmpty {
        try clipboardDiskClear(fileURL: fileURL)
    } else {
        try clipboardDiskRewrite(records: records, fileURL: fileURL)
    }
}

private func clipboardDiskClear(fileURL: URL) throws {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: fileURL.path) else {
        return
    }

    try fileManager.removeItem(at: fileURL)
}

private func clipboardDiskEnsureParentDirectory(for fileURL: URL, fileManager: FileManager) throws {
    let directoryURL = fileURL.deletingLastPathComponent()
    try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
}

private func clipboardDiskEncodedLine(for record: ClipboardHistoryRecord, encoder: JSONEncoder) throws -> Data {
    var line = try encoder.encode(record)
    line.append(0x0A)
    return line
}

private enum ClipboardDiskError: Error {
    case couldNotCreateFile
}
