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

    func handleHotKeyPress() async throws
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

            self.recordingPillPresenter.showRecording(level: level)
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

    func handleHotKeyPress() async throws {
        switch state {
        case .idle:
            try await startRecording()
        case .recording:
            try await stopAndTranscribeRecording()
        case .transcribing:
            return
        }
    }

    private func startRecording() async throws {
        guard await microphoneAccess.ensureAccess() else {
            throw VoiceDictationCoordinatorError.permissionDenied
        }

        try audioRecordingService.startRecording()
        transition(to: .recording)
        recordingPillPresenter.showRecording(level: 0)
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
            let request = LLMRequest(
                providerID: voiceSettings.providerID,
                task: .voiceTranscription(
                    audioData: payload.data,
                    mimeType: payload.mimeType,
                    customInstructions: voiceSettings.customInstructions
                ),
                modelIDOverride: voiceSettings.modelID(for: voiceSettings.providerID)
            )

            let result = try await router.perform(request)

            guard let transcript = result.textValue else {
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
        recordingPillPresenter.hide()
        transition(to: .idle)
    }

    private func transition(to newState: VoiceDictationWorkflowState) {
        guard state != newState else {
            return
        }

        state = newState
    }
}
