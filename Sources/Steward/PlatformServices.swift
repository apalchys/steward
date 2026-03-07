import AppKit
import Foundation
import ScreenCaptureKit

protocol ClipboardChangeSuppressing: AnyObject {
    func suppressNextClipboardChanges(_ count: Int)
}

extension ClipboardMonitor: ClipboardChangeSuppressing {}

protocol TextInteractionPerforming: AnyObject, Sendable {
    func getSelectedText() async -> String?
    func replaceSelectedText(with newText: String)
    func copyTextToClipboard(_ text: String)
}

final class SystemTextInteractionService: TextInteractionPerforming, @unchecked Sendable {
    private let pasteboard: NSPasteboard
    private weak var suppression: ClipboardChangeSuppressing?

    init(pasteboard: NSPasteboard = .general, suppression: ClipboardChangeSuppressing?) {
        self.pasteboard = pasteboard
        self.suppression = suppression
    }

    func getSelectedText() async -> String? {
        let oldPasteboardContent = pasteboard.string(forType: .string)
        suppression?.suppressNextClipboardChanges(1)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        try? await Task.sleep(for: .milliseconds(200))

        let selectedText = pasteboard.string(forType: .string)

        if let oldPasteboardContent {
            suppression?.suppressNextClipboardChanges(2)
            pasteboard.clearContents()
            pasteboard.setString(oldPasteboardContent, forType: .string)
        }

        return selectedText
    }

    func replaceSelectedText(with newText: String) {
        let oldPasteboardContent = pasteboard.string(forType: .string)

        suppression?.suppressNextClipboardChanges(2)
        pasteboard.clearContents()
        pasteboard.setString(newText, forType: .string)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            guard let self, let oldPasteboardContent else {
                return
            }

            self.suppression?.suppressNextClipboardChanges(2)
            self.pasteboard.clearContents()
            self.pasteboard.setString(oldPasteboardContent, forType: .string)
        }
    }

    func copyTextToClipboard(_ text: String) {
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}

struct ScreenCaptureRequest: Sendable {
    let displayID: CGDirectDisplayID
    let screenFrame: CGRect
    let scaleFactor: CGFloat

    @MainActor
    init?(screen: NSScreen) {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }
        self.displayID = CGDirectDisplayID(screenNumber.uint32Value)
        self.screenFrame = screen.frame
        self.scaleFactor = max(screen.backingScaleFactor, 1)
    }
}

protocol ScreenCaptureProviding: AnyObject, Sendable {
    func ensureScreenCaptureAccess() -> Bool
    func captureSelectionImageData(request: ScreenCaptureRequest, selectionRect: CGRect) async -> Data?
}

final class SystemScreenCaptureService: ScreenCaptureProviding, @unchecked Sendable {
    func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    func captureSelectionImageData(request: ScreenCaptureRequest, selectionRect: CGRect) async -> Data? {
        let scaleFactor = request.scaleFactor
        let screenFrame = request.screenFrame
        let streamWidth = max(1, Int(screenFrame.width * scaleFactor))
        let streamHeight = max(1, Int(screenFrame.height * scaleFactor))
        let displayID = request.displayID

        return await withCheckedContinuation { continuation in
            SCShareableContent.getCurrentProcessShareableContent { shareableContent, error in
                guard error == nil,
                    let shareableContent,
                    let display = shareableContent.displays.first(where: { $0.displayID == displayID })
                else {
                    continuation.resume(returning: nil)
                    return
                }

                let streamConfiguration = SCStreamConfiguration()
                streamConfiguration.captureResolution = .best
                streamConfiguration.showsCursor = false
                streamConfiguration.width = streamWidth
                streamConfiguration.height = streamHeight

                let contentFilter = SCContentFilter(
                    display: display, excludingApplications: [], exceptingWindows: [])
                SCScreenshotManager.captureImage(
                    contentFilter: contentFilter, configuration: streamConfiguration
                ) { image, captureError in
                    guard captureError == nil, let image else {
                        continuation.resume(returning: nil)
                        return
                    }

                    let croppedData = Self.croppedImageData(
                        from: image, screenFrame: screenFrame, selectionRect: selectionRect)
                    continuation.resume(returning: croppedData)
                }
            }
        }
    }

    private static func croppedImageData(
        from displayImage: CGImage, screenFrame: CGRect, selectionRect: CGRect
    ) -> Data? {
        let relativeRect = CGRect(
            x: selectionRect.minX - screenFrame.minX,
            y: screenFrame.maxY - selectionRect.maxY,
            width: selectionRect.width,
            height: selectionRect.height
        )

        let scaleX = CGFloat(displayImage.width) / screenFrame.width
        let scaleY = CGFloat(displayImage.height) / screenFrame.height
        let cropRect = CGRect(
            x: relativeRect.minX * scaleX,
            y: relativeRect.minY * scaleY,
            width: relativeRect.width * scaleX,
            height: relativeRect.height * scaleY
        ).integral
        let fullImageRect = CGRect(x: 0, y: 0, width: displayImage.width, height: displayImage.height)
        let clippedCropRect = cropRect.intersection(fullImageRect)

        guard !clippedCropRect.isNull,
            clippedCropRect.width > 0,
            clippedCropRect.height > 0,
            let croppedImage = displayImage.cropping(to: clippedCropRect)
        else {
            return nil
        }

        let bitmapRepresentation = NSBitmapImageRep(cgImage: croppedImage)
        return bitmapRepresentation.representation(using: .png, properties: [:])
    }

}
