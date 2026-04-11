import AppKit
import SwiftUI

@main
struct StewardApp: App {
    @StateObject private var appState: AppState

    init() {
        let settingsStore = UserDefaultsLLMSettingsStore()
        let clipboardHistoryStore = ClipboardHistoryStore()
        let clipboardMonitor = ClipboardMonitor { record in
            clipboardHistoryStore.append(record)
        }
        let textInteractionService = SystemTextInteractionService(suppression: clipboardMonitor)
        let appSystemServices = AppSystemServices.live()
        let llmRouter = LLMRouter(
            settingsStore: settingsStore
        )
        let grammarCoordinator = GrammarCoordinator(
            router: llmRouter,
            textInteraction: textInteractionService,
            settingsStore: settingsStore
        )
        let screenOCRCoordinator = ScreenOCRCoordinator(
            router: llmRouter,
            textInteraction: textInteractionService,
            captureService: SystemScreenCaptureService(),
            selectionPresenter: ScreenSelectionOverlayController(),
            settingsStore: settingsStore
        )
        let voiceDictationCoordinator = VoiceDictationCoordinator(
            microphoneAccess: SystemMicrophoneAccessService(),
            audioRecordingService: SystemAudioRecordingService(),
            recordingPillPresenter: VoiceRecordingPillController(),
            router: llmRouter,
            textInteraction: textInteractionService,
            settingsStore: settingsStore
        )

        _appState = StateObject(
            wrappedValue: AppState(
                settingsStore: settingsStore,
                clipboardHistoryStore: clipboardHistoryStore,
                clipboardMonitor: clipboardMonitor,
                llmRouter: llmRouter,
                grammarCoordinator: grammarCoordinator,
                screenOCRCoordinator: screenOCRCoordinator,
                voiceDictationCoordinator: voiceDictationCoordinator,
                appSystemServices: appSystemServices
            )
        )
    }

    var body: some Scene {
        MenuBarExtra {
            AppMenuView()
                .environmentObject(appState)
        } label: {
            Image(nsImage: appState.statusBarIconImage)
                .accessibilityLabel("Steward")
        }
        .menuBarExtraStyle(.menu)

        Window("Clipboard History", id: "history") {
            ClipboardHistoryView(store: appState.clipboardHistoryStore)
        }
        .defaultSize(width: 860, height: 520)

        Settings {
            SettingsView(
                appState: appState,
                settingsStore: appState.settingsStore,
                clipboardHistoryStore: appState.clipboardHistoryStore
            ) {
                appState.settingsDidChange()
            }
        }
    }
}

private struct AppMenuView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openSettings) private var openSettings
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Refine") {
                appState.runGrammarAction()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Capture") {
                appState.runScreenOCRAction()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Button("Dictate") {
                appState.runVoiceDictationAction()
            }

            Divider()

            Text(appState.activityStatusTitle)
                .foregroundColor(.secondary)

            Button(appState.grammarStatusTitle) {
                appState.checkGrammarProviderStatus()
            }

            Button(appState.ocrStatusTitle) {
                appState.checkOCRProviderStatus()
            }

            Button(appState.voiceStatusTitle) {
                appState.checkVoiceProviderStatus()
            }

            if appState.shouldShowPermissionActions {
                Divider()

                if !appState.accessibilityPermissionGranted {
                    Button(appState.accessibilityStatusTitle) {
                        appState.openAccessibilityPrivacySettings()
                    }
                }

                if !appState.microphonePermissionGranted {
                    Button(appState.microphoneStatusTitle) {
                        appState.openMicrophonePrivacySettings()
                    }
                }

                if !appState.screenRecordingPermissionGranted {
                    Button(appState.screenRecordingStatusTitle) {
                        appState.openScreenRecordingPrivacySettings()
                    }
                }
            }

            if let shortcutRegistrationMessage = appState.shortcutRegistrationMessage {
                Divider()

                Text(shortcutRegistrationMessage)
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            Button("Clipboard History") {
                openWindow(id: "history")
                NSApp.activate(ignoringOtherApps: true)
            }

            Button("Preferences...") {
                Task { @MainActor in
                    openSettings()
                    NSApp.activate(ignoringOtherApps: true)
                }
            }
            .keyboardShortcut(",", modifiers: [.command])

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
        .onAppear {
            appState.refreshPermissionStatuses()
        }
    }
}
