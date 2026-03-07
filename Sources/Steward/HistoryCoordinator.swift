import AppKit
import SwiftUI

final class HistoryCoordinator: NSObject, NSWindowDelegate {
    private let store: ClipboardHistoryStore
    private var historyWindow: NSWindow?

    init(store: ClipboardHistoryStore) {
        self.store = store
    }

    func openHistoryWindow() {
        if let historyWindow, historyWindow.isVisible {
            historyWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let historyWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 520),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        historyWindow.isReleasedWhenClosed = false
        historyWindow.hidesOnDeactivate = false
        historyWindow.canHide = true
        historyWindow.title = "History"
        historyWindow.center()
        historyWindow.delegate = self
        historyWindow.contentViewController = NSHostingController(
            rootView: ClipboardHistoryView(store: store)
        )

        self.historyWindow = historyWindow
        historyWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow,
            closingWindow === historyWindow
        else {
            return
        }

        historyWindow = nil
    }
}
