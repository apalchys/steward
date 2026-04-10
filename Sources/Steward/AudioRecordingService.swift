import AVFoundation
import Foundation

struct RecordedAudioPayload: Equatable {
    let data: Data
    let mimeType: String
}

enum AudioRecordingError: LocalizedError, Equatable {
    case alreadyRecording
    case notRecording
    case couldNotCreateRecorder
    case couldNotStartRecording
    case emptyRecording

    var errorDescription: String? {
        switch self {
        case .alreadyRecording:
            return "A recording is already in progress."
        case .notRecording:
            return "No active recording was found."
        case .couldNotCreateRecorder:
            return "Steward could not prepare the audio recorder."
        case .couldNotStartRecording:
            return "Steward could not start recording audio."
        case .emptyRecording:
            return "The recorded audio was empty."
        }
    }
}

@MainActor
protocol AudioRecordingProviding: AnyObject {
    var onLevelChanged: ((Float) -> Void)? { get set }
    var onMaximumDurationReached: (() -> Void)? { get set }
    var isRecording: Bool { get }

    func startRecording() throws
    func stopRecording() async throws -> RecordedAudioPayload
    func cancelRecording() async
}

protocol AudioRecorderSession: AnyObject {
    var isRecording: Bool { get }
    var currentTime: TimeInterval { get }
    var isMeteringEnabled: Bool { get set }

    func record() -> Bool
    func stop()
    func deleteRecording()
    func updateMeters()
    func averagePower(forChannel channelNumber: Int) -> Float
}

protocol AudioRecorderBuilding {
    func makeRecorder(url: URL, settings: [String: Any]) throws -> any AudioRecorderSession
}

private final class AVAudioRecorderSession: NSObject, AudioRecorderSession {
    private let recorder: AVAudioRecorder

    init(recorder: AVAudioRecorder) {
        self.recorder = recorder
    }

    var isRecording: Bool {
        recorder.isRecording
    }

    var currentTime: TimeInterval {
        recorder.currentTime
    }

    var isMeteringEnabled: Bool {
        get { recorder.isMeteringEnabled }
        set { recorder.isMeteringEnabled = newValue }
    }

    func record() -> Bool {
        recorder.record()
    }

    func stop() {
        recorder.stop()
    }

    func deleteRecording() {
        recorder.deleteRecording()
    }

    func updateMeters() {
        recorder.updateMeters()
    }

    func averagePower(forChannel channelNumber: Int) -> Float {
        recorder.averagePower(forChannel: channelNumber)
    }
}

struct LiveAudioRecorderBuilder: AudioRecorderBuilding {
    func makeRecorder(url: URL, settings: [String: Any]) throws -> any AudioRecorderSession {
        let recorder = try AVAudioRecorder(url: url, settings: settings)
        recorder.prepareToRecord()
        return AVAudioRecorderSession(recorder: recorder)
    }
}

@MainActor
final class SystemAudioRecordingService: AudioRecordingProviding {
    var onLevelChanged: ((Float) -> Void)?
    var onMaximumDurationReached: (() -> Void)?

    var isRecording: Bool {
        recorder?.isRecording == true
    }

    private let recorderBuilder: any AudioRecorderBuilding
    private let maximumDuration: TimeInterval
    private let meteringInterval: Duration
    private let createTemporaryFileURL: () throws -> URL
    private let loadAudioData: (URL) throws -> Data
    private let removeItemAtURL: (URL) throws -> Void
    private let sleep: @Sendable (Duration) async -> Void

    private var recorder: (any AudioRecorderSession)?
    private var recordingURL: URL?
    private var meteringTask: Task<Void, Never>?

    init(
        recorderBuilder: any AudioRecorderBuilding = LiveAudioRecorderBuilder(),
        maximumDuration: TimeInterval = 120,
        meteringInterval: Duration = .milliseconds(50),
        createTemporaryFileURL: @escaping () throws -> URL = {
            try SystemAudioRecordingService.makeTemporaryRecordingURL()
        },
        loadAudioData: @escaping (URL) throws -> Data = { try Data(contentsOf: $0) },
        removeItemAtURL: @escaping (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) },
        sleep: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.recorderBuilder = recorderBuilder
        self.maximumDuration = maximumDuration
        self.meteringInterval = meteringInterval
        self.createTemporaryFileURL = createTemporaryFileURL
        self.loadAudioData = loadAudioData
        self.removeItemAtURL = removeItemAtURL
        self.sleep = sleep
    }

    func startRecording() throws {
        guard recorder == nil, recordingURL == nil else {
            throw AudioRecordingError.alreadyRecording
        }

        let url = try createTemporaryFileURL()
        let recorder: any AudioRecorderSession

        do {
            recorder = try recorderBuilder.makeRecorder(url: url, settings: Self.recordingSettings)
        } catch {
            try? removeItemAtURL(url)
            throw AudioRecordingError.couldNotCreateRecorder
        }

        recorder.isMeteringEnabled = true
        guard recorder.record() else {
            recorder.deleteRecording()
            try? removeItemAtURL(url)
            throw AudioRecordingError.couldNotStartRecording
        }

        self.recorder = recorder
        recordingURL = url
        onLevelChanged?(0)
        startMeteringTask()
    }

    func stopRecording() async throws -> RecordedAudioPayload {
        guard let recorder, let recordingURL else {
            throw AudioRecordingError.notRecording
        }

        stopMeteringTask()

        if recorder.isRecording {
            recorder.stop()
        }

        defer {
            cleanupRecorderState()
            try? removeItemAtURL(recordingURL)
            onLevelChanged?(0)
        }

        let data = try loadAudioData(recordingURL)
        guard !data.isEmpty else {
            throw AudioRecordingError.emptyRecording
        }

        return RecordedAudioPayload(data: data, mimeType: "audio/wav")
    }

    func cancelRecording() async {
        guard let recorder, let recordingURL else {
            return
        }

        stopMeteringTask()

        if recorder.isRecording {
            recorder.stop()
        }

        recorder.deleteRecording()
        try? removeItemAtURL(recordingURL)
        cleanupRecorderState()
        onLevelChanged?(0)
    }

    private func startMeteringTask() {
        stopMeteringTask()

        meteringTask = Task { [weak self] in
            guard let self else {
                return
            }

            while !Task.isCancelled {
                guard let recorder = self.recorder else {
                    return
                }

                recorder.updateMeters()
                self.onLevelChanged?(Self.normalizedPowerLevel(recorder.averagePower(forChannel: 0)))

                if recorder.currentTime >= self.maximumDuration {
                    recorder.stop()
                    self.onLevelChanged?(0)
                    self.onMaximumDurationReached?()
                    return
                }

                if !recorder.isRecording {
                    return
                }

                await self.sleep(self.meteringInterval)
            }
        }
    }

    private func stopMeteringTask() {
        meteringTask?.cancel()
        meteringTask = nil
    }

    private func cleanupRecorderState() {
        recorder = nil
        recordingURL = nil
    }

    private static func normalizedPowerLevel(_ averagePower: Float) -> Float {
        guard averagePower.isFinite else {
            return 0
        }

        let clampedPower = max(averagePower, -60)
        return pow(10, clampedPower / 20)
    }

    nonisolated private static func makeTemporaryRecordingURL() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("wav")

        if FileManager.default.fileExists(atPath: url.path) {
            try FileManager.default.removeItem(at: url)
        }

        return url
    }

    nonisolated private static var recordingSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsFloatKey: false,
        ]
    }
}
