import AppKit
import Foundation

protocol ClipboardTextReading {
    var changeCount: Int { get }
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
}

extension NSPasteboard: ClipboardTextReading {}

@MainActor
final class ClipboardMonitor {
    static let defaultPollInterval: TimeInterval = 0.75

    private let pasteboard: ClipboardTextReading
    private let pollInterval: TimeInterval
    private let maxRecordSize: Int
    private let suppressionExpiration: TimeInterval
    private let onAcceptedRecord: (ClipboardHistoryRecord) -> Void

    private var pollingTask: Task<Void, Never>?
    private var lastChangeCount = 0
    private var suppressedChangeCount = 0
    private var suppressionExpiresAt: Date?

    init(
        pasteboard: ClipboardTextReading = NSPasteboard.general,
        pollInterval: TimeInterval = ClipboardMonitor.defaultPollInterval,
        maxRecordSize: Int = ClipboardHistoryStore.maxRecordSize,
        suppressionExpiration: TimeInterval = 2.0,
        onAcceptedRecord: @escaping (ClipboardHistoryRecord) -> Void
    ) {
        self.pasteboard = pasteboard
        self.pollInterval = pollInterval
        self.maxRecordSize = maxRecordSize
        self.suppressionExpiration = suppressionExpiration
        self.onAcceptedRecord = onAcceptedRecord
    }

    deinit {
        pollingTask?.cancel()
    }

    func start() {
        guard pollingTask == nil else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        pollingTask = Task { [weak self, pollInterval] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(pollInterval))
                guard !Task.isCancelled else {
                    return
                }

                await MainActor.run {
                    self?.pollPasteboardIfNeeded()
                }
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    func suppressNextClipboardChanges(_ count: Int = 1) {
        guard count > 0 else {
            return
        }

        suppressedChangeCount += count
        suppressionExpiresAt = Date().addingTimeInterval(suppressionExpiration)
    }

    func pollPasteboardIfNeeded() {
        let currentChangeCount = pasteboard.changeCount
        guard currentChangeCount != lastChangeCount else {
            return
        }

        let delta = currentChangeCount > lastChangeCount ? (currentChangeCount - lastChangeCount) : 1
        lastChangeCount = currentChangeCount
        clearExpiredSuppressionIfNeeded()

        if suppressedChangeCount > 0 {
            if delta <= suppressedChangeCount {
                suppressedChangeCount -= delta
                if suppressedChangeCount == 0 {
                    suppressionExpiresAt = nil
                }
                return
            }

            suppressedChangeCount = 0
            suppressionExpiresAt = nil
        }

        guard let text = pasteboard.string(forType: .string), !text.isEmpty else {
            return
        }

        let size = text.utf8.count
        guard size <= maxRecordSize else {
            return
        }

        onAcceptedRecord(ClipboardHistoryRecord(capturedAt: Date(), text: text, size: size))
    }

    private func clearExpiredSuppressionIfNeeded(now: Date = Date()) {
        guard let suppressionExpiresAt, now > suppressionExpiresAt else {
            return
        }

        suppressedChangeCount = 0
        self.suppressionExpiresAt = nil
    }
}
