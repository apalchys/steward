import AppKit
import SwiftUI

@main
struct StewardApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        MenuBarExtra {
            AppMenuView()
                .environmentObject(appState)
        } label: {
            Image(nsImage: appState.statusBarIconImage)
                .accessibilityLabel("Steward")
        }
        .menuBarExtraStyle(.menu)

        Window("History", id: "history") {
            ClipboardHistoryView(store: appState.clipboardHistoryStore)
        }
        .defaultSize(width: 860, height: 520)

        Settings {
            SettingsView(settingsStore: appState.settingsStore) {
                appState.settingsDidChange()
            }
        }
    }
}

private struct AppMenuView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            Button("Grammar Check") {
                appState.runGrammarAction()
            }
            .keyboardShortcut("f", modifiers: [.command, .shift])

            Button("Screen Text Capture") {
                appState.runScreenOCRAction()
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])

            Divider()

            Text(appState.activityStatusTitle)

            Button(appState.grammarStatusTitle) {
                appState.checkGrammarProviderStatus()
            }

            Button(appState.ocrStatusTitle) {
                appState.checkOCRProviderStatus()
            }

            Divider()

            Button("History") {
                openWindow(id: "history")
                NSApp.activate(ignoringOtherApps: true)
            }

            SettingsLink {
                Text("Preferences...")
            }

            Divider()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
