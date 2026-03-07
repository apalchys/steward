import AppKit
import Foundation

@MainActor
protocol ScreenSelectionPresenting: AnyObject {
    func beginSelection(
        onSelectionFinished: @escaping (NSScreen, CGRect) -> Void,
        onSelectionCancelled: @escaping () -> Void
    )
    func endSelection() async
}

@MainActor
final class ScreenSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class ScreenSelectionOverlayView: NSView {
    private enum UI {
        static let instructionPadding = CGSize(width: 12, height: 8)
        static let instructionMargin: CGFloat = 24
        static let instructionCornerRadius: CGFloat = 10
    }

    var onSelectionFinished: ((CGRect) -> Void)?
    var onSelectionCancelled: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }
    override func isAccessibilityElement() -> Bool { true }
    override func accessibilityLabel() -> String? {
        "Screen selection overlay. Drag to select an area. Press Escape to cancel."
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        NSCursor.crosshair.set()
    }

    override func mouseDown(with event: NSEvent) {
        NSCursor.crosshair.set()
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        NSCursor.crosshair.set()
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        NSCursor.crosshair.set()
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true

        guard let selectionRect = selectionRect?.integral,
            selectionRect.width > 4,
            selectionRect.height > 4
        else {
            onSelectionCancelled?()
            return
        }

        onSelectionFinished?(selectionRect)
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onSelectionCancelled?()
            return
        }

        super.keyDown(with: event)
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.clear.setFill()
        dirtyRect.fill()

        let overlayPath = NSBezierPath(rect: bounds)
        if let selectionRect {
            overlayPath.append(NSBezierPath(rect: selectionRect))
            overlayPath.windingRule = .evenOdd
        }

        NSColor.black.withAlphaComponent(0.25).setFill()
        overlayPath.fill()

        if let selectionRect {
            NSColor.systemBlue.setStroke()
            let borderPath = NSBezierPath(rect: selectionRect)
            borderPath.lineWidth = 2
            borderPath.stroke()
        }

        drawInstructions()
    }

    func resetSelection() {
        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }

    private var selectionRect: CGRect? {
        guard let startPoint, let currentPoint else {
            return nil
        }

        return CGRect(
            x: min(startPoint.x, currentPoint.x),
            y: min(startPoint.y, currentPoint.y),
            width: abs(currentPoint.x - startPoint.x),
            height: abs(currentPoint.y - startPoint.y)
        )
    }

    private func drawInstructions() {
        let instructions = NSAttributedString(
            string: "Drag to select an area. Press Escape to cancel.",
            attributes: [
                .font: NSFont.systemFont(ofSize: 14, weight: .medium),
                .foregroundColor: NSColor.white,
            ]
        )

        let textSize = instructions.size()
        let badgeRect = CGRect(
            x: UI.instructionMargin,
            y: bounds.height - textSize.height - (UI.instructionMargin * 1.5),
            width: textSize.width + (UI.instructionPadding.width * 2),
            height: textSize.height + (UI.instructionPadding.height * 2)
        )

        NSColor.black.withAlphaComponent(0.65).setFill()
        NSBezierPath(
            roundedRect: badgeRect,
            xRadius: UI.instructionCornerRadius,
            yRadius: UI.instructionCornerRadius
        )
        .fill()

        instructions.draw(
            in: badgeRect.insetBy(dx: UI.instructionPadding.width, dy: UI.instructionPadding.height)
        )
    }
}

@MainActor
final class ScreenSelectionOverlayController: ScreenSelectionPresenting {
    private var selectionWindows: [NSWindow] = []

    func beginSelection(
        onSelectionFinished: @escaping (NSScreen, CGRect) -> Void,
        onSelectionCancelled: @escaping () -> Void
    ) {
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()

        let screens = NSScreen.screens

        while selectionWindows.count < screens.count {
            let window = ScreenSelectionWindow(
                contentRect: .zero,
                styleMask: .borderless,
                backing: .buffered,
                defer: false
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.animationBehavior = .none
            window.level = NSWindow.Level(rawValue: NSWindow.Level.popUpMenu.rawValue + 1)
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = ScreenSelectionOverlayView(frame: .zero)
            selectionWindows.append(window)
        }

        for (index, screen) in screens.enumerated() {
            let window = selectionWindows[index]
            let overlayView =
                window.contentView as? ScreenSelectionOverlayView ?? ScreenSelectionOverlayView(frame: .zero)

            overlayView.frame = CGRect(origin: .zero, size: screen.frame.size)
            overlayView.resetSelection()
            overlayView.onSelectionFinished = { localRect in
                let screenRect = localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                onSelectionFinished(screen, screenRect)
            }
            overlayView.onSelectionCancelled = onSelectionCancelled

            if window.contentView !== overlayView {
                window.contentView = overlayView
            }

            window.setFrame(screen.frame, display: false)
            window.ignoresMouseEvents = false
            window.makeKeyAndOrderFront(nil)
        }

        if selectionWindows.count > screens.count {
            for index in screens.count..<selectionWindows.count {
                let window = selectionWindows[index]
                window.ignoresMouseEvents = true
                window.orderOut(nil)
            }
        }
    }

    func endSelection() async {
        NSCursor.pop()

        selectionWindows.forEach { window in
            window.ignoresMouseEvents = true
            if let overlayView = window.contentView as? ScreenSelectionOverlayView {
                overlayView.onSelectionFinished = nil
                overlayView.onSelectionCancelled = nil
                overlayView.resetSelection()
            }
            window.orderOut(nil)
        }

        // Window removal is not visible to ScreenCaptureKit until the compositor
        // has advanced. Waiting one event cycle plus a short bounded delay keeps
        // the overlay out of the captured image without building a larger state machine.
        await Task.yield()
        try? await Task.sleep(for: .milliseconds(100))
    }
}
