import AppKit
import Foundation
import ScreenCaptureKit

protocol ClipboardChangeSuppressing: AnyObject {
    func suppressNextClipboardChanges(_ count: Int)
}

extension ClipboardMonitor: ClipboardChangeSuppressing {}

protocol TextInteractionPerforming: AnyObject {
    func getSelectedText() -> String?
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

    func getSelectedText() -> String? {
        let oldPasteboardContent = pasteboard.string(forType: .string)
        suppression?.suppressNextClipboardChanges(1)

        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)

        Thread.sleep(forTimeInterval: 0.2)

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

protocol ScreenCaptureProviding: AnyObject {
    func ensureScreenCaptureAccess() -> Bool
    func captureSelectionImageData(
        on screen: NSScreen,
        selectionRect: CGRect,
        completion: @escaping (Data?) -> Void
    )
}

final class SystemScreenCaptureService: ScreenCaptureProviding, @unchecked Sendable {
    func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    func captureSelectionImageData(
        on screen: NSScreen,
        selectionRect: CGRect,
        completion: @escaping (Data?) -> Void
    ) {
        guard let displayID = displayID(for: screen) else {
            completion(nil)
            return
        }

        SCShareableContent.getCurrentProcessShareableContent { [weak self] shareableContent, error in
            guard let self,
                error == nil,
                let shareableContent,
                let display = shareableContent.displays.first(where: { $0.displayID == displayID })
            else {
                completion(nil)
                return
            }

            let streamConfiguration = SCStreamConfiguration()
            streamConfiguration.captureResolution = .best
            streamConfiguration.showsCursor = false

            let scaleFactor = max(screen.backingScaleFactor, 1)
            streamConfiguration.width = max(1, Int(screen.frame.width * scaleFactor))
            streamConfiguration.height = max(1, Int(screen.frame.height * scaleFactor))

            let contentFilter = SCContentFilter(display: display, excludingApplications: [], exceptingWindows: [])
            SCScreenshotManager.captureImage(contentFilter: contentFilter, configuration: streamConfiguration) {
                [weak self] image, captureError in
                guard let self, captureError == nil, let image else {
                    completion(nil)
                    return
                }

                completion(self.croppedImageData(from: image, on: screen, selectionRect: selectionRect))
            }
        }
    }

    private func croppedImageData(from displayImage: CGImage, on screen: NSScreen, selectionRect: CGRect) -> Data? {
        let screenFrame = screen.frame
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

    private func displayID(for screen: NSScreen) -> CGDirectDisplayID? {
        guard let screenNumber = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
            return nil
        }

        return CGDirectDisplayID(screenNumber.uint32Value)
    }
}
