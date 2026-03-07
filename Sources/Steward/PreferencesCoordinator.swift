import AppKit
import SwiftUI

final class PreferencesCoordinator: NSObject, NSWindowDelegate {
    private var preferencesWindow: NSWindow?

    func openPreferencesWindow() {
        if let preferencesWindow, preferencesWindow.isVisible {
            preferencesWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 520),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        settingsWindow.isReleasedWhenClosed = false
        settingsWindow.hidesOnDeactivate = false
        settingsWindow.canHide = true
        settingsWindow.title = "Preferences"
        settingsWindow.center()
        settingsWindow.delegate = self
        settingsWindow.contentViewController = NSHostingController(rootView: SettingsView())

        self.preferencesWindow = settingsWindow
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
            closingWindow === preferencesWindow
        else {
            return
        }

        preferencesWindow = nil
    }
}
