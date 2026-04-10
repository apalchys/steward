import Foundation
import XCTest
@testable import Steward

@MainActor
final class VoiceDictationCoordinatorTests: XCTestCase {
    func testFirstHotKeyPressStartsRecordingAndShowsPill() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService()
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let router = VoiceDictationFakeRouter(result: .success(.text("ignored")))
        let textInteraction = VoiceDictationFakeTextInteraction()
        let coordinator = VoiceDictationCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: textInteraction,
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleHotKeyPress()

        XCTAssertEqual(microphoneAccess.ensureAccessCallCount, 1)
        XCTAssertEqual(audioRecordingService.startRecordingCallCount, 1)
        XCTAssertEqual(pillPresenter.recordingLevels, [0])
        XCTAssertTrue(audioRecordingService.isRecording)
    }

    func testSecondHotKeyPressStopsRecordingRoutesTranscriptAndReplacesText() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService(payload: RecordedAudioPayload(data: Data("audio".utf8), mimeType: "audio/wav"))
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let router = VoiceDictationFakeRouter(result: .success(.text("Dictated text")))
        let textInteraction = VoiceDictationFakeTextInteraction()
        let settingsStore = VoiceDictationSettingsStore()
        settingsStore.settings.voice = VoiceSettings(
            providerID: .gemini,
            geminiModelID: "voice-model-gemini",
            openAIModelID: "voice-model-openai",
            customInstructions: "Keep mixed languages"
        )
        let coordinator = VoiceDictationCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: textInteraction,
            settingsStore: settingsStore
        )

        try await coordinator.handleHotKeyPress()
        try await coordinator.handleHotKeyPress()

        XCTAssertEqual(audioRecordingService.stopRecordingCallCount, 1)
        XCTAssertEqual(pillPresenter.showTranscribingCallCount, 1)
        XCTAssertEqual(textInteraction.replacedText, "Dictated text")
        XCTAssertEqual(pillPresenter.hideCallCount, 1)
        guard let request = router.lastRequest else {
            return XCTFail("Expected routed voice request")
        }
        XCTAssertEqual(request.providerID, .gemini)
        XCTAssertEqual(request.modelIDOverride, "voice-model-gemini")
    }

    func testCancelDiscardsRecordingWithoutCallingRouter() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService()
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let router = VoiceDictationFakeRouter(result: .success(.text("ignored")))
        let coordinator = VoiceDictationCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleHotKeyPress()
        pillPresenter.onCancel?()
        await Task.yield()

        XCTAssertEqual(audioRecordingService.cancelRecordingCallCount, 1)
        XCTAssertNil(router.lastRequest)
        XCTAssertEqual(pillPresenter.hideCallCount, 1)
    }

    func testInsertionFailureCopiesTranscriptToClipboard() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService(payload: RecordedAudioPayload(data: Data("audio".utf8), mimeType: "audio/wav"))
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let router = VoiceDictationFakeRouter(result: .success(.text("Dictated text")))
        let textInteraction = VoiceDictationFakeTextInteraction(replaceError: TextInteractionError.couldNotReplaceSelectedText)
        let coordinator = VoiceDictationCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: textInteraction,
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleHotKeyPress()

        do {
            try await coordinator.handleHotKeyPress()
            XCTFail("Expected insertion fallback error")
        } catch {
            XCTAssertEqual(error as? VoiceDictationCoordinatorError, .insertionFailedCopiedToClipboard)
            XCTAssertEqual(textInteraction.copiedText, "Dictated text")
        }
    }

    func testPermissionDeniedFailsBeforeRecordingStarts() async {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: false)
        let audioRecordingService = FakeAudioRecordingService()
        let coordinator = VoiceDictationCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: FakeVoiceRecordingPillPresenter(),
            router: VoiceDictationFakeRouter(result: .success(.text("ignored"))),
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )

        do {
            try await coordinator.handleHotKeyPress()
            XCTFail("Expected microphone permission error")
        } catch {
            XCTAssertEqual(error as? VoiceDictationCoordinatorError, .permissionDenied)
            XCTAssertEqual(audioRecordingService.startRecordingCallCount, 0)
        }
    }

    func testMaximumDurationAutomaticallyTranscribesAndForwardsErrors() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService(payload: RecordedAudioPayload(data: Data("audio".utf8), mimeType: "audio/wav"))
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let router = VoiceDictationFakeRouter(result: .failure(VoiceDictationTestError.failed))
        let coordinator = VoiceDictationCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )
        var reportedError: Error?
        coordinator.onError = { reportedError = $0 }

        try await coordinator.handleHotKeyPress()
        audioRecordingService.onMaximumDurationReached?()
        await Task.yield()

        XCTAssertEqual(audioRecordingService.stopRecordingCallCount, 1)
        XCTAssertEqual(reportedError as? VoiceDictationTestError, .failed)
        XCTAssertEqual(pillPresenter.hideCallCount, 1)
    }
}

private enum VoiceDictationTestError: Error, Equatable {
    case failed
}

@MainActor
private final class FakeMicrophoneAccessProvider: MicrophoneAccessProviding {
    let result: Bool
    private(set) var ensureAccessCallCount = 0

    init(result: Bool) {
        self.result = result
    }

    func ensureAccess() async -> Bool {
        ensureAccessCallCount += 1
        return result
    }
}

@MainActor
private final class FakeAudioRecordingService: AudioRecordingProviding {
    var onLevelChanged: ((Float) -> Void)?
    var onMaximumDurationReached: (() -> Void)?
    private(set) var isRecording = false
    private(set) var startRecordingCallCount = 0
    private(set) var stopRecordingCallCount = 0
    private(set) var cancelRecordingCallCount = 0
    let payload: RecordedAudioPayload

    init(payload: RecordedAudioPayload = RecordedAudioPayload(data: Data("audio".utf8), mimeType: "audio/wav")) {
        self.payload = payload
    }

    func startRecording() throws {
        startRecordingCallCount += 1
        isRecording = true
    }

    func stopRecording() async throws -> RecordedAudioPayload {
        stopRecordingCallCount += 1
        isRecording = false
        return payload
    }

    func cancelRecording() async {
        cancelRecordingCallCount += 1
        isRecording = false
    }
}

@MainActor
private final class FakeVoiceRecordingPillPresenter: VoiceRecordingPillPresenting {
    var onCancel: (() -> Void)?
    var onConfirm: (() -> Void)?
    private(set) var recordingLevels: [Float] = []
    private(set) var showTranscribingCallCount = 0
    private(set) var hideCallCount = 0

    func showRecording(level: Float) {
        recordingLevels.append(level)
    }

    func showTranscribing() {
        showTranscribingCallCount += 1
    }

    func hide() {
        hideCallCount += 1
    }
}

@MainActor
private final class VoiceDictationFakeRouter: LLMRouting {
    let result: Result<LLMResult, Error>
    private(set) var lastRequest: LLMRequest?

    init(result: Result<LLMResult, Error>) {
        self.result = result
    }

    func perform(_ request: LLMRequest) async throws -> LLMResult {
        lastRequest = request
        return try result.get()
    }

    func checkAccess(for providerID: LLMProviderID) async throws -> LLMProviderHealth {
        LLMProviderHealth(providerID: providerID, state: .available, message: "Ready")
    }
}

private final class VoiceDictationFakeTextInteraction: TextInteractionPerforming, @unchecked Sendable {
    let replaceError: Error?
    private(set) var replacedText: String?
    private(set) var copiedText: String?

    init(replaceError: Error? = nil) {
        self.replaceError = replaceError
    }

    func getSelectedText() async throws -> String? {
        nil
    }

    func replaceSelectedText(with newText: String) async throws {
        if let replaceError {
            throw replaceError
        }

        replacedText = newText
    }

    func copyTextToClipboard(_ text: String) {
        copiedText = text
    }
}

private final class VoiceDictationSettingsStore: AppSettingsProviding {
    var settings = LLMSettings.empty()

    func loadSettings() -> LLMSettings {
        settings
    }

    func saveSettings(_ settings: LLMSettings) {
        self.settings = settings
    }
}
