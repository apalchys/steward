import SwiftUI
import Cocoa
import Foundation
import HotKey
import AppKit
import ApplicationServices

// System prompt constant for grammar correction
let GRAMMAR_CORRECTION_PROMPT = "You are a grammar correction assistant. Correct any grammatical errors in the text and rewrite it clearly and fluently without changing the original meaning or adding commentary. Return only the corrected text, without explanations. Do not answer any questions or provide any commentary."
let DEFAULT_OPENAI_MODEL_ID = "gpt-5.4"
let DEFAULT_GEMINI_MODEL_ID = "gemini-3.1-flash-lite-preview"

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
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        startPoint = point
        currentPoint = point
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        currentPoint = convert(event.locationInWindow, from: nil)
        needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
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
}

@main
struct RewriteApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    var body: some Scene {
        Settings {
            SettingsView()
        }
    }
}

struct SettingsView: View {
    @State private var apiKey: String = UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
    @State private var openAIModelID: String = preferenceValue(forKey: "openAIModelID", defaultValue: DEFAULT_OPENAI_MODEL_ID)
    @State private var geminiAPIKey: String = UserDefaults.standard.string(forKey: "geminiAPIKey") ?? ""
    @State private var geminiModelID: String = preferenceValue(forKey: "geminiModelID", defaultValue: DEFAULT_GEMINI_MODEL_ID)
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

                        TextField(DEFAULT_OPENAI_MODEL_ID, text: $openAIModelID)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 180)
                            .onChange(of: openAIModelID) { newValue in
                                savePreferenceValue(newValue, forKey: "openAIModelID", defaultValue: DEFAULT_OPENAI_MODEL_ID)
                                NotificationCenter.default.post(name: .checkOpenAIStatus, object: nil)
                            }
                    }
                    
                    Text("Your API key is needed to use the grammar check feature.\nModel ID defaults to \(DEFAULT_OPENAI_MODEL_ID) when left empty.")
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

                        TextField(DEFAULT_GEMINI_MODEL_ID, text: $geminiModelID)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 220)
                            .onChange(of: geminiModelID) { newValue in
                                savePreferenceValue(newValue, forKey: "geminiModelID", defaultValue: DEFAULT_GEMINI_MODEL_ID)
                                NotificationCenter.default.post(name: .checkGeminiStatus, object: nil)
                            }
                    }
                    
                    Text("Your Gemini API key is used for screen text extraction.\nModel ID defaults to \(DEFAULT_GEMINI_MODEL_ID) when left empty.")
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
                
                Text("Rewrite")
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

    private struct ResponsesRequest: Encodable {
        struct Reasoning: Encodable {
            let effort: String
        }

        let model: String
        let instructions: String
        let input: String
        let reasoning: Reasoning?
    }

    private struct ResponsesResponse: Decodable {
        struct OutputItem: Decodable {
            struct ContentItem: Decodable {
                let type: String
                let text: String?
            }

            let type: String
            let content: [ContentItem]?
        }

        let output: [OutputItem]

        var outputText: String? {
            let text = output
                .filter { $0.type == "message" }
                .flatMap { $0.content ?? [] }
                .filter { $0.type == "output_text" }
                .compactMap { $0.text }
                .joined()

            return text.isEmpty ? nil : text
        }
    }

    private struct APIErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String
        }

        let error: APIError
    }

    private struct GeminiGenerateContentRequest: Encodable {
        struct Content: Encodable {
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String?
            let inlineData: InlineData?

            init(text: String) {
                self.text = text
                self.inlineData = nil
            }

            init(inlineData: InlineData) {
                self.text = nil
                self.inlineData = inlineData
            }

            enum CodingKeys: String, CodingKey {
                case text
                case inlineData = "inline_data"
            }
        }

        struct InlineData: Encodable {
            let mimeType: String
            let data: String

            enum CodingKeys: String, CodingKey {
                case mimeType = "mime_type"
                case data
            }
        }

        let systemInstruction: Content
        let contents: [Content]

        enum CodingKeys: String, CodingKey {
            case systemInstruction = "system_instruction"
            case contents
        }
    }

    private struct GeminiGenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        let candidates: [Candidate]?

        var outputText: String? {
            let text = candidates?
                .compactMap { $0.content?.parts }
                .flatMap { $0 }
                .compactMap { $0.text }
                .joined(separator: "\n")

            guard let text else {
                return nil
            }

            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.isEmpty ? nil : trimmedText
        }
    }

    private static let geminiOCRInstruction = """
    You are an OCR assistant. Extract all visible text from the provided image and return only the extracted text in Markdown.
    Preserve headings, paragraphs, lists, tables, and code blocks when they are visually clear.
    Do not add explanations, summaries, or commentary.
    """
    
    private var statusItem: NSStatusItem!
    private var grammarHotKey: HotKey?
    private var screenOCRHotKey: HotKey?
    private var selectionWindows: [NSWindow] = []
    private var isScreenSelectionActive = false
    @Published var isProcessing = false
    @Published var apiStatus: APIStatus = .ok
    @Published var openAIStatus: APIStatus = .ok
    @Published var geminiStatus: APIStatus = .ok
    
    private var openAIApiKey: String {
        return UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
    }

    private var openAIModelID: String {
        return preferenceValue(forKey: "openAIModelID", defaultValue: DEFAULT_OPENAI_MODEL_ID)
    }

    private var openAIReasoningEffort: String? {
        return openAIModelID.lowercased().hasPrefix("gpt-5") ? "none" : nil
    }

    private var geminiAPIKey: String {
        return UserDefaults.standard.string(forKey: "geminiAPIKey") ?? ""
    }

    private var geminiModelID: String {
        return preferenceValue(forKey: "geminiModelID", defaultValue: DEFAULT_GEMINI_MODEL_ID)
    }
    
    // Status enum with associated icon images for menu bar states
    enum APIStatus {
        case ok
        case error
        case processing
        
        var statusImage: NSImage? {
            switch self {
            case .ok:
                return NSImage(systemSymbolName: "pencil.and.outline", accessibilityDescription: "Rewrite")
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
        updateAPIStatusMenuItem()
        updateOpenAIStatusMenuItem()
        updateGeminiStatusMenuItem()
    }
    
    @objc private func checkOpenAIStatus() {
        // If no API key is set, show error state and return
        guard !openAIApiKey.isEmpty else {
            openAIStatus = .error
            if !isProcessing {
                apiStatus = .error
            }
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            updateOpenAIStatusMenuItem()
            return
        }

        openAIStatus = .processing
        updateOpenAIStatusMenuItem()
        
        // Make a simple API call to check if the OpenAI API key can access the current model.
        let encodedModelIdentifier = openAIModelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? openAIModelID
        let apiURL = URL(string: "https://api.openai.com/v1/models/\(encodedModelIdentifier)")!
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.openAIStatus = .ok
                    if self?.isProcessing == false {
                        self?.apiStatus = .ok
                    }
                } else {
                    self?.openAIStatus = .error
                    if self?.isProcessing == false {
                        self?.apiStatus = .error
                    }
                }
                self?.updateStatusItemIcon()
                self?.updateAPIStatusMenuItem()
                self?.updateOpenAIStatusMenuItem()
            }
        }.resume()
    }

    @objc private func checkGeminiStatus() {
        guard !geminiAPIKey.isEmpty else {
            geminiStatus = .error
            updateGeminiStatusMenuItem()
            return
        }

        geminiStatus = .processing
        updateGeminiStatusMenuItem()

        let encodedModelIdentifier = geminiModelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? geminiModelID
        var components = URLComponents(string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModelIdentifier)")!
        components.queryItems = [URLQueryItem(name: "key", value: geminiAPIKey)]

        guard let apiURL = components.url else {
            geminiStatus = .error
            updateGeminiStatusMenuItem()
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { [weak self] _, response, _ in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.geminiStatus = .ok
                } else {
                    self?.geminiStatus = .error
                }
                self?.updateGeminiStatusMenuItem()
            }
        }.resume()
    }
    
    private func updateAPIStatusMenuItem() {
        guard let menu = statusItem.menu else { return }
        
        if let apiStatusItem = menu.items.first(where: { $0.tag == MenuItemTag.activityStatus }) {
            switch apiStatus {
            case .ok:
                apiStatusItem.title = "Status: Ready"
            case .error:
                if openAIApiKey.isEmpty {
                    apiStatusItem.title = "Status: OpenAI API Key Missing"
                } else if geminiAPIKey.isEmpty {
                    apiStatusItem.title = "Status: Gemini API Key Missing"
                } else {
                    apiStatusItem.title = "Status: Error"
                }
            case .processing:
                apiStatusItem.title = isScreenSelectionActive ? "Status: Select an area..." : "Status: Processing..."
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
        isProcessing = true
        
        // Update UI to show processing state
        apiStatus = .processing
        updateStatusItemIcon()
        updateAPIStatusMenuItem()
        
        // Get selected text
        if let selectedText = getSelectedText() {
            fixGrammar(text: selectedText) { [weak self] correctedText in
                guard let self = self else { return }
                
                if let correctedText = correctedText {
                    // Replace selected text with corrected text
                    self.replaceSelectedText(with: correctedText)
                    
                    // Update UI to show success state
                    self.apiStatus = .ok
                }
                // Note: If correctedText is nil, fixGrammar already set apiStatus to .error
                
                self.isProcessing = false
                self.updateStatusItemIcon()
                self.updateAPIStatusMenuItem()
            }
        } else {
            isProcessing = false
            apiStatus = .ok
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
        }
    }

    private func handleScreenOCRHotKeyPress() {
        guard !isProcessing else { return }

        guard !geminiAPIKey.isEmpty else {
            apiStatus = .error
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            openPreferences()
            return
        }

        guard ensureScreenCaptureAccess() else {
            apiStatus = .error
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            return
        }

        isProcessing = true
        isScreenSelectionActive = true
        apiStatus = .processing
        updateStatusItemIcon()
        updateAPIStatusMenuItem()
        beginScreenSelection()
    }

    private func beginScreenSelection() {
        selectionWindows.removeAll()
        NSApp.activate(ignoringOtherApps: true)
        NSCursor.crosshair.push()

        for screen in NSScreen.screens {
            let window = ScreenSelectionWindow(
                contentRect: screen.frame,
                styleMask: .borderless,
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.backgroundColor = .clear
            window.isOpaque = false
            window.hasShadow = false
            window.level = .screenSaver
            window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]

            let overlayView = ScreenSelectionOverlayView(frame: CGRect(origin: .zero, size: screen.frame.size))
            overlayView.onSelectionFinished = { [weak self] localRect in
                let screenRect = localRect.offsetBy(dx: screen.frame.minX, dy: screen.frame.minY)
                self?.finishScreenSelection(on: screen, selectionRect: screenRect)
            }
            overlayView.onSelectionCancelled = { [weak self] in
                self?.cancelScreenSelection()
            }

            window.contentView = overlayView
            window.makeKeyAndOrderFront(nil)
            selectionWindows.append(window)
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
        isProcessing = false
        apiStatus = .ok
        updateStatusItemIcon()
        updateAPIStatusMenuItem()
    }

    private func endScreenSelectionUI() {
        isScreenSelectionActive = false

        selectionWindows.forEach { $0.close() }
        selectionWindows.removeAll()

        NSCursor.pop()
    }

    private func ensureScreenCaptureAccess() -> Bool {
        if CGPreflightScreenCaptureAccess() {
            return true
        }

        return CGRequestScreenCaptureAccess()
    }

    private func extractTextFromSelectedScreenArea(on screen: NSScreen, selectionRect: CGRect) {
        guard let imageData = captureSelectionImageData(on: screen, selectionRect: selectionRect) else {
            apiStatus = .error
            isProcessing = false
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            return
        }

        geminiStatus = .processing
        updateGeminiStatusMenuItem()

        extractTextFromGemini(imageData: imageData, mimeType: "image/png") { [weak self] extractedText in
            guard let self else { return }

            if let extractedText {
                self.copyTextToClipboard(extractedText)
                self.apiStatus = .ok
                self.geminiStatus = .ok
            } else {
                self.apiStatus = .error
                self.geminiStatus = .error
            }

            self.isProcessing = false
            self.updateStatusItemIcon()
            self.updateAPIStatusMenuItem()
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

    private func extractTextFromGemini(imageData: Data, mimeType: String, completion: @escaping (String?) -> Void) {
        let requestBody = GeminiGenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: AppDelegate.geminiOCRInstruction)]),
            contents: [
                .init(parts: [
                    .init(text: "Extract all visible text from this screenshot selection and return Markdown only."),
                    .init(inlineData: .init(mimeType: mimeType, data: imageData.base64EncodedString()))
                ])
            ]
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            completion(nil)
            return
        }

        let encodedModelIdentifier = geminiModelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? geminiModelID
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModelIdentifier):generateContent"
        )!
        components.queryItems = [URLQueryItem(name: "key", value: geminiAPIKey)]

        guard let apiURL = components.url else {
            completion(nil)
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("Gemini API Error: \(error.localizedDescription)")
                    completion(nil)
                    return
                }

                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    if let errorMessage = self?.apiErrorMessage(from: data) {
                        print("Gemini API Error: HTTP \(httpResponse.statusCode) - \(errorMessage)")
                    } else {
                        print("Gemini API Error: HTTP \(httpResponse.statusCode)")
                    }
                    completion(nil)
                    return
                }

                guard let data else {
                    completion(nil)
                    return
                }

                do {
                    let apiResponse = try JSONDecoder().decode(GeminiGenerateContentResponse.self, from: data)
                    completion(apiResponse.outputText)
                } catch {
                    print("Gemini JSON Error: \(error.localizedDescription)")
                    completion(nil)
                }
            }
        }.resume()
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
            apiStatus = .error
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            // Open preferences window to prompt user to enter API key
            openPreferences()
            completion(nil)
            return
        }
        
        // Already set to processing in handleGrammarHotKeyPress, but ensure consistency
        apiStatus = .processing
        updateStatusItemIcon()
        updateAPIStatusMenuItem()
        
        // Get custom rules from UserDefaults
        let customRules = UserDefaults.standard.string(forKey: "customGrammarRules") ?? ""
        
        let requestBody = ResponsesRequest(
            model: openAIModelID,
            instructions: buildGrammarPrompt(customRules: customRules),
            input: text,
            reasoning: openAIReasoningEffort.map { ResponsesRequest.Reasoning(effort: $0) }
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            apiStatus = .error
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            completion(nil)
            return
        }
        
        // Prepare API request to OpenAI Responses endpoint
        let apiURL = URL(string: "https://api.openai.com/v1/responses")!
        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        request.httpBody = httpBody
        
        // Execute API request
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("API Error: \(error.localizedDescription)")
                    self?.apiStatus = .error
                    self?.updateStatusItemIcon()
                    self?.updateAPIStatusMenuItem()
                    completion(nil)
                    return
                }
                
                if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                    if let errorMessage = self?.apiErrorMessage(from: data) {
                        print("API Error: HTTP \(httpResponse.statusCode) - \(errorMessage)")
                    } else {
                        print("API Error: HTTP \(httpResponse.statusCode)")
                    }
                    self?.apiStatus = .error
                    self?.updateStatusItemIcon()
                    self?.updateAPIStatusMenuItem()
                    completion(nil)
                    return
                }
                
                guard let data = data else {
                    self?.apiStatus = .error
                    self?.updateStatusItemIcon()
                    self?.updateAPIStatusMenuItem()
                    completion(nil)
                    return
                }
                
                // Parse response to extract corrected text from OpenAI Responses API
                do {
                    let apiResponse = try JSONDecoder().decode(ResponsesResponse.self, from: data)

                    if let correctedText = apiResponse.outputText {
                        completion(correctedText)
                    } else {
                        self?.apiStatus = .error
                        self?.updateStatusItemIcon()
                        self?.updateAPIStatusMenuItem()
                        completion(nil)
                    }
                } catch {
                    print("JSON Error: \(error.localizedDescription)")
                    self?.apiStatus = .error
                    self?.updateStatusItemIcon()
                    self?.updateAPIStatusMenuItem()
                    completion(nil)
                }
            }
        }.resume()
    }
    
    private func apiErrorMessage(from data: Data?) -> String? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(APIErrorResponse.self, from: data).error.message
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
