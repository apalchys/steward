import AVFoundation
import Foundation

@MainActor
enum VoiceDictationWorkflowState: Equatable {
    case idle
    case recording
    case transcribing
}

@MainActor
protocol MicrophoneAccessProviding: AnyObject {
    func ensureAccess() async -> Bool
}

@MainActor
final class SystemMicrophoneAccessService: MicrophoneAccessProviding {
    func ensureAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            return true
        case .notDetermined:
            return await AVCaptureDevice.requestAccess(for: .audio)
        case .denied, .restricted:
            return false
        @unknown default:
            return false
        }
    }
}

@MainActor
protocol VoiceDictationCoordinating: AnyObject {
    var onStateChanged: ((VoiceDictationWorkflowState) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func handleManualToggleAction() async throws
    func handlePushToTalkKeyDown() async throws
    func handlePushToTalkKeyUp() async throws
}

enum VoiceDictationCoordinatorError: LocalizedError, Equatable {
    case permissionDenied
    case invalidProviderResponse
    case insertionFailedCopiedToClipboard

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required for Voice Dictation."
        case .invalidProviderResponse:
            return "Provider returned an invalid Voice Dictation response."
        case .insertionFailedCopiedToClipboard:
            return
                "Voice Dictation copied the transcript to the clipboard because it could not insert it into the focused app."
        }
    }
}

@MainActor
final class VoiceDictationCoordinator: VoiceDictationCoordinating {
    private enum RecordingSource {
        case pushToTalkHotKey
        case manualToggle
    }

    var onStateChanged: ((VoiceDictationWorkflowState) -> Void)?
    var onError: ((Error) -> Void)?

    private let microphoneAccess: any MicrophoneAccessProviding
    private let audioRecordingService: any AudioRecordingProviding
    private let recordingPillPresenter: any VoiceRecordingPillPresenting
    private let router: any LLMRouting
    private let textInteraction: any TextInteractionPerforming
    private let settingsStore: any AppSettingsProviding

    private(set) var state: VoiceDictationWorkflowState = .idle {
        didSet {
            onStateChanged?(state)
        }
    }
    private var recordingSource: RecordingSource?

    init(
        microphoneAccess: any MicrophoneAccessProviding,
        audioRecordingService: any AudioRecordingProviding,
        recordingPillPresenter: any VoiceRecordingPillPresenting,
        router: any LLMRouting,
        textInteraction: any TextInteractionPerforming,
        settingsStore: any AppSettingsProviding
    ) {
        self.microphoneAccess = microphoneAccess
        self.audioRecordingService = audioRecordingService
        self.recordingPillPresenter = recordingPillPresenter
        self.router = router
        self.textInteraction = textInteraction
        self.settingsStore = settingsStore

        audioRecordingService.onLevelChanged = { [weak self] level in
            guard let self, self.state == .recording else {
                return
            }

            self.showRecordingPill(level: level)
        }
        audioRecordingService.onMaximumDurationReached = { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                do {
                    try await self.stopAndTranscribeRecording()
                } catch {
                    self.onError?(error)
                }
            }
        }
        recordingPillPresenter.onCancel = { [weak self] in
            Task { @MainActor in
                await self?.cancelRecording()
            }
        }
        recordingPillPresenter.onConfirm = { [weak self] in
            Task { @MainActor in
                guard let self else {
                    return
                }

                do {
                    try await self.stopAndTranscribeRecording()
                } catch {
                    self.onError?(error)
                }
            }
        }
    }

    func handleManualToggleAction() async throws {
        switch state {
        case .idle:
            try await startRecording(triggeredBy: .manualToggle)
        case .recording:
            guard recordingSource == .manualToggle else {
                return
            }

            try await stopAndTranscribeRecording()
        case .transcribing:
            return
        }
    }

    func handlePushToTalkKeyDown() async throws {
        guard state == .idle else {
            return
        }

        try await startRecording(triggeredBy: .pushToTalkHotKey)
    }

    func handlePushToTalkKeyUp() async throws {
        guard state == .recording, recordingSource == .pushToTalkHotKey else {
            return
        }

        try await stopAndTranscribeRecording()
    }

    private func startRecording(triggeredBy source: RecordingSource) async throws {
        guard await microphoneAccess.ensureAccess() else {
            throw VoiceDictationCoordinatorError.permissionDenied
        }

        try audioRecordingService.startRecording()
        recordingSource = source
        transition(to: .recording)
        showRecordingPill(level: 0)
    }

    private func stopAndTranscribeRecording() async throws {
        guard state == .recording else {
            return
        }

        transition(to: .transcribing)
        recordingPillPresenter.showTranscribing()

        do {
            let payload = try await audioRecordingService.stopRecording()
            let settings = settingsStore.loadSettings()
            let voiceSettings = settings.voice
            guard let selection = voiceSettings.selectedModel else {
                throw LLMRouterError.featureNotConfigured(LLMFeature.voice.displayName)
            }
            let request = LLMRequest(
                selection: selection,
                task: .voiceTranscription(
                    audioData: payload.data,
                    mimeType: payload.mimeType,
                    customInstructions: voiceSettings.customInstructions
                )
            )

            let result = try await router.perform(request)

            guard let transcript = result.textValue?.trimmed, !transcript.isEmpty else {
                throw VoiceDictationCoordinatorError.invalidProviderResponse
            }

            do {
                try await textInteraction.replaceSelectedText(with: transcript)
            } catch {
                textInteraction.copyTextToClipboard(transcript)
                throw VoiceDictationCoordinatorError.insertionFailedCopiedToClipboard
            }

            finishWorkflow()
        } catch {
            finishWorkflow()
            throw error
        }
    }

    private func cancelRecording() async {
        await audioRecordingService.cancelRecording()
        finishWorkflow()
    }

    private func finishWorkflow() {
        recordingSource = nil
        recordingPillPresenter.hide()
        transition(to: .idle)
    }

    private func showRecordingPill(level: Float) {
        switch recordingSource {
        case .pushToTalkHotKey:
            recordingPillPresenter.showPassiveRecording(level: level)
        case .manualToggle:
            recordingPillPresenter.showInteractiveRecording(level: level)
        case nil:
            recordingPillPresenter.showInteractiveRecording(level: level)
        }
    }

    private func transition(to newState: VoiceDictationWorkflowState) {
        guard state != newState else {
            return
        }

        state = newState
    }
}
