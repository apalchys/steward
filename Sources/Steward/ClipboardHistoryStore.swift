import Combine
import Foundation
import OSLog

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.steward", category: "clipboard")

final class ClipboardHistoryStore: ObservableObject, @unchecked Sendable {
    static let maxRecordSize = 4096

    @Published private(set) var records: [ClipboardHistoryRecord] = []
    @Published private(set) var lastErrorMessage: String?

    private let fileManager: FileManager
    private let historyFileURL: URL
    private let ioQueue: DispatchQueue
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    // Access only from ioQueue.
    private var queuedRecords: [ClipboardHistoryRecord] = []

    init(
        fileManager: FileManager = .default,
        historyFileURL: URL? = nil,
        ioQueue: DispatchQueue? = nil,
        autoLoad: Bool = true
    ) {
        self.fileManager = fileManager
        self.historyFileURL = historyFileURL ?? Self.defaultHistoryFileURL(fileManager: fileManager)
        self.ioQueue = ioQueue ?? DispatchQueue(label: "Steward.ClipboardHistoryStore", qos: .utility)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder

        if autoLoad {
            load()
        }
    }

    func load(completion: (@Sendable () -> Void)? = nil) {
        ioQueue.async {
            self.loadFromDisk()
            self.notifyCompletion(completion)
        }
    }

    func append(_ record: ClipboardHistoryRecord, completion: (@Sendable () -> Void)? = nil) {
        ioQueue.async {
            self.queuedRecords.append(record)
            self.publish(records: self.queuedRecords, errorMessage: nil)

            do {
                try self.appendRecordToDisk(record)
            } catch {
                self.publishError("Could not save clipboard history.")
            }

            self.notifyCompletion(completion)
        }
    }

    func deleteRecord(id: ClipboardHistoryRecord.ID, completion: (@Sendable () -> Void)? = nil) {
        ioQueue.async {
            guard let index = self.queuedRecords.firstIndex(where: { $0.id == id }) else {
                self.notifyCompletion(completion)
                return
            }

            self.queuedRecords.remove(at: index)
            self.publish(records: self.queuedRecords, errorMessage: nil)

            do {
                if self.queuedRecords.isEmpty {
                    try self.clearHistoryFile()
                } else {
                    try self.rewriteHistoryFile()
                }
            } catch {
                self.publishError("Could not update clipboard history.")
            }

            self.notifyCompletion(completion)
        }
    }

    func clearAll(completion: (@Sendable () -> Void)? = nil) {
        ioQueue.async {
            self.queuedRecords.removeAll()
            self.publish(records: self.queuedRecords, errorMessage: nil)

            do {
                try self.clearHistoryFile()
            } catch {
                self.publishError("Could not clear clipboard history.")
            }

            self.notifyCompletion(completion)
        }
    }

    private func loadFromDisk() {
        do {
            try ensureParentDirectoryExists()
            guard fileManager.fileExists(atPath: historyFileURL.path) else {
                queuedRecords = []
                publish(records: [], errorMessage: nil)
                return
            }

            let data = try Data(contentsOf: historyFileURL)
            guard !data.isEmpty else {
                queuedRecords = []
                publish(records: [], errorMessage: nil)
                return
            }

            guard let fileContents = String(data: data, encoding: .utf8) else {
                throw StoreError.invalidFileEncoding
            }

            var loadedRecords: [ClipboardHistoryRecord] = []
            fileContents.enumerateLines { line, _ in
                guard !line.isEmpty, let lineData = line.data(using: .utf8) else {
                    return
                }

                guard let record = try? self.decoder.decode(ClipboardHistoryRecord.self, from: lineData) else {
                    return
                }

                loadedRecords.append(record)
            }

            queuedRecords = loadedRecords
            publish(records: loadedRecords, errorMessage: nil)
        } catch {
            queuedRecords = []
            publish(records: [], errorMessage: nil)
            logger.error("ClipboardHistoryStore load failed: \(error)")
        }
    }

    private func appendRecordToDisk(_ record: ClipboardHistoryRecord) throws {
        try ensureParentDirectoryExists()
        let lineData = try encodedLine(for: record)

        if fileManager.fileExists(atPath: historyFileURL.path) {
            let fileHandle = try FileHandle(forWritingTo: historyFileURL)
            defer { try? fileHandle.close() }

            try fileHandle.seekToEnd()
            try fileHandle.write(contentsOf: lineData)
            return
        }

        let created = fileManager.createFile(atPath: historyFileURL.path, contents: lineData)
        if !created {
            throw StoreError.couldNotCreateFile
        }
    }

    private func rewriteHistoryFile() throws {
        try ensureParentDirectoryExists()

        var fileData = Data()
        for record in queuedRecords {
            fileData.append(try encodedLine(for: record))
        }

        try fileData.write(to: historyFileURL, options: .atomic)
    }

    private func clearHistoryFile() throws {
        guard fileManager.fileExists(atPath: historyFileURL.path) else {
            return
        }

        try fileManager.removeItem(at: historyFileURL)
    }

    private func ensureParentDirectoryExists() throws {
        let directoryURL = historyFileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
    }

    private func encodedLine(for record: ClipboardHistoryRecord) throws -> Data {
        var line = try encoder.encode(record)
        line.append(0x0A)
        return line
    }

    private func publish(records: [ClipboardHistoryRecord], errorMessage: String?) {
        Task { @MainActor in
            self.records = records
            self.lastErrorMessage = errorMessage
        }
    }

    private func publishError(_ message: String) {
        Task { @MainActor in
            self.lastErrorMessage = message
        }
    }

    private func notifyCompletion(_ completion: (@Sendable () -> Void)?) {
        guard let completion else {
            return
        }

        completion()
    }

    private enum StoreError: Error {
        case couldNotCreateFile
        case invalidFileEncoding
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
