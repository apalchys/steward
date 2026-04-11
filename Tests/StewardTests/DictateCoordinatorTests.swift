import Foundation
import XCTest
@testable import Steward

@MainActor
final class DictateCoordinatorTests: XCTestCase {
    func testFirstManualToggleStartsRecordingAndShowsPill() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService()
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let router = VoiceDictationFakeRouter(result: .success(.text("ignored")))
        let textInteraction = VoiceDictationFakeTextInteraction()
        let coordinator = DictateCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: textInteraction,
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleManualToggleAction()

        XCTAssertEqual(microphoneAccess.ensureAccessCallCount, 1)
        XCTAssertEqual(audioRecordingService.startRecordingCallCount, 1)
        XCTAssertEqual(pillPresenter.recordingStates, [.interactiveRecording(level: 0)])
        XCTAssertTrue(audioRecordingService.isRecording)
    }

    func testSecondManualToggleStopsRecordingRoutesTranscriptAndReplacesText() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService(payload: RecordedAudioPayload(data: Data("audio".utf8), mimeType: "audio/wav"))
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let router = VoiceDictationFakeRouter(result: .success(.text("Dictated text")))
        let textInteraction = VoiceDictationFakeTextInteraction()
        let settingsStore = VoiceDictationSettingsStore()
        settingsStore.settings.voice = VoiceSettings(
            selectedModel: LLMModelSelection(providerID: .gemini, modelID: "voice-model-gemini"),
            customInstructions: "Keep mixed languages",
            preferredRecognitionLanguages: [.english, .spanish],
            translateToLanguageEnabled: true,
            translationTargetLanguage: .german
        )
        let coordinator = DictateCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: textInteraction,
            settingsStore: settingsStore
        )

        try await coordinator.handleManualToggleAction()
        try await coordinator.handleManualToggleAction()

        XCTAssertEqual(audioRecordingService.stopRecordingCallCount, 1)
        XCTAssertEqual(pillPresenter.showTranscribingCallCount, 1)
        XCTAssertEqual(textInteraction.replacedText, "Dictated text")
        XCTAssertEqual(pillPresenter.hideCallCount, 1)
        guard let request = router.lastRequest else {
            return XCTFail("Expected routed voice request")
        }
        XCTAssertEqual(request.selection, LLMModelSelection(providerID: .gemini, modelID: "voice-model-gemini"))
        guard case let .voiceTranscription(_, _, options) = request.task else {
            return XCTFail("Expected voice transcription task")
        }
        XCTAssertEqual(options.preferredRecognitionLanguages, [.english, .spanish])
        XCTAssertTrue(options.translateToLanguageEnabled)
        XCTAssertEqual(options.translationTargetLanguage, .german)
        XCTAssertEqual(options.customInstructions, "Keep mixed languages")
    }

    func testCancelDiscardsRecordingWithoutCallingRouter() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService()
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let router = VoiceDictationFakeRouter(result: .success(.text("ignored")))
        let coordinator = DictateCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleManualToggleAction()
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
        let coordinator = DictateCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: textInteraction,
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleManualToggleAction()

        do {
            try await coordinator.handleManualToggleAction()
            XCTFail("Expected insertion fallback error")
        } catch {
            XCTAssertEqual(error as? DictateCoordinatorError, .insertionFailedCopiedToClipboard)
            XCTAssertEqual(textInteraction.copiedText, "Dictated text")
        }
    }

    func testPermissionDeniedFailsBeforeRecordingStarts() async {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: false)
        let audioRecordingService = FakeAudioRecordingService()
        let coordinator = DictateCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: FakeVoiceRecordingPillPresenter(),
            router: VoiceDictationFakeRouter(result: .success(.text("ignored"))),
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )

        do {
            try await coordinator.handleManualToggleAction()
            XCTFail("Expected microphone permission error")
        } catch {
            XCTAssertEqual(error as? DictateCoordinatorError, .permissionDenied)
            XCTAssertEqual(audioRecordingService.startRecordingCallCount, 0)
        }
    }

    func testMaximumDurationAutomaticallyTranscribesAndForwardsErrors() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService(payload: RecordedAudioPayload(data: Data("audio".utf8), mimeType: "audio/wav"))
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let router = VoiceDictationFakeRouter(result: .failure(VoiceDictationTestError.failed))
        let coordinator = DictateCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: pillPresenter,
            router: router,
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )
        var reportedError: Error?
        coordinator.onError = { reportedError = $0 }

        try await coordinator.handleManualToggleAction()
        audioRecordingService.onMaximumDurationReached?()
        await Task.yield()

        XCTAssertEqual(audioRecordingService.stopRecordingCallCount, 1)
        XCTAssertEqual(reportedError as? VoiceDictationTestError, .failed)
        XCTAssertEqual(pillPresenter.hideCallCount, 1)
    }

    func testBlankTranscriptIsRejectedAsInvalidProviderResponse() async throws {
        let microphoneAccess = FakeMicrophoneAccessProvider(result: true)
        let audioRecordingService = FakeAudioRecordingService(payload: RecordedAudioPayload(data: Data("audio".utf8), mimeType: "audio/wav"))
        let coordinator = DictateCoordinator(
            microphoneAccess: microphoneAccess,
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: FakeVoiceRecordingPillPresenter(),
            router: VoiceDictationFakeRouter(result: .success(.text("   \n"))),
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleManualToggleAction()

        do {
            try await coordinator.handleManualToggleAction()
            XCTFail("Expected invalid provider response error")
        } catch {
            XCTAssertEqual(error as? DictateCoordinatorError, .invalidProviderResponse)
        }
    }

    func testPushToTalkKeyDownStartsRecording() async throws {
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let coordinator = DictateCoordinator(
            microphoneAccess: FakeMicrophoneAccessProvider(result: true),
            audioRecordingService: FakeAudioRecordingService(),
            recordingPillPresenter: pillPresenter,
            router: VoiceDictationFakeRouter(result: .success(.text("ignored"))),
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handlePushToTalkKeyDown()

        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(pillPresenter.recordingStates, [.passiveRecording(level: 0)])
    }

    func testRegularHotKeyToggleStartsRecordingWithInteractivePill() async throws {
        let pillPresenter = FakeVoiceRecordingPillPresenter()
        let coordinator = DictateCoordinator(
            microphoneAccess: FakeMicrophoneAccessProvider(result: true),
            audioRecordingService: FakeAudioRecordingService(),
            recordingPillPresenter: pillPresenter,
            router: VoiceDictationFakeRouter(result: .success(.text("ignored"))),
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleRegularHotKeyToggleAction()

        XCTAssertEqual(coordinator.state, .recording)
        XCTAssertEqual(pillPresenter.recordingStates, [.interactiveRecording(level: 0)])
    }

    func testRegularHotKeyToggleStopsItsOwnRecordingAndTranscribes() async throws {
        let audioRecordingService = FakeAudioRecordingService(payload: RecordedAudioPayload(data: Data("audio".utf8), mimeType: "audio/wav"))
        let textInteraction = VoiceDictationFakeTextInteraction()
        let coordinator = DictateCoordinator(
            microphoneAccess: FakeMicrophoneAccessProvider(result: true),
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: FakeVoiceRecordingPillPresenter(),
            router: VoiceDictationFakeRouter(result: .success(.text("Regular mode transcript"))),
            textInteraction: textInteraction,
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleRegularHotKeyToggleAction()
        try await coordinator.handleRegularHotKeyToggleAction()

        XCTAssertEqual(audioRecordingService.stopRecordingCallCount, 1)
        XCTAssertEqual(textInteraction.replacedText, "Regular mode transcript")
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testPushToTalkKeyUpStopsRecordingAndTranscribes() async throws {
        let audioRecordingService = FakeAudioRecordingService(payload: RecordedAudioPayload(data: Data("audio".utf8), mimeType: "audio/wav"))
        let textInteraction = VoiceDictationFakeTextInteraction()
        let coordinator = DictateCoordinator(
            microphoneAccess: FakeMicrophoneAccessProvider(result: true),
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: FakeVoiceRecordingPillPresenter(),
            router: VoiceDictationFakeRouter(result: .success(.text("Push to talk transcript"))),
            textInteraction: textInteraction,
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handlePushToTalkKeyDown()
        try await coordinator.handlePushToTalkKeyUp()

        XCTAssertEqual(audioRecordingService.stopRecordingCallCount, 1)
        XCTAssertEqual(textInteraction.replacedText, "Push to talk transcript")
        XCTAssertEqual(coordinator.state, .idle)
    }

    func testPushToTalkKeyUpDoesNotStopMenuTriggeredRecording() async throws {
        let audioRecordingService = FakeAudioRecordingService()
        let coordinator = DictateCoordinator(
            microphoneAccess: FakeMicrophoneAccessProvider(result: true),
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: FakeVoiceRecordingPillPresenter(),
            router: VoiceDictationFakeRouter(result: .success(.text("ignored"))),
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleManualToggleAction()
        try await coordinator.handlePushToTalkKeyUp()

        XCTAssertEqual(audioRecordingService.stopRecordingCallCount, 0)
        XCTAssertEqual(coordinator.state, .recording)
    }

    func testRegularHotKeyToggleDoesNotStopMenuTriggeredRecording() async throws {
        let audioRecordingService = FakeAudioRecordingService()
        let coordinator = DictateCoordinator(
            microphoneAccess: FakeMicrophoneAccessProvider(result: true),
            audioRecordingService: audioRecordingService,
            recordingPillPresenter: FakeVoiceRecordingPillPresenter(),
            router: VoiceDictationFakeRouter(result: .success(.text("ignored"))),
            textInteraction: VoiceDictationFakeTextInteraction(),
            settingsStore: VoiceDictationSettingsStore()
        )

        try await coordinator.handleManualToggleAction()
        try await coordinator.handleRegularHotKeyToggleAction()

        XCTAssertEqual(audioRecordingService.stopRecordingCallCount, 0)
        XCTAssertEqual(coordinator.state, .recording)
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
    private(set) var recordingStates: [VoiceRecordingPillState] = []
    private(set) var showTranscribingCallCount = 0
    private(set) var hideCallCount = 0

    func showInteractiveRecording(level: Float) {
        recordingStates.append(.interactiveRecording(level: level))
    }

    func showPassiveRecording(level: Float) {
        recordingStates.append(.passiveRecording(level: level))
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

    func checkAccess(for selection: LLMModelSelection) async throws -> LLMProviderHealth {
        LLMProviderHealth(providerID: selection.providerID, state: .available, message: "Ready")
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
    var settings: LLMSettings = {
        var settings = LLMSettings.empty()
        settings.voice.selectedModel = LLMModelSelection(providerID: .gemini, modelID: "voice-model-gemini")
        return settings
    }()

    func loadSettings() -> LLMSettings {
        settings
    }

    func saveSettings(_ settings: LLMSettings) {
        self.settings = settings
    }
}
