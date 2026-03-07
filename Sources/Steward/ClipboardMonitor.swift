import AppKit
import Foundation

protocol ClipboardTextReading {
    var changeCount: Int { get }
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
}

extension NSPasteboard: ClipboardTextReading {}

final class ClipboardMonitor: @unchecked Sendable {
    static let defaultPollInterval: TimeInterval = 0.75

    private let pasteboard: ClipboardTextReading
    private let pollInterval: TimeInterval
    private let maxRecordSize: Int
    private let suppressionExpiration: TimeInterval
    private let onAcceptedRecord: (ClipboardHistoryRecord) -> Void

    private var timer: Timer?
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
        stop()
    }

    func start() {
        guard timer == nil else {
            return
        }

        lastChangeCount = pasteboard.changeCount

        let timer = Timer(timeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.pollPasteboardIfNeeded()
        }
        timer.tolerance = min(0.25, pollInterval * 0.5)
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stop() {
        timer?.invalidate()
        timer = nil
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
