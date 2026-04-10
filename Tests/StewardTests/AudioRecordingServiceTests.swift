import AVFoundation
import XCTest
@testable import Steward

@MainActor
final class AudioRecordingServiceTests: XCTestCase {
    func testStartRecordingBuildsMonoWAVRecorderAndStartsMetering() async throws {
        let recorder = FakeAudioRecorderSession()
        let builder = FakeAudioRecorderBuilder(recorder: recorder)
        let url = URL(fileURLWithPath: "/tmp/test-audio.wav")
        let service = SystemAudioRecordingService(
            recorderBuilder: builder,
            maximumDuration: 120,
            meteringInterval: .milliseconds(1),
            createTemporaryFileURL: { url },
            loadAudioData: { _ in Data("audio".utf8) },
            removeItemAtURL: { _ in },
            sleep: { _ in await Task.yield() }
        )
        var levels: [Float] = []
        service.onLevelChanged = { levels.append($0) }
        recorder.averagePowerValue = -12
        recorder.currentTimeValue = 1

        try service.startRecording()
        await Task.yield()

        XCTAssertTrue(service.isRecording)
        XCTAssertEqual(builder.createdURL, url)
        XCTAssertEqual(builder.createdSettings[AVNumberOfChannelsKey] as? Int, 1)
        XCTAssertEqual(builder.createdSettings[AVSampleRateKey] as? Int, 16_000)
        XCTAssertEqual(builder.createdSettings[AVLinearPCMBitDepthKey] as? Int, 16)
        XCTAssertTrue(recorder.isMeteringEnabled)
        XCTAssertGreaterThan(levels.count, 0)
    }

    func testStopRecordingReturnsAudioDataAndDeletesTemporaryFile() async throws {
        let recorder = FakeAudioRecorderSession()
        let builder = FakeAudioRecorderBuilder(recorder: recorder)
        let url = URL(fileURLWithPath: "/tmp/test-audio.wav")
        var removedURLs: [URL] = []
        let service = SystemAudioRecordingService(
            recorderBuilder: builder,
            createTemporaryFileURL: { url },
            loadAudioData: { _ in Data("audio-bytes".utf8) },
            removeItemAtURL: { removedURLs.append($0) },
            sleep: { _ in }
        )

        try service.startRecording()
        let payload = try await service.stopRecording()

        XCTAssertEqual(payload, RecordedAudioPayload(data: Data("audio-bytes".utf8), mimeType: "audio/wav"))
        XCTAssertTrue(recorder.stopCallCount >= 1)
        XCTAssertEqual(removedURLs, [url])
        XCTAssertFalse(service.isRecording)
    }

    func testCancelRecordingStopsDeletesAndResetsLevel() async throws {
        let recorder = FakeAudioRecorderSession()
        let builder = FakeAudioRecorderBuilder(recorder: recorder)
        let url = URL(fileURLWithPath: "/tmp/test-audio.wav")
        var removedURLs: [URL] = []
        var levels: [Float] = []
        let service = SystemAudioRecordingService(
            recorderBuilder: builder,
            createTemporaryFileURL: { url },
            loadAudioData: { _ in Data() },
            removeItemAtURL: { removedURLs.append($0) },
            sleep: { _ in }
        )
        service.onLevelChanged = { levels.append($0) }

        try service.startRecording()
        await service.cancelRecording()

        XCTAssertEqual(recorder.deleteRecordingCallCount, 1)
        XCTAssertEqual(removedURLs, [url])
        XCTAssertEqual(levels.last, 0)
        XCTAssertFalse(service.isRecording)
    }

    func testStartRecordingThrowsWhenAlreadyRecording() throws {
        let recorder = FakeAudioRecorderSession()
        let service = SystemAudioRecordingService(
            recorderBuilder: FakeAudioRecorderBuilder(recorder: recorder),
            createTemporaryFileURL: { URL(fileURLWithPath: "/tmp/test-audio.wav") },
            loadAudioData: { _ in Data() },
            removeItemAtURL: { _ in },
            sleep: { _ in }
        )

        try service.startRecording()

        XCTAssertThrowsError(try service.startRecording()) { error in
            XCTAssertEqual(error as? AudioRecordingError, .alreadyRecording)
        }
    }

    func testMeteringAutoStopsAtMaximumDurationAndNotifies() async throws {
        let recorder = FakeAudioRecorderSession()
        recorder.currentTimeValue = 2
        let service = SystemAudioRecordingService(
            recorderBuilder: FakeAudioRecorderBuilder(recorder: recorder),
            maximumDuration: 1,
            meteringInterval: .milliseconds(1),
            createTemporaryFileURL: { URL(fileURLWithPath: "/tmp/test-audio.wav") },
            loadAudioData: { _ in Data("audio".utf8) },
            removeItemAtURL: { _ in },
            sleep: { _ in await Task.yield() }
        )
        var didReachMaximumDuration = false
        service.onMaximumDurationReached = { didReachMaximumDuration = true }

        try service.startRecording()
        await Task.yield()

        XCTAssertTrue(didReachMaximumDuration)
        XCTAssertEqual(recorder.stopCallCount, 1)
        XCTAssertFalse(service.isRecording)

        let payload = try await service.stopRecording()
        XCTAssertEqual(payload.mimeType, "audio/wav")
    }
}

private final class FakeAudioRecorderBuilder: AudioRecorderBuilding {
    let recorder: FakeAudioRecorderSession
    private(set) var createdURL: URL?
    private(set) var createdSettings: [String: Any] = [:]

    init(recorder: FakeAudioRecorderSession) {
        self.recorder = recorder
    }

    func makeRecorder(url: URL, settings: [String: Any]) throws -> any AudioRecorderSession {
        createdURL = url
        createdSettings = settings
        return recorder
    }
}

private final class FakeAudioRecorderSession: AudioRecorderSession {
    var isRecording = false
    var currentTimeValue: TimeInterval = 0
    var isMeteringEnabled = false
    var averagePowerValue: Float = -30
    private(set) var stopCallCount = 0
    private(set) var deleteRecordingCallCount = 0

    var currentTime: TimeInterval {
        currentTimeValue
    }

    func record() -> Bool {
        isRecording = true
        return true
    }

    func stop() {
        stopCallCount += 1
        isRecording = false
    }

    func deleteRecording() {
        deleteRecordingCallCount += 1
    }

    func updateMeters() {}

    func averagePower(forChannel channelNumber: Int) -> Float {
        averagePowerValue
    }
}
