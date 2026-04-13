import AVFoundation
import Foundation
import StewardCore

@MainActor
enum DictateWorkflowState: Equatable {
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
protocol DictateCoordinating: AnyObject {
    var onStateChanged: ((DictateWorkflowState) -> Void)? { get set }
    var onError: ((Error) -> Void)? { get set }

    func handleManualToggleAction() async throws
    func handleHotKeyDown() async throws
    func handleHotKeyUp() async throws
}

enum DictateCoordinatorError: LocalizedError, Equatable {
    case permissionDenied
    case providerUnavailable(String)
    case invalidProviderResponse
    case insertionFailedCopiedToClipboard

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "Microphone permission is required for Dictate."
        case .providerUnavailable(let message):
            return message
        case .invalidProviderResponse:
            return "Provider returned an invalid Dictate response."
        case .insertionFailedCopiedToClipboard:
            return "Dictate copied the transcript to the clipboard because it could not insert it into the focused app."
        }
    }
}

@MainActor
final class DictateCoordinator: DictateCoordinating {
    private struct PendingTranscriptionConfiguration {
        let selection: LLMModelSelection
        let options: VoiceTranscriptionOptions
    }

    private enum RecordingSource {
        case manualToggle
        case hotKeyHold
        case hotKeyLatched
    }

    var onStateChanged: ((DictateWorkflowState) -> Void)?
    var onError: ((Error) -> Void)?

    private let microphoneAccess: any MicrophoneAccessProviding
    private let audioRecordingService: any AudioRecordingProviding
    private let recordingPillPresenter: any VoiceRecordingPillPresenting
    private let router: any LLMRouting
    private let textInteraction: any TextInteractionPerforming
    private let settingsStore: any AppSettingsProviding
    private let clock: ContinuousClock
    private let hotKeyHoldThreshold: Duration
    private let hotKeyDoublePressWindow: Duration
    private let sleeper: @Sendable (Duration) async -> Void

    private(set) var state: DictateWorkflowState = .idle {
        didSet {
            onStateChanged?(state)
        }
    }
    private var recordingSource: RecordingSource?
    private var pendingTranscriptionConfiguration: PendingTranscriptionConfiguration?
    private var lastRecordingLevel: Float = 0
    private var hotKeyPressStartedAt: ContinuousClock.Instant?
    private var hotKeyDoublePressExpiresAt: ContinuousClock.Instant?
    private var hotKeyDoublePressTask: Task<Void, Never>?
    private var shouldIgnoreNextHotKeyUp = false

    init(
        microphoneAccess: any MicrophoneAccessProviding,
        audioRecordingService: any AudioRecordingProviding,
        recordingPillPresenter: any VoiceRecordingPillPresenting,
        router: any LLMRouting,
        textInteraction: any TextInteractionPerforming,
        settingsStore: any AppSettingsProviding,
        clock: ContinuousClock = ContinuousClock(),
        hotKeyHoldThreshold: Duration = .milliseconds(200),
        hotKeyDoublePressWindow: Duration = .milliseconds(250),
        sleeper: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.microphoneAccess = microphoneAccess
        self.audioRecordingService = audioRecordingService
        self.recordingPillPresenter = recordingPillPresenter
        self.router = router
        self.textInteraction = textInteraction
        self.settingsStore = settingsStore
        self.clock = clock
        self.hotKeyHoldThreshold = hotKeyHoldThreshold
        self.hotKeyDoublePressWindow = hotKeyDoublePressWindow
        self.sleeper = sleeper

        audioRecordingService.onLevelChanged = { [weak self] level in
            guard let self, self.state == .recording else {
                return
            }

            self.lastRecordingLevel = level
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

    func handleHotKeyDown() async throws {
        switch state {
        case .idle:
            try await startRecording(triggeredBy: .hotKeyHold)
            hotKeyPressStartedAt = clock.now
        case .recording:
            guard isHotKeyRecording else {
                return
            }

            if recordingSource == .hotKeyLatched {
                shouldIgnoreNextHotKeyUp = true
                hotKeyPressStartedAt = nil
                cancelPendingHotKeyDoublePressWindow()
                try await stopAndTranscribeRecording()
                return
            }

            guard
                let hotKeyDoublePressExpiresAt,
                clock.now <= hotKeyDoublePressExpiresAt
            else {
                return
            }

            cancelPendingHotKeyDoublePressWindow()
            hotKeyPressStartedAt = nil
            shouldIgnoreNextHotKeyUp = true
            recordingSource = .hotKeyLatched
            showRecordingPill(level: lastRecordingLevel)
        case .transcribing:
            return
        }
    }

    func handleHotKeyUp() async throws {
        guard state == .recording, isHotKeyRecording else {
            return
        }

        if shouldIgnoreNextHotKeyUp {
            shouldIgnoreNextHotKeyUp = false
            return
        }

        guard recordingSource == .hotKeyHold, let hotKeyPressStartedAt else {
            return
        }

        self.hotKeyPressStartedAt = nil
        if hotKeyPressStartedAt.duration(to: clock.now) >= hotKeyHoldThreshold {
            cancelPendingHotKeyDoublePressWindow()
            try await stopAndTranscribeRecording()
            return
        }

        armHotKeyDoublePressWindow()
    }

    private func startRecording(triggeredBy source: RecordingSource) async throws {
        let configuration = try voiceTranscriptionConfiguration()
        try await ensureProviderReady(for: configuration.selection)
        guard await microphoneAccess.ensureAccess() else {
            throw DictateCoordinatorError.permissionDenied
        }

        try audioRecordingService.startRecording()
        pendingTranscriptionConfiguration = configuration
        recordingSource = source
        lastRecordingLevel = 0
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
            guard let configuration = pendingTranscriptionConfiguration else {
                throw LLMRouterError.featureNotConfigured(LLMFeature.voice.displayName)
            }
            let request = LLMRequest(
                selection: configuration.selection,
                task: .voiceTranscription(
                    audioData: payload.data,
                    mimeType: payload.mimeType,
                    options: configuration.options
                )
            )

            let result = try await router.perform(request)

            guard let transcript = result.textValue?.trimmed, !transcript.isEmpty else {
                throw DictateCoordinatorError.invalidProviderResponse
            }

            do {
                try await textInteraction.replaceSelectedText(with: transcript)
            } catch {
                textInteraction.copyTextToClipboard(transcript)
                throw DictateCoordinatorError.insertionFailedCopiedToClipboard
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
        clearHotKeyGestureState()
        recordingSource = nil
        pendingTranscriptionConfiguration = nil
        recordingPillPresenter.hide()
        transition(to: .idle)
    }

    private func showRecordingPill(level: Float) {
        switch recordingSource {
        case .hotKeyHold:
            recordingPillPresenter.showPassiveRecording(level: level)
        case .manualToggle, .hotKeyLatched:
            recordingPillPresenter.showInteractiveRecording(level: level)
        case nil:
            recordingPillPresenter.showInteractiveRecording(level: level)
        }
    }

    private var isHotKeyRecording: Bool {
        switch recordingSource {
        case .hotKeyHold, .hotKeyLatched:
            return true
        case .manualToggle, nil:
            return false
        }
    }

    private func armHotKeyDoublePressWindow() {
        cancelPendingHotKeyDoublePressWindow()

        let hotKeyDoublePressExpiresAt = clock.now.advanced(by: hotKeyDoublePressWindow)
        self.hotKeyDoublePressExpiresAt = hotKeyDoublePressExpiresAt
        hotKeyDoublePressTask = Task { @MainActor [weak self] in
            guard let self else {
                return
            }

            await self.sleeper(self.hotKeyDoublePressWindow)
            guard
                !Task.isCancelled,
                self.state == .recording,
                self.recordingSource == .hotKeyHold,
                self.hotKeyDoublePressExpiresAt == hotKeyDoublePressExpiresAt
            else {
                return
            }

            self.hotKeyDoublePressTask = nil
            self.hotKeyDoublePressExpiresAt = nil
            await self.cancelRecording()
        }
    }

    private func cancelPendingHotKeyDoublePressWindow() {
        hotKeyDoublePressTask?.cancel()
        hotKeyDoublePressTask = nil
        hotKeyDoublePressExpiresAt = nil
    }

    private func clearHotKeyGestureState() {
        hotKeyPressStartedAt = nil
        shouldIgnoreNextHotKeyUp = false
        cancelPendingHotKeyDoublePressWindow()
    }

    private func transition(to newState: DictateWorkflowState) {
        guard state != newState else {
            return
        }

        state = newState
    }

    private func voiceTranscriptionConfiguration() throws -> PendingTranscriptionConfiguration {
        let voiceSettings = settingsStore.loadSettings().voice
        guard let selection = voiceSettings.selectedModel, LLMModelCatalog.supports(selection, feature: .voice) else {
            throw LLMRouterError.featureNotConfigured(LLMFeature.voice.displayName)
        }

        return PendingTranscriptionConfiguration(
            selection: selection,
            options: VoiceTranscriptionOptions(
                preferredRecognitionLanguages: voiceSettings.preferredRecognitionLanguages,
                translateToLanguageEnabled: voiceSettings.translateToLanguageEnabled,
                translationTargetLanguage: voiceSettings.translationTargetLanguage,
                customInstructions: voiceSettings.activeMode.customInstructions
            )
        )
    }

    private func ensureProviderReady(for selection: LLMModelSelection) async throws {
        let health = try await router.checkAccess(for: selection)
        guard health.hasAccess else {
            switch health.state {
            case .notConfigured:
                throw LLMRouterError.providerNotConfigured(selection.providerID)
            default:
                throw DictateCoordinatorError.providerUnavailable(health.message)
            }
        }
    }
}
