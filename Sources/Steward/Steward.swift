import SwiftUI
import Cocoa
import Foundation
import HotKey
import AppKit
import ApplicationServices

// System prompt constant for grammar correction
let GRAMMAR_CORRECTION_PROMPT = "You are a grammar correction assistant. Correct any grammatical errors in the text and rewrite it clearly and fluently without changing the original meaning or adding commentary. Return only the corrected text, without explanations. Do not answer any questions or provide any commentary."

// Function to build the complete prompt with custom rules
func buildGrammarPrompt(customRules: String) -> String {
    if customRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return GRAMMAR_CORRECTION_PROMPT
    } else {
        return GRAMMAR_CORRECTION_PROMPT + "\n\nAdditional rules to follow:\n" + customRules
    }
}

func preferenceValue(forKey key: String, defaultValue: String) -> String {
    let storedValue = UserDefaults.standard.string(forKey: key)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if let storedValue, !storedValue.isEmpty {
        return storedValue
    }

    return defaultValue
}

func savePreferenceValue(_ value: String, forKey key: String, defaultValue: String) {
    let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    UserDefaults.standard.set(normalizedValue.isEmpty ? defaultValue : normalizedValue, forKey: key)
}

extension Notification.Name {
    static let checkOpenAIStatus = Notification.Name("checkOpenAIStatus")
    static let checkGeminiStatus = Notification.Name("checkGeminiStatus")
}

// Extension to load images from bundle
extension Bundle {
    // Helper method to decode images from the bundle with proper error handling
    func decodedImage(named name: String) -> Image? {
        if let path = Bundle.main.path(forResource: name, ofType: "png"),
           let nsImage = NSImage(contentsOfFile: path) {
            return Image(nsImage: nsImage)
        }
        return nil
    }
}

final class ScreenSelectionWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

final class ScreenSelectionOverlayView: NSView {
    var onSelectionFinished: ((CGRect) -> Void)?
    var onSelectionCancelled: (() -> Void)?

    private var startPoint: NSPoint?
    private var currentPoint: NSPoint?

    override var acceptsFirstResponder: Bool { true }

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
              selectionRect.height > 4 else {
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

    func resetSelection() {
        startPoint = nil
        currentPoint = nil
        needsDisplay = true
    }
}

@main
struct StewardApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
    @State private var openAIModelID: String = preferenceValue(forKey: "openAIModelID", defaultValue: OpenAIClient.defaultModelID)
    @State private var geminiAPIKey: String = UserDefaults.standard.string(forKey: "geminiAPIKey") ?? ""
    @State private var geminiModelID: String = preferenceValue(forKey: "geminiModelID", defaultValue: GeminiClient.defaultModelID)
    @State private var customRules: String = UserDefaults.standard.string(forKey: "customGrammarRules") ?? ""
    
    var body: some View {
        TabView {
            // General tab
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("OpenAI API Key")
                        .font(.headline)

                    HStack(alignment: .top, spacing: 12) {
                        SecureField("Enter your OpenAI API Key", text: $apiKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                            .onChange(of: apiKey) { newValue in
                                // Save immediately per macOS HIG
                                UserDefaults.standard.set(newValue, forKey: "openAIApiKey")
                                // Trigger API status check
                                NotificationCenter.default.post(name: .checkOpenAIStatus, object: nil)
                            }

                        TextField(OpenAIClient.defaultModelID, text: $openAIModelID)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onChange(of: openAIModelID) { newValue in
                                savePreferenceValue(newValue, forKey: "openAIModelID", defaultValue: OpenAIClient.defaultModelID)
                                NotificationCenter.default.post(name: .checkOpenAIStatus, object: nil)
                            }
                    }
                    
                    Text("Your API key is needed to use the grammar check feature.\nModel ID defaults to \(OpenAIClient.defaultModelID) when left empty.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Gemini API Key")
                        .font(.headline)

                    HStack(alignment: .top, spacing: 12) {
                        SecureField("Enter your Gemini API Key", text: $geminiAPIKey)
                            .textFieldStyle(.roundedBorder)
                            .frame(maxWidth: .infinity)
                            .onChange(of: geminiAPIKey) { newValue in
                                UserDefaults.standard.set(newValue, forKey: "geminiAPIKey")
                                NotificationCenter.default.post(name: .checkGeminiStatus, object: nil)
                            }

                        TextField(GeminiClient.defaultModelID, text: $geminiModelID)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: geminiModelID) { newValue in
                                savePreferenceValue(newValue, forKey: "geminiModelID", defaultValue: GeminiClient.defaultModelID)
                                NotificationCenter.default.post(name: .checkGeminiStatus, object: nil)
                            }
                    }
                    
                    Text("Your Gemini API key is used for screen text extraction.\nModel ID defaults to \(GeminiClient.defaultModelID) when left empty.")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
            }
            .padding(20)
            .tabItem {
                Label("General", systemImage: "gear")
            }
            
                        // Custom Rules tab
            VStack(alignment: .leading, spacing: 20) {
                Text("Custom Grammar Rules")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Define additional rules for grammar correction:")
                        .font(.subheadline)
                        .foregroundColor(.primary)
                    
                    TextEditor(text: $customRules)
                        .font(.system(.body, design: .monospaced))
                        .padding(8)
                        .background(Color(NSColor.textBackgroundColor))
                        .cornerRadius(6)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color(NSColor.separatorColor), lineWidth: 1)
                        )
                        .frame(height: 80)
                        .onChange(of: customRules) { newValue in
                            // Save immediately per macOS HIG
                            UserDefaults.standard.set(newValue, forKey: "customGrammarRules")
                        }
                    
                    Text("Examples:\n• Use Oxford comma in lists\n• Prefer active voice over passive voice\n• Use \"they\" as singular pronoun\n• Capitalize job titles when preceding names")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.top, 4)
                }
                
                Spacer()
            }
            .padding(20)
            .tabItem {
                Label("Custom Rules", systemImage: "list.bullet.rectangle")
            }
            
            // About tab
            VStack(alignment: .center, spacing: 12) {
                // Try multiple methods to load the app icon
                if let appIcon = NSImage(named: "AppIcon") {
                    // App icon registered with the system
                    Image(nsImage: appIcon)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } else if let iconImage = Bundle.main.decodedImage(named: "icon") {
                    // Load from our bundle extension
                    iconImage
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } else if let appIconPath = Bundle.main.path(forResource: "AppIcon", ofType: "icns"),
                          let nsImage = NSImage(contentsOfFile: appIconPath) {
                    // Try to load ICNS file directly
                    Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 80, height: 80)
                } else {
                    // Fallback to a symbol if no icon found
                    Image(systemName: "pencil.and.outline")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 60, height: 60)
                        .foregroundColor(.accentColor)
                }
                
                Text("Steward")
                    .font(.largeTitle)
                    .bold()
                
                Text("Version 1.0")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                Text("A simple writing and OCR tool for your Mac.\nPress ⌘⇧F to check grammar or ⌘⇧R to extract text from a screen selection.")
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .padding(.top, 2)
                
                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .tabItem {
                Label("About", systemImage: "info.circle")
            }
        }
        .frame(width: 560, height: 360)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    private enum MenuItemTag {
        static let activityStatus = 1
        static let openAIStatus = 2
        static let geminiStatus = 3
    }
    
    private var statusItem: NSStatusItem!
    private let openAIClient = OpenAIClient()
    private let geminiClient = GeminiClient()
    private var grammarHotKey: HotKey?
    private var screenOCRHotKey: HotKey?
    private var selectionWindows: [NSWindow] = []
    private var isScreenSelectionActive = false
    private var lastOperationFailed = false
    @Published var isProcessing = false
    @Published var apiStatus: APIStatus = .ok
    @Published var openAIStatus: APIStatus = .ok
    @Published var geminiStatus: APIStatus = .ok
    
    private var openAIApiKey: String {
        return UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
    }

    private var openAIModelID: String {
        return preferenceValue(forKey: "openAIModelID", defaultValue: OpenAIClient.defaultModelID)
    }

    private var geminiAPIKey: String {
        return UserDefaults.standard.string(forKey: "geminiAPIKey") ?? ""
    }

    private var geminiModelID: String {
        return preferenceValue(forKey: "geminiModelID", defaultValue: GeminiClient.defaultModelID)
    }
    
    // Status enum with associated icon images for menu bar states
    enum APIStatus {
        case ok
        case error
        case processing
        
        var statusImage: NSImage? {
            switch self {
            case .ok:
                return NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: "Steward")
            case .error:
                return NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: "API Error")
            case .processing:
                return NSImage(systemSymbolName: "ellipsis.circle", accessibilityDescription: "Processing Request")
            }
        }
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Tell the app it's a menu bar app without a main window
        NSApp.setActivationPolicy(.accessory)
        
        // Create the status bar item
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        updateStatusItemIcon()
        
        setupMenu()
        setupHotKeys()
        
        // Register for notifications to check service status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkOpenAIStatus),
            name: .checkOpenAIStatus,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkGeminiStatus),
            name: .checkGeminiStatus,
            object: nil
        )
        
        // Check service status on launch with a small delay to ensure UI is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkOpenAIStatus()
            self?.checkGeminiStatus()
        }
    }
    
    private func updateStatusItemIcon() {
        if let button = statusItem.button {
            button.image = apiStatus.statusImage
        }
    }

    private func refreshOverallStatus() {
        if isProcessing {
            apiStatus = .processing
        } else if lastOperationFailed || openAIStatus == .error || geminiStatus == .error {
            apiStatus = .error
        } else if openAIStatus == .processing || geminiStatus == .processing {
            apiStatus = .processing
        } else {
            apiStatus = .ok
        }
    }

    private func refreshStatusUI() {
        refreshOverallStatus()
        updateStatusItemIcon()
        updateAPIStatusMenuItem()
    }
    
    private func setupMenu() {
        let menu = NSMenu()
        
        menu.addItem(NSMenuItem(title: "Grammar Check (⌘⇧F)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Screen Text Capture (⌘⇧R)", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        
        let activityStatusItem = NSMenuItem(title: "Status: Ready", action: nil, keyEquivalent: "")
        activityStatusItem.tag = MenuItemTag.activityStatus
        menu.addItem(activityStatusItem)

        let openAIStatusItem = NSMenuItem(title: "OpenAI: Checking...", action: #selector(checkOpenAIStatus), keyEquivalent: "")
        openAIStatusItem.target = self
        openAIStatusItem.tag = MenuItemTag.openAIStatus
        menu.addItem(openAIStatusItem)

        let geminiStatusItem = NSMenuItem(title: "Gemini: Checking...", action: #selector(checkGeminiStatus), keyEquivalent: "")
        geminiStatusItem.target = self
        geminiStatusItem.tag = MenuItemTag.geminiStatus
        menu.addItem(geminiStatusItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
        refreshStatusUI()
        updateOpenAIStatusMenuItem()
        updateGeminiStatusMenuItem()
    }
    
    @objc private func checkOpenAIStatus() {
        // If no API key is set, show error state and return
        guard !openAIApiKey.isEmpty else {
            openAIStatus = .error
            refreshStatusUI()
            updateOpenAIStatusMenuItem()
            return
        }

        openAIStatus = .processing
        refreshStatusUI()
        updateOpenAIStatusMenuItem()

        openAIClient.checkAccess(apiKey: openAIApiKey, modelID: openAIModelID) { [weak self] hasAccess in
            guard let self else { return }

            self.openAIStatus = hasAccess ? .ok : .error
            self.refreshStatusUI()
            self.updateOpenAIStatusMenuItem()
        }
    }

    @objc private func checkGeminiStatus() {
        guard !geminiAPIKey.isEmpty else {
            geminiStatus = .error
            refreshStatusUI()
            updateGeminiStatusMenuItem()
            return
        }

        geminiStatus = .processing
        refreshStatusUI()
        updateGeminiStatusMenuItem()

        geminiClient.checkAccess(apiKey: geminiAPIKey, modelID: geminiModelID) { [weak self] hasAccess in
            guard let self else { return }
            self.geminiStatus = hasAccess ? .ok : .error
            self.refreshStatusUI()
            self.updateGeminiStatusMenuItem()
        }
    }
    
    private func updateAPIStatusMenuItem() {
        guard let menu = statusItem.menu else { return }
        
        if let apiStatusItem = menu.items.first(where: { $0.tag == MenuItemTag.activityStatus }) {
            switch apiStatus {
            case .ok:
                apiStatusItem.title = "Status: Ready"
            case .error:
                if lastOperationFailed {
                    apiStatusItem.title = "Status: Last operation failed"
                } else if openAIStatus == .error && openAIApiKey.isEmpty {
                    apiStatusItem.title = "Status: OpenAI API Key Missing"
                } else if geminiStatus == .error && geminiAPIKey.isEmpty {
                    apiStatusItem.title = "Status: Gemini API Key Missing"
                } else if openAIStatus == .error && geminiStatus != .error {
                    apiStatusItem.title = "Status: OpenAI Error"
                } else if geminiStatus == .error && openAIStatus != .error {
                    apiStatusItem.title = "Status: Gemini Error"
                } else {
                    apiStatusItem.title = "Status: Error"
                }
            case .processing:
                if isScreenSelectionActive {
                    apiStatusItem.title = "Status: Select an area..."
                } else if isProcessing {
                    apiStatusItem.title = "Status: Processing..."
                } else {
                    apiStatusItem.title = "Status: Checking services..."
                }
            }
        }
    }

    private func updateOpenAIStatusMenuItem() {
        guard let menu = statusItem.menu,
              let openAIStatusItem = menu.items.first(where: { $0.tag == MenuItemTag.openAIStatus }) else {
            return
        }

        switch openAIStatus {
        case .ok:
            openAIStatusItem.title = "OpenAI: OK"
        case .error:
            openAIStatusItem.title = openAIApiKey.isEmpty ? "OpenAI: API Key Missing" : "OpenAI: Error - Click to retry"
        case .processing:
            openAIStatusItem.title = "OpenAI: Checking..."
        }
    }

    private func updateGeminiStatusMenuItem() {
        guard let menu = statusItem.menu,
              let geminiStatusItem = menu.items.first(where: { $0.tag == MenuItemTag.geminiStatus }) else {
            return
        }

        switch geminiStatus {
        case .ok:
            geminiStatusItem.title = "Gemini: OK"
        case .error:
            geminiStatusItem.title = geminiAPIKey.isEmpty ? "Gemini: API Key Missing" : "Gemini: Error - Click to retry"
        case .processing:
            geminiStatusItem.title = "Gemini: Checking..."
        }
    }
    
    private func setupHotKeys() {
        // Set up system-wide keyboard shortcuts.
        grammarHotKey = HotKey(key: .f, modifiers: [.command, .shift])
        grammarHotKey?.keyDownHandler = { [weak self] in
            self?.handleGrammarHotKeyPress()
        }

        screenOCRHotKey = HotKey(key: .r, modifiers: [.command, .shift])
        screenOCRHotKey?.keyDownHandler = { [weak self] in
            self?.handleScreenOCRHotKeyPress()
        }
    }
    
    private func handleGrammarHotKeyPress() {
        guard !isProcessing else { return }
        lastOperationFailed = false
        isProcessing = true
        
        // Update UI to show processing state
        refreshStatusUI()
        
        // Get selected text
        if let selectedText = getSelectedText() {
            fixGrammar(text: selectedText) { [weak self] correctedText in
                guard let self = self else { return }
                
                if let correctedText = correctedText {
                    // Replace selected text with corrected text
                    self.replaceSelectedText(with: correctedText)
                    
                    // Update UI to show success state
                    self.lastOperationFailed = false
                    self.openAIStatus = .ok
                }
                // Note: If correctedText is nil, fixGrammar already set apiStatus to .error
                
                self.isProcessing = false
                self.refreshStatusUI()
                self.updateOpenAIStatusMenuItem()
            }
        } else {
            isProcessing = false
            refreshStatusUI()
        }
    }

    private func handleScreenOCRHotKeyPress() {
        guard !isProcessing else { return }

        guard !geminiAPIKey.isEmpty else {
            geminiStatus = .error
            refreshStatusUI()
            updateGeminiStatusMenuItem()
            openPreferences()
            return
        }

        guard ensureScreenCaptureAccess() else {
            lastOperationFailed = true
            refreshStatusUI()
            return
        }

        lastOperationFailed = false
        isProcessing = true
        isScreenSelectionActive = true
        refreshStatusUI()
        beginScreenSelection()
    }

    private func beginScreenSelection() {
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
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
            window.contentView = ScreenSelectionOverlayView(frame: .zero)
            selectionWindows.append(window)
        }

        for (index, screen) in screens.enumerated() {
            let window = selectionWindows[index]
            let overlayView = window.contentView as? ScreenSelectionOverlayView ?? ScreenSelectionOverlayView(frame: .zero)

            overlayView.frame = CGRect(origin: .zero, size: screen.frame.size)
            overlayView.resetSelection()
            overlayView.onSelectionFinished = { [weak self] localRect in
                let screenRect = localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self?.finishScreenSelection(on: screen, selectionRect: screenRect)
            }
            overlayView.onSelectionCancelled = { [weak self] in
                self?.cancelScreenSelection()
            }

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

    private func finishScreenSelection(on screen: NSScreen, selectionRect: CGRect) {
        guard isScreenSelectionActive else { return }
        endScreenSelectionUI()

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.extractTextFromSelectedScreenArea(on: screen, selectionRect: selectionRect)
        }
    }

    private func cancelScreenSelection() {
        guard isScreenSelectionActive else { return }
        endScreenSelectionUI()
        lastOperationFailed = false
        isProcessing = false
        refreshStatusUI()
    }

    private func endScreenSelectionUI() {
        isScreenSelectionActive = false

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
    }

    private func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    private func extractTextFromSelectedScreenArea(on screen: NSScreen, selectionRect: CGRect) {
        guard let imageData = captureSelectionImageData(on: screen, selectionRect: selectionRect) else {
            lastOperationFailed = true
            isProcessing = false
            refreshStatusUI()
            return
        }

        geminiStatus = .processing
        refreshStatusUI()
        updateGeminiStatusMenuItem()

        geminiClient.extractMarkdownText(
            apiKey: geminiAPIKey,
            modelID: geminiModelID,
            imageData: imageData,
            mimeType: "image/png"
        ) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let extractedText):
                self.copyTextToClipboard(extractedText)
                self.lastOperationFailed = false
                self.geminiStatus = .ok
            case .failure(let error):
                print("Gemini API Error: \(error.localizedDescription)")
                self.lastOperationFailed = true
                self.geminiStatus = .error
            }

            self.isProcessing = false
            self.refreshStatusUI()
            self.updateGeminiStatusMenuItem()
        }
    }

    private func captureSelectionImageData(on screen: NSScreen, selectionRect: CGRect) -> Data? {
        guard let displayID = displayID(for: screen),
              let displayImage = CGDisplayCreateImage(displayID) else {
            return nil
        }

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
              let croppedImage = displayImage.cropping(to: clippedCropRect) else {
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
    
    private func getSelectedText() -> String? {
        // This method uses pasteboard and keyboard shortcuts to get selected text from any app
        // We need to save the current pasteboard content to restore it later
        let oldPasteboardContent = NSPasteboard.general.string(forType: .string)
        
        // Simulate Command+C to copy selected text using CGEvent (Core Graphics)
        // Virtual key 0x08 corresponds to 'c' on the keyboard
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x08, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        // Post these events to the system to simulate keyboard press
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        // Small delay to ensure copy completes
        Thread.sleep(forTimeInterval: 0.2)
        
        // Get the selected text from pasteboard
        let selectedText = NSPasteboard.general.string(forType: .string)
        
        // If there was content in the pasteboard before, restore it
        if let oldContent = oldPasteboardContent {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(oldContent, forType: .string)
        }
        
        return selectedText
    }
    
    private func replaceSelectedText(with newText: String) {
        // Save current pasteboard content to restore it after operation
        let oldPasteboardContent = NSPasteboard.general.string(forType: .string)
        
        // Set the corrected text to pasteboard
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(newText, forType: .string)
        
        // Simulate Command+V to paste corrected text
        // Virtual key 0x09 corresponds to 'v' on the keyboard
        let source = CGEventSource(stateID: .hidSystemState)
        
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 0x09, keyDown: false)
        
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        
        // Restore original pasteboard content after a delay
        // Delay ensures paste operation completes before restoring clipboard
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            if let oldContent = oldPasteboardContent {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(oldContent, forType: .string)
            }
        }
    }

    private func copyTextToClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    
    private func fixGrammar(text: String, completion: @escaping (String?) -> Void) {
        guard !text.isEmpty else {
            completion(nil)
            return
        }
        
        // Check if API key is set
        guard !openAIApiKey.isEmpty else {
            openAIStatus = .error
            lastOperationFailed = true
            refreshStatusUI()
            updateOpenAIStatusMenuItem()
            // Open preferences window to prompt user to enter API key
            openPreferences()
            completion(nil)
            return
        }
        
        // Already set to processing in handleGrammarHotKeyPress, but ensure consistency
        refreshStatusUI()
        
        // Get custom rules from UserDefaults
        let customRules = UserDefaults.standard.string(forKey: "customGrammarRules") ?? ""

        openAIClient.correctGrammar(
            apiKey: openAIApiKey,
            modelID: openAIModelID,
            customRules: customRules,
            text: text
        ) { [weak self] result in
            guard let self else { return }

            switch result {
            case .success(let correctedText):
                completion(correctedText)
            case .failure(let error):
                print("OpenAI API Error: \(error.localizedDescription)")
                self.lastOperationFailed = true
                self.openAIStatus = .error
                self.refreshStatusUI()
                self.updateOpenAIStatusMenuItem()
                completion(nil)
            }
        }
    }
    
    // Store a reference to our settings window to prevent it from being deallocated
    private var preferencesWindow: NSWindow?
    
    @objc private func openPreferences() {
        // If we already have a window, just bring it to front
        if let existingWindow = self.preferencesWindow {
            if existingWindow.isVisible {
                existingWindow.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                return
            }
        }
        
        // Create a window for the settings view
        let settingsWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 450, height: 300),
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        // These window properties are crucial for proper behavior as a preference window
        // isReleasedWhenClosed = false prevents the window from being deallocated when closed
        settingsWindow.isReleasedWhenClosed = false
        // Set the window to be non-main to prevent it from becoming the main window
        // which would cause app termination when closed
        settingsWindow.hidesOnDeactivate = false
        // Tell the app not to terminate when this window is closed
        settingsWindow.canHide = true
        settingsWindow.title = "Preferences"
        settingsWindow.center()
        
        // Create a hosting controller for our SwiftUI view
        let settingsView = NSHostingController(rootView: SettingsView())
        settingsWindow.contentView = settingsView.view
        
        // Set window delegate and clear reference when window closes
        settingsWindow.delegate = self
        
        // Store a reference to prevent deallocation
        self.preferencesWindow = settingsWindow
        
        // Make the window key and visible
        settingsWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
    
    // MARK: - NSWindowDelegate methods
    
    func windowWillClose(_ notification: Notification) {
        if let closingWindow = notification.object as? NSWindow, 
           closingWindow === preferencesWindow {
            // Release the window reference when it's closed
            preferencesWindow = nil
        }
    }
}
