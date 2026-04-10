import AppKit
import Defaults
import Foundation
import HotKey
import OSLog
import StewardCore

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.steward", category: "settings")

struct LLMProviderProfile: Equatable {
    var apiKey: String
    var modelID: String

    static var empty: LLMProviderProfile {
        LLMProviderProfile(apiKey: "", modelID: "")
    }

    var configuration: LLMProviderConfiguration? {
        let configuration = LLMProviderConfiguration(
            apiKey: apiKey.trimmed,
            modelID: modelID.trimmed
        )

        return configuration.isConfigured ? configuration : nil
    }
}

struct VoiceSettings: Equatable {
    static let defaultGeminiModelID = "gemini-3.1-flash-lite-preview"
    static let defaultOpenAIModelID = "gpt-4o-mini-transcribe"
    static let `default` = VoiceSettings()

    var providerID: LLMProviderID
    var geminiModelID: String
    var openAIModelID: String
    var customInstructions: String
    var hotKey: AppHotKey

    init(
        providerID: LLMProviderID = .gemini,
        geminiModelID: String = VoiceSettings.defaultGeminiModelID,
        openAIModelID: String = VoiceSettings.defaultOpenAIModelID,
        customInstructions: String = "",
        hotKey: AppHotKey = .defaultVoiceDictation
    ) {
        self.providerID = providerID
        self.geminiModelID = geminiModelID
        self.openAIModelID = openAIModelID
        self.customInstructions = customInstructions
        self.hotKey = hotKey
    }

    func modelID(for providerID: LLMProviderID) -> String {
        switch providerID {
        case .gemini:
            let trimmedModelID = geminiModelID.trimmed
            return trimmedModelID.isEmpty ? Self.defaultGeminiModelID : trimmedModelID
        case .openAI:
            let trimmedModelID = openAIModelID.trimmed
            return trimmedModelID.isEmpty ? Self.defaultOpenAIModelID : trimmedModelID
        }
    }
}

struct AppHotKey: Equatable, Hashable {
    enum TriggerKind: String, Equatable, Hashable {
        case keyboard
        case mouseButton
    }

    static let grammarCheck = AppHotKey(
        carbonKeyCode: Key.f.carbonKeyCode,
        carbonModifiers: NSEvent.ModifierFlags([.command, .shift]).carbonFlags
    )
    static let screenTextCapture = AppHotKey(
        carbonKeyCode: Key.r.carbonKeyCode,
        carbonModifiers: NSEvent.ModifierFlags([.command, .shift]).carbonFlags
    )
    static let defaultVoiceDictation = AppHotKey(
        carbonKeyCode: Key.d.carbonKeyCode,
        carbonModifiers: NSEvent.ModifierFlags([.command, .shift]).carbonFlags
    )

    var triggerKind: TriggerKind
    var carbonKeyCode: UInt32
    var carbonModifiers: UInt32
    var mouseButtonNumber: Int

    init(carbonKeyCode: UInt32, carbonModifiers: UInt32) {
        self.triggerKind = .keyboard
        self.carbonKeyCode = carbonKeyCode
        self.carbonModifiers = carbonModifiers
        self.mouseButtonNumber = 0
    }

    init(mouseButtonNumber: Int, carbonModifiers: UInt32 = 0) {
        self.triggerKind = .mouseButton
        self.carbonKeyCode = 0
        self.carbonModifiers = carbonModifiers
        self.mouseButtonNumber = mouseButtonNumber
    }

    init(keyCombo: KeyCombo) {
        self.init(carbonKeyCode: keyCombo.carbonKeyCode, carbonModifiers: keyCombo.carbonModifiers)
    }

    var isKeyboard: Bool {
        triggerKind == .keyboard
    }

    var isMouseButton: Bool {
        triggerKind == .mouseButton
    }

    var keyCombo: KeyCombo? {
        guard isKeyboard else {
            return nil
        }

        return KeyCombo(carbonKeyCode: carbonKeyCode, carbonModifiers: carbonModifiers)
    }

    var key: Key? {
        keyCombo?.key
    }

    var modifiers: NSEvent.ModifierFlags {
        if let keyCombo {
            return keyCombo.modifiers
        }

        return NSEvent.ModifierFlags(carbonFlags: carbonModifiers)
    }

    var displayValue: String {
        if let keyCombo {
            return keyCombo.description
        }

        return readableDisplayValue
    }

    var readableDisplayValue: String {
        var components = modifierDisplayComponents(for: modifiers)

        if let key {
            components.append(key.readableDisplayName)
        } else if isMouseButton {
            components.append("Mouse Button \(mouseButtonNumber)")
        }

        return components.joined(separator: "-")
    }
}

private func modifierDisplayComponents(for modifiers: NSEvent.ModifierFlags) -> [String] {
    var components: [String] = []

    if modifiers.contains(.command) {
        components.append("Command")
    }
    if modifiers.contains(.shift) {
        components.append("Shift")
    }
    if modifiers.contains(.option) {
        components.append("Option")
    }
    if modifiers.contains(.control) {
        components.append("Control")
    }

    return components
}

private extension Key {
    var readableDisplayName: String {
        switch self {
        case .space:
            return "Space"
        case .tab:
            return "Tab"
        case .return:
            return "Return"
        default:
            return description
        }
    }
}

struct LLMSettings: Equatable {
    static let grammarProvider = LLMProviderID.openAI
    static let screenshotProvider = LLMProviderID.gemini

    var providerProfiles: [LLMProviderID: LLMProviderProfile]
    var grammarCustomInstructions: String
    var screenshotCustomInstructions: String
    var voice: VoiceSettings
    var clipboardHistory: ClipboardHistorySettings

    static func empty() -> LLMSettings {
        LLMSettings(
            providerProfiles: [:],
            grammarCustomInstructions: "",
            screenshotCustomInstructions: "",
            voice: .default,
            clipboardHistory: .default
        )
    }

    func profile(for providerID: LLMProviderID) -> LLMProviderProfile {
        providerProfiles[providerID] ?? .empty
    }

    func configuration(for providerID: LLMProviderID) -> LLMProviderConfiguration? {
        profile(for: providerID).configuration
    }
}

struct ClipboardHistorySettings: Equatable {
    static let defaultMaxStoredRecords = 1_000
    static let maxStoredRecordsLimit = 10_000
    static let maxStoredRecordsStep = 500
    static let `default` = ClipboardHistorySettings()

    var isEnabled: Bool
    var maxStoredRecords: Int

    init(isEnabled: Bool = true, maxStoredRecords: Int = ClipboardHistorySettings.defaultMaxStoredRecords) {
        self.isEnabled = isEnabled
        self.maxStoredRecords = Self.sanitizedMaxStoredRecords(maxStoredRecords)
    }

    static func sanitizedMaxStoredRecords(_ value: Int) -> Int {
        min(max(1, value), maxStoredRecordsLimit)
    }
}

protocol AppSettingsProviding {
    func loadSettings() -> LLMSettings
    func saveSettings(_ settings: LLMSettings)
}

protocol LLMSecretsStoring {
    func apiKey(for providerID: LLMProviderID) -> String
    func setAPIKey(_ apiKey: String, for providerID: LLMProviderID)
}

final class UserDefaultsLLMSecretsStore: LLMSecretsStoring {
    private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    func apiKey(for providerID: LLMProviderID) -> String {
        (userDefaults.string(forKey: key(for: providerID)) ?? "").trimmed
    }

    func setAPIKey(_ apiKey: String, for providerID: LLMProviderID) {
        let normalized = apiKey.trimmed
        if normalized.isEmpty {
            userDefaults.removeObject(forKey: key(for: providerID))
        } else {
            userDefaults.set(normalized, forKey: key(for: providerID))
        }
    }

    private func key(for providerID: LLMProviderID) -> String {
        "llmProvider_\(providerID.rawValue)_apiKey"
    }
}

final class UserDefaultsLLMSettingsStore: AppSettingsProviding {
    static let supportedProviders: [LLMProviderID] = [.openAI, .gemini]

    private struct Keys {
        let customGrammarInstructions: Defaults.Key<String>
        let customScreenshotInstructions: Defaults.Key<String>
        let voiceProviderID: Defaults.Key<String>
        let voiceGeminiModelID: Defaults.Key<String>
        let voiceOpenAIModelID: Defaults.Key<String>
        let voiceCustomInstructions: Defaults.Key<String>
        let voiceHotKeyTriggerKind: Defaults.Key<String>
        let voiceHotKeyCode: Defaults.Key<Int>
        let voiceHotKeyModifiers: Defaults.Key<Int>
        let voiceHotKeyMouseButtonNumber: Defaults.Key<Int>
        let clipboardHistoryEnabled: Defaults.Key<Bool>
        let clipboardHistoryMaxStoredRecords: Defaults.Key<Int>
        let userDefaults: UserDefaults

        init(userDefaults: UserDefaults) {
            self.userDefaults = userDefaults
            customGrammarInstructions = Defaults.Key<String>(
                "customGrammarInstructions",
                default: "",
                suite: userDefaults
            )
            customScreenshotInstructions = Defaults.Key<String>(
                "customScreenshotInstructions",
                default: "",
                suite: userDefaults
            )
            voiceProviderID = Defaults.Key<String>(
                "voiceProviderID",
                default: LLMProviderID.gemini.rawValue,
                suite: userDefaults
            )
            voiceGeminiModelID = Defaults.Key<String>(
                "voiceGeminiModelID",
                default: VoiceSettings.defaultGeminiModelID,
                suite: userDefaults
            )
            voiceOpenAIModelID = Defaults.Key<String>(
                "voiceOpenAIModelID",
                default: VoiceSettings.defaultOpenAIModelID,
                suite: userDefaults
            )
            voiceCustomInstructions = Defaults.Key<String>(
                "voiceCustomInstructions",
                default: "",
                suite: userDefaults
            )
            voiceHotKeyTriggerKind = Defaults.Key<String>(
                "voiceHotKeyTriggerKind",
                default: AppHotKey.TriggerKind.keyboard.rawValue,
                suite: userDefaults
            )
            voiceHotKeyCode = Defaults.Key<Int>(
                "voiceHotKeyCode",
                default: Int(AppHotKey.defaultVoiceDictation.carbonKeyCode),
                suite: userDefaults
            )
            voiceHotKeyModifiers = Defaults.Key<Int>(
                "voiceHotKeyModifiers",
                default: Int(AppHotKey.defaultVoiceDictation.carbonModifiers),
                suite: userDefaults
            )
            voiceHotKeyMouseButtonNumber = Defaults.Key<Int>(
                "voiceHotKeyMouseButtonNumber",
                default: 0,
                suite: userDefaults
            )
            clipboardHistoryEnabled = Defaults.Key<Bool>(
                "clipboardHistoryEnabled",
                default: ClipboardHistorySettings.default.isEnabled,
                suite: userDefaults
            )
            clipboardHistoryMaxStoredRecords = Defaults.Key<Int>(
                "clipboardHistoryMaxStoredRecords",
                default: ClipboardHistorySettings.default.maxStoredRecords,
                suite: userDefaults
            )
        }

        func modelID(for providerID: LLMProviderID) -> Defaults.Key<String> {
            Defaults.Key<String>(
                "llmProvider_\(providerID.rawValue)_modelID",
                default: providerID.defaultModelID,
                suite: userDefaults
            )
        }

    }

    private let keys: Keys
    private let secretsStore: any LLMSecretsStoring

    init(
        userDefaults: UserDefaults = .standard,
        secretsStore: any LLMSecretsStoring = UserDefaultsLLMSecretsStore()
    ) {
        self.keys = Keys(userDefaults: userDefaults)
        self.secretsStore = secretsStore
    }

    func loadSettings() -> LLMSettings {
        var profiles: [LLMProviderID: LLMProviderProfile] = [:]

        for providerID in Self.supportedProviders {
            let rawModelID = Defaults[keys.modelID(for: providerID)].trimmed
            let modelID = rawModelID.isEmpty ? providerID.defaultModelID : rawModelID

            profiles[providerID] = LLMProviderProfile(
                apiKey: secretsStore.apiKey(for: providerID),
                modelID: modelID
            )
        }

        let rawVoiceProviderID = Defaults[keys.voiceProviderID].trimmed
        let voiceProviderID = LLMProviderID(rawValue: rawVoiceProviderID) ?? .gemini
        let voiceHotKeyTriggerKind =
            AppHotKey.TriggerKind(rawValue: Defaults[keys.voiceHotKeyTriggerKind]) ?? .keyboard
        let voiceHotKey: AppHotKey
        switch voiceHotKeyTriggerKind {
        case .keyboard:
            voiceHotKey = AppHotKey(
                carbonKeyCode: UInt32(max(0, Defaults[keys.voiceHotKeyCode])),
                carbonModifiers: UInt32(max(0, Defaults[keys.voiceHotKeyModifiers]))
            )
        case .mouseButton:
            voiceHotKey = AppHotKey(
                mouseButtonNumber: max(0, Defaults[keys.voiceHotKeyMouseButtonNumber]),
                carbonModifiers: UInt32(max(0, Defaults[keys.voiceHotKeyModifiers]))
            )
        }

        return LLMSettings(
            providerProfiles: profiles,
            grammarCustomInstructions: Defaults[keys.customGrammarInstructions],
            screenshotCustomInstructions: Defaults[keys.customScreenshotInstructions],
            voice: VoiceSettings(
                providerID: voiceProviderID,
                geminiModelID: Defaults[keys.voiceGeminiModelID],
                openAIModelID: Defaults[keys.voiceOpenAIModelID],
                customInstructions: Defaults[keys.voiceCustomInstructions],
                hotKey: voiceHotKey
            ),
            clipboardHistory: ClipboardHistorySettings(
                isEnabled: Defaults[keys.clipboardHistoryEnabled],
                maxStoredRecords: Defaults[keys.clipboardHistoryMaxStoredRecords]
            )
        )
    }

    func saveSettings(_ settings: LLMSettings) {
        for providerID in Self.supportedProviders {
            let profile = settings.profile(for: providerID)

            secretsStore.setAPIKey(profile.apiKey, for: providerID)

            let normalizedModelID = profile.modelID.trimmed
            Defaults[keys.modelID(for: providerID)] =
                normalizedModelID.isEmpty ? providerID.defaultModelID : normalizedModelID
        }

        Defaults[keys.customGrammarInstructions] = settings.grammarCustomInstructions
        Defaults[keys.customScreenshotInstructions] = settings.screenshotCustomInstructions
        Defaults[keys.voiceProviderID] = settings.voice.providerID.rawValue
        Defaults[keys.voiceGeminiModelID] = settings.voice.modelID(for: .gemini)
        Defaults[keys.voiceOpenAIModelID] = settings.voice.modelID(for: .openAI)
        Defaults[keys.voiceCustomInstructions] = settings.voice.customInstructions
        Defaults[keys.voiceHotKeyTriggerKind] = settings.voice.hotKey.triggerKind.rawValue
        Defaults[keys.voiceHotKeyCode] = Int(settings.voice.hotKey.carbonKeyCode)
        Defaults[keys.voiceHotKeyModifiers] = Int(settings.voice.hotKey.carbonModifiers)
        Defaults[keys.voiceHotKeyMouseButtonNumber] = settings.voice.hotKey.mouseButtonNumber
        Defaults[keys.clipboardHistoryEnabled] = settings.clipboardHistory.isEnabled
        Defaults[keys.clipboardHistoryMaxStoredRecords] = settings.clipboardHistory.maxStoredRecords
    }
}
