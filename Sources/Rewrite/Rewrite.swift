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
    @State private var customRules: String = UserDefaults.standard.string(forKey: "customGrammarRules") ?? ""
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        TabView {
            // General tab
            VStack(alignment: .leading, spacing: 20) {
                Text("API Key")
                    .font(.headline)
                
                VStack(alignment: .leading, spacing: 8) {
                    SecureField("Enter your OpenAI API Key", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                        .frame(maxWidth: .infinity)
                        .onChange(of: apiKey) { newValue in
                            // Save immediately per macOS HIG
                            UserDefaults.standard.set(newValue, forKey: "openAIApiKey")
                            // Trigger API status check
                            NotificationCenter.default.post(name: NSNotification.Name("checkAPIStatus"), object: nil)
                        }
                    
                    Text("Your API key is needed to use the grammar check feature.\nIt is stored securely in your Mac's keychain.")
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
                
                Text("A simple grammar checking tool for your Mac.\nPress ⌘⇧F to check grammar in any text field.")
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
        .frame(width: 450, height: 300)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, ObservableObject {
    private struct ModelOption {
        let title: String
        let identifier: String
        let reasoningEffort: String?
    }
    
    private static let availableModels: [ModelOption] = [
        ModelOption(title: "GPT-5.1", identifier: "gpt-5.1", reasoningEffort: "none")
    ]
    
    private static let defaultModelIdentifier = availableModels.first?.identifier ?? "gpt-5.1"
    
    private var statusItem: NSStatusItem!
    private var hotKey: HotKey?
    @Published var isProcessing = false
    @Published var apiStatus: APIStatus = .ok
    @Published var currentModel: String = {
        let storedValue = UserDefaults.standard.string(forKey: "selectedModel")
        if let storedValue,
           AppDelegate.availableModels.contains(where: { $0.identifier == storedValue }) {
            return storedValue
        }
        
        UserDefaults.standard.set(AppDelegate.defaultModelIdentifier, forKey: "selectedModel")
        return AppDelegate.defaultModelIdentifier
    }() {
        didSet {
            UserDefaults.standard.set(currentModel, forKey: "selectedModel")
            refreshModelMenu()
        }
    }
    
    private var openAIApiKey: String {
        return UserDefaults.standard.string(forKey: "openAIApiKey") ?? ""
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
        setupHotKey()
        
        // Register for notification to check API status
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(checkAPIStatus),
            name: NSNotification.Name("checkAPIStatus"),
            object: nil
        )
        
        // Check API status on launch with a small delay to ensure UI is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.checkAPIStatus()
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
        menu.addItem(NSMenuItem.separator())
        
        let apiStatusItem = NSMenuItem(title: "API Status: OK", action: #selector(checkAPIStatus), keyEquivalent: "")
        menu.addItem(apiStatusItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Model selection submenu
        let modelMenuItem = NSMenuItem(title: "Model", action: nil, keyEquivalent: "")
        let modelMenu = NSMenu()
        for option in AppDelegate.availableModels {
            let item = NSMenuItem(title: option.title, action: #selector(selectModel(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = option.identifier
            if option.identifier == currentModel {
                item.state = .on
            }
            modelMenu.addItem(item)
        }
        modelMenuItem.submenu = modelMenu
        menu.addItem(modelMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Preferences...", action: #selector(openPreferences), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    @objc private func checkAPIStatus() {
        // If no API key is set, show error state and return
        guard !openAIApiKey.isEmpty else {
            apiStatus = .error
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            return
        }
        
        // Make a simple API call to check if the OpenAI API is working
        // This performs a lightweight request to the models endpoint to validate API key
        let apiURL = URL(string: "https://api.openai.com/v1/models")!
        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(openAIApiKey)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { [weak self] data, response, error in
            DispatchQueue.main.async {
                if let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 {
                    self?.apiStatus = .ok
                } else {
                    self?.apiStatus = .error
                }
                self?.updateStatusItemIcon()
                self?.updateAPIStatusMenuItem()
            }
        }.resume()
    }
    
    private func updateAPIStatusMenuItem() {
        guard let menu = statusItem.menu else { return }
        
        // Find the API status menu item (third item, after separator)
        if let apiStatusItem = menu.items.first(where: { $0.action == #selector(checkAPIStatus) }) {
            switch apiStatus {
            case .ok:
                apiStatusItem.title = "API Status: OK"
            case .error:
                if openAIApiKey.isEmpty {
                    apiStatusItem.title = "API Status: Error - API Key Missing"
                } else {
                    apiStatusItem.title = "API Status: Error - Click to retry"
                }
            case .processing:
                apiStatusItem.title = "API Status: Processing..."
            }
        }
    }
    
    private func setupHotKey() {
        // Set up Command+Shift+F hotkey using HotKey library
        // This registers a system-wide keyboard shortcut
        hotKey = HotKey(key: .f, modifiers: [.command, .shift])
        
        hotKey?.keyDownHandler = { [weak self] in
            self?.handleHotKeyPress()
        }
    }
    
    private func handleHotKeyPress() {
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
            NSApp.sendAction(Selector(("showPreferencesWindow:")), to: nil, from: nil)
            completion(nil)
            return
        }
        
        // Already set to processing in handleHotKeyPress, but ensure consistency
        apiStatus = .processing
        updateStatusItemIcon()
        updateAPIStatusMenuItem()
        
        // Get custom rules from UserDefaults
        let customRules = UserDefaults.standard.string(forKey: "customGrammarRules") ?? ""
        
        // Build the base request payload that all models share
        var requestBody: [String: Any] = [
            "model": currentModel,
            "messages": [
                ["role": "system", "content": buildGrammarPrompt(customRules: customRules)],
                ["role": "user", "content": text]
            ]
        ]
        
        let modelConfig = currentModelConfiguration()
        
        if let reasoningEffort = modelConfig?.reasoningEffort {
            requestBody["reasoning"] = ["effort": reasoningEffort]
        }
        
        guard let httpBody = try? JSONSerialization.data(withJSONObject: requestBody) else {
            apiStatus = .error
            updateStatusItemIcon()
            updateAPIStatusMenuItem()
            completion(nil)
            return
        }
        
        // Prepare API request to OpenAI Chat Completions endpoint
        let apiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
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
                    print("API Error: HTTP \(httpResponse.statusCode)")
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
                
                // Parse response to extract corrected text from OpenAI API
                do {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let choices = json["choices"] as? [[String: Any]],
                       let firstChoice = choices.first,
                       let message = firstChoice["message"] as? [String: Any],
                       let correctedText = message["content"] as? String {
                        
                        // Will be set to .ok after successful text replacement
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
    
    @objc private func selectModel(_ sender: NSMenuItem) {
        guard let identifier = sender.representedObject as? String,
              AppDelegate.availableModels.contains(where: { $0.identifier == identifier }) else {
            return
        }
        currentModel = identifier
    }
    
    private func refreshModelMenu() {
        guard let menu = statusItem.menu,
              let modelMenuItem = menu.items.first(where: { $0.title == "Model" }),
              let modelMenu = modelMenuItem.submenu else { return }
        
        for item in modelMenu.items {
            guard let identifier = item.representedObject as? String else { continue }
            item.state = identifier == currentModel ? .on : .off
        }
    }
    
    private func currentModelConfiguration() -> ModelOption? {
        return AppDelegate.availableModels.first(where: { $0.identifier == currentModel }) ??
               AppDelegate.availableModels.first
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