import AppKit
import ApplicationServices
import Foundation
import ScreenCaptureKit

@MainActor
protocol ClipboardChangeSuppressing: AnyObject {
    func suppressNextClipboardChanges(_ count: Int)
}

extension ClipboardMonitor: ClipboardChangeSuppressing {}

@MainActor
protocol TextInteractionPerforming: AnyObject {
    func getSelectedText() async throws -> String?
    func replaceSelectedText(with newText: String) async throws
    func copyTextToClipboard(_ text: String)
}

enum TextInteractionError: LocalizedError {
    case accessibilityPermissionDenied
    case couldNotReplaceSelectedText

    var errorDescription: String? {
        switch self {
        case .accessibilityPermissionDenied:
            return "Accessibility permission is required to read or replace selected text."
        case .couldNotReplaceSelectedText:
            return "Steward could not replace the selected text in the current app."
        }
    }
}

protocol PasteboardControlling: AnyObject {
    var changeCount: Int { get }
    func string(forType dataType: NSPasteboard.PasteboardType) -> String?
    @discardableResult
    func clearContents() -> Int
    @discardableResult
    func setString(_ string: String, forType dataType: NSPasteboard.PasteboardType) -> Bool
}

extension NSPasteboard: PasteboardControlling {}

protocol TextInteractionEventPosting {
    func postCopyCommand()
    func postPasteCommand()
}

struct SystemTextInteractionEventPoster: TextInteractionEventPosting {
    func postCopyCommand() {
        postCommand(for: 0x08)
    }

    func postPasteCommand() {
        postCommand(for: 0x09)
    }

    private func postCommand(for virtualKey: CGKeyCode) {
        let source = CGEventSource(stateID: .hidSystemState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: virtualKey, keyDown: false)

        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}

protocol AccessibilityTextInteracting {
    func isProcessTrusted() -> Bool
    func selectedText() -> String?
    func replaceSelectedText(with newText: String) -> Bool
}

struct SystemAccessibilityTextInteraction: AccessibilityTextInteracting {
    func isProcessTrusted() -> Bool {
        AXIsProcessTrusted()
    }

    func selectedText() -> String? {
        guard let focusedElement = focusedElement() else {
            return nil
        }

        if let selectedText = stringAttribute(kAXSelectedTextAttribute, from: focusedElement),
            !selectedText.isEmpty
        {
            return selectedText
        }

        guard let selectedRange = selectedTextRange(from: focusedElement), selectedRange.length > 0 else {
            return nil
        }

        return stringForRange(selectedRange, from: focusedElement)
    }

    func replaceSelectedText(with newText: String) -> Bool {
        guard
            let focusedElement = focusedElement(),
            let selectedRange = selectedTextRange(from: focusedElement),
            selectedRange.location != kCFNotFound
        else {
            return false
        }

        guard let fullText = stringAttribute(kAXValueAttribute, from: focusedElement) else {
            return false
        }

        let fullNSString = fullText as NSString
        let replacementRange = NSRange(location: selectedRange.location, length: selectedRange.length)
        guard NSMaxRange(replacementRange) <= fullNSString.length else {
            return false
        }

        let updatedText = fullNSString.replacingCharacters(in: replacementRange, with: newText)
        let setValueResult = AXUIElementSetAttributeValue(
            focusedElement,
            kAXValueAttribute as CFString,
            updatedText as CFTypeRef
        )
        guard setValueResult == .success else {
            return false
        }

        var insertionRange = CFRange(location: selectedRange.location + (newText as NSString).length, length: 0)
        if let selectionValue = AXValueCreate(.cfRange, &insertionRange) {
            _ = AXUIElementSetAttributeValue(
                focusedElement,
                kAXSelectedTextRangeAttribute as CFString,
                selectionValue
            )
        }

        return true
    }

    private func focusedElement() -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var focusedElement: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &focusedElement
        )

        guard result == .success, let focusedElement else {
            return nil
        }

        return (focusedElement as! AXUIElement)
    }

    private func stringAttribute(_ attribute: String, from element: AXUIElement) -> String? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, attribute as CFString, &value)
        guard result == .success, let stringValue = value as? String else {
            return nil
        }

        return stringValue
    }

    private func selectedTextRange(from element: AXUIElement) -> CFRange? {
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, &value)
        guard result == .success, let value else {
            return nil
        }

        let axValue = value as! AXValue
        guard AXValueGetType(axValue) == .cfRange else {
            return nil
        }

        var range = CFRange()
        guard AXValueGetValue(axValue, .cfRange, &range) else {
            return nil
        }

        return range
    }

    private func stringForRange(_ range: CFRange, from element: AXUIElement) -> String? {
        var mutableRange = range
        guard let rangeValue = AXValueCreate(.cfRange, &mutableRange) else {
            return nil
        }

        var value: CFTypeRef?
        let result = AXUIElementCopyParameterizedAttributeValue(
            element,
            kAXStringForRangeParameterizedAttribute as CFString,
            rangeValue,
            &value
        )

        guard result == .success, let stringValue = value as? String else {
            return nil
        }

        return stringValue
    }
}

@MainActor
final class SystemTextInteractionService: TextInteractionPerforming {
    private struct PasteboardSnapshot {
        let text: String?
        let changeCount: Int
    }

    private let pasteboard: PasteboardControlling
    private weak var suppression: ClipboardChangeSuppressing?
    private let accessibilityTextInteraction: AccessibilityTextInteracting
    private let eventPoster: TextInteractionEventPosting
    private let sleeper: @Sendable (Duration) async -> Void

    init(
        pasteboard: PasteboardControlling = NSPasteboard.general,
        suppression: ClipboardChangeSuppressing?,
        accessibilityTextInteraction: AccessibilityTextInteracting = SystemAccessibilityTextInteraction(),
        eventPoster: TextInteractionEventPosting = SystemTextInteractionEventPoster(),
        sleeper: @escaping @Sendable (Duration) async -> Void = { duration in
            try? await Task.sleep(for: duration)
        }
    ) {
        self.pasteboard = pasteboard
        self.suppression = suppression
        self.accessibilityTextInteraction = accessibilityTextInteraction
        self.eventPoster = eventPoster
        self.sleeper = sleeper
    }

    func getSelectedText() async throws -> String? {
        guard accessibilityTextInteraction.isProcessTrusted() else {
            throw TextInteractionError.accessibilityPermissionDenied
        }

        if let axSelectedText = accessibilityTextInteraction.selectedText(), !axSelectedText.isEmpty {
            return axSelectedText
        }

        return await selectedTextUsingClipboardFallback()
    }

    func replaceSelectedText(with newText: String) async throws {
        guard accessibilityTextInteraction.isProcessTrusted() else {
            throw TextInteractionError.accessibilityPermissionDenied
        }

        if accessibilityTextInteraction.replaceSelectedText(with: newText) {
            return
        }

        try await replaceSelectedTextUsingClipboardFallback(with: newText)
    }

    func copyTextToClipboard(_ text: String) {
        _ = writePasteboard(text)
    }

    private func selectedTextUsingClipboardFallback() async -> String? {
        let originalSnapshot = currentPasteboardSnapshot()
        suppression?.suppressNextClipboardChanges(1)
        eventPoster.postCopyCommand()

        guard let copiedChangeCount = await waitForPasteboardChange(after: originalSnapshot.changeCount) else {
            return nil
        }

        let selectedText = pasteboard.string(forType: .string)
        restorePasteboardIfUnchanged(
            from: originalSnapshot,
            expectedChangeCount: copiedChangeCount,
            expectedText: selectedText
        )

        return selectedText
    }

    private func replaceSelectedTextUsingClipboardFallback(with newText: String) async throws {
        let originalSnapshot = currentPasteboardSnapshot()
        let temporaryChangeCount = writePasteboard(newText)
        eventPoster.postPasteCommand()

        await sleeper(.milliseconds(300))
        restorePasteboardIfUnchanged(
            from: originalSnapshot,
            expectedChangeCount: temporaryChangeCount,
            expectedText: newText
        )

        if pasteboard.changeCount == temporaryChangeCount && pasteboard.string(forType: .string) == newText {
            throw TextInteractionError.couldNotReplaceSelectedText
        }
    }

    private func currentPasteboardSnapshot() -> PasteboardSnapshot {
        PasteboardSnapshot(text: pasteboard.string(forType: .string), changeCount: pasteboard.changeCount)
    }

    @discardableResult
    private func writePasteboard(_ text: String?) -> Int {
        let suppressedChangeCount = text == nil ? 1 : 2
        suppression?.suppressNextClipboardChanges(suppressedChangeCount)
        pasteboard.clearContents()

        if let text {
            _ = pasteboard.setString(text, forType: .string)
        }

        return pasteboard.changeCount
    }

    private func waitForPasteboardChange(
        after changeCount: Int,
        timeoutMilliseconds: Int = 400,
        pollMilliseconds: Int = 20
    ) async -> Int? {
        for _ in 0..<(timeoutMilliseconds / pollMilliseconds) {
            if pasteboard.changeCount != changeCount {
                return pasteboard.changeCount
            }

            await sleeper(.milliseconds(pollMilliseconds))
        }

        return pasteboard.changeCount == changeCount ? nil : pasteboard.changeCount
    }

    private func restorePasteboardIfUnchanged(
        from snapshot: PasteboardSnapshot,
        expectedChangeCount: Int,
        expectedText: String?
    ) {
        guard pasteboard.changeCount == expectedChangeCount else {
            return
        }

        guard pasteboard.string(forType: .string) == expectedText else {
            return
        }

        _ = writePasteboard(snapshot.text)
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

protocol ScreenCaptureProviding: Sendable {
    func ensureScreenCaptureAccess() -> Bool
    func captureSelectionImageData(request: ScreenCaptureRequest, selectionRect: CGRect) async -> Data?
}

struct SystemScreenCaptureService: ScreenCaptureProviding {
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

        let shareableContent: SCShareableContent
        do {
            shareableContent = try await SCShareableContent.currentProcess
        } catch {
            return nil
        }

        guard let display = shareableContent.displays.first(where: { $0.displayID == displayID }) else {
            return nil
        }

        return await withCheckedContinuation { continuation in
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
