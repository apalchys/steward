import AppKit
import Defaults
import Foundation
import HotKey
import OSLog
import StewardCore

private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.steward", category: "settings")

struct LLMProviderSettings: Equatable {
    var apiKey: String

    static var empty: LLMProviderSettings {
        LLMProviderSettings(apiKey: "")
    }

    var isEnabled: Bool {
        !apiKey.trimmed.isEmpty
    }
}

struct GrammarSettings: Equatable {
    static let `default` = GrammarSettings(selectedModel: nil)

    var selectedModel: LLMModelSelection?
    var customInstructions: String

    init(selectedModel: LLMModelSelection? = GrammarSettings.default.selectedModel, customInstructions: String = "") {
        self.selectedModel = selectedModel
        self.customInstructions = customInstructions
    }
}

struct ScreenTextSettings: Equatable {
    static let `default` = ScreenTextSettings(selectedModel: nil)

    var selectedModel: LLMModelSelection?
    var customInstructions: String

    init(selectedModel: LLMModelSelection? = ScreenTextSettings.default.selectedModel, customInstructions: String = "")
    {
        self.selectedModel = selectedModel
        self.customInstructions = customInstructions
    }
}

struct VoiceSettings: Equatable {
    static let `default` = VoiceSettings(selectedModel: nil)

    var selectedModel: LLMModelSelection?
    var customInstructions: String
    var hotKey: AppHotKey

    init(
        selectedModel: LLMModelSelection? = VoiceSettings.default.selectedModel,
        customInstructions: String = "",
        hotKey: AppHotKey = .defaultVoiceDictation
    ) {
        self.selectedModel = selectedModel
        self.customInstructions = customInstructions
        self.hotKey = hotKey
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
    var providerSettings: [LLMProviderID: LLMProviderSettings]
    var grammar: GrammarSettings
    var screenText: ScreenTextSettings
    var voice: VoiceSettings
    var clipboardHistory: ClipboardHistorySettings

    static func empty() -> LLMSettings {
        LLMSettings(
            providerSettings: [:],
            grammar: .default,
            screenText: .default,
            voice: .default,
            clipboardHistory: .default
        )
    }

    func providerSettings(for providerID: LLMProviderID) -> LLMProviderSettings {
        providerSettings[providerID] ?? .empty
    }

    var enabledProviderIDs: Set<LLMProviderID> {
        Set(
            LLMProviderID.allCases.filter {
                providerSettings(for: $0).isEnabled
            }
        )
    }

    func availableModels(for feature: LLMFeature) -> [LLMModelCatalogEntry] {
        LLMModelCatalog.entries(for: feature, enabledProviders: enabledProviderIDs)
    }

    func sanitized() -> LLMSettings {
        var sanitizedSettings = self
        let enabledProviders = sanitizedSettings.enabledProviderIDs

        sanitizedSettings.grammar.selectedModel = LLMModelCatalog.sanitizedSelection(
            sanitizedSettings.grammar.selectedModel,
            for: .grammar,
            enabledProviders: enabledProviders
        )
        sanitizedSettings.screenText.selectedModel = LLMModelCatalog.sanitizedSelection(
            sanitizedSettings.screenText.selectedModel,
            for: .screenText,
            enabledProviders: enabledProviders
        )
        sanitizedSettings.voice.selectedModel = LLMModelCatalog.sanitizedSelection(
            sanitizedSettings.voice.selectedModel,
            for: .voice,
            enabledProviders: enabledProviders
        )

        return sanitizedSettings
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
        let grammarSelectedProviderID: Defaults.Key<String>
        let grammarSelectedModelID: Defaults.Key<String>
        let customGrammarInstructions: Defaults.Key<String>
        let screenTextSelectedProviderID: Defaults.Key<String>
        let screenTextSelectedModelID: Defaults.Key<String>
        let customScreenshotInstructions: Defaults.Key<String>
        let voiceSelectedProviderID: Defaults.Key<String>
        let voiceSelectedModelID: Defaults.Key<String>
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
            grammarSelectedProviderID = Defaults.Key<String>(
                "grammarSelectedProviderID",
                default: "",
                suite: userDefaults
            )
            grammarSelectedModelID = Defaults.Key<String>(
                "grammarSelectedModelID",
                default: "",
                suite: userDefaults
            )
            customGrammarInstructions = Defaults.Key<String>(
                "customGrammarInstructions",
                default: "",
                suite: userDefaults
            )
            screenTextSelectedProviderID = Defaults.Key<String>(
                "screenTextSelectedProviderID",
                default: "",
                suite: userDefaults
            )
            screenTextSelectedModelID = Defaults.Key<String>(
                "screenTextSelectedModelID",
                default: "",
                suite: userDefaults
            )
            customScreenshotInstructions = Defaults.Key<String>(
                "customScreenshotInstructions",
                default: "",
                suite: userDefaults
            )
            voiceSelectedProviderID = Defaults.Key<String>(
                "voiceSelectedProviderID",
                default: "",
                suite: userDefaults
            )
            voiceSelectedModelID = Defaults.Key<String>(
                "voiceSelectedModelID",
                default: "",
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

        func legacyProviderModelKey(for providerID: LLMProviderID) -> String {
            "llmProvider_\(providerID.rawValue)_modelID"
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
        var providerSettings: [LLMProviderID: LLMProviderSettings] = [:]

        for providerID in Self.supportedProviders {
            providerSettings[providerID] = LLMProviderSettings(
                apiKey: secretsStore.apiKey(for: providerID)
            )
        }

        let grammarSelection =
            readSelection(
                providerKey: keys.grammarSelectedProviderID,
                modelKey: keys.grammarSelectedModelID
            ) ?? legacySelection(for: .grammar)
        let screenTextSelection =
            readSelection(
                providerKey: keys.screenTextSelectedProviderID,
                modelKey: keys.screenTextSelectedModelID
            ) ?? legacySelection(for: .screenText)
        let voiceSelection =
            readSelection(
                providerKey: keys.voiceSelectedProviderID,
                modelKey: keys.voiceSelectedModelID
            ) ?? legacySelection(for: .voice)

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

        let settings = LLMSettings(
            providerSettings: providerSettings,
            grammar: GrammarSettings(
                selectedModel: grammarSelection,
                customInstructions: Defaults[keys.customGrammarInstructions]
            ),
            screenText: ScreenTextSettings(
                selectedModel: screenTextSelection,
                customInstructions: Defaults[keys.customScreenshotInstructions]
            ),
            voice: VoiceSettings(
                selectedModel: voiceSelection,
                customInstructions: Defaults[keys.voiceCustomInstructions],
                hotKey: voiceHotKey
            ),
            clipboardHistory: ClipboardHistorySettings(
                isEnabled: Defaults[keys.clipboardHistoryEnabled],
                maxStoredRecords: Defaults[keys.clipboardHistoryMaxStoredRecords]
            )
        )

        return settings.sanitized()
    }

    func saveSettings(_ settings: LLMSettings) {
        let sanitizedSettings = settings.sanitized()

        for providerID in Self.supportedProviders {
            let providerSetting = sanitizedSettings.providerSettings(for: providerID)
            secretsStore.setAPIKey(providerSetting.apiKey, for: providerID)
        }

        saveSelection(
            sanitizedSettings.grammar.selectedModel,
            providerKey: keys.grammarSelectedProviderID,
            modelKey: keys.grammarSelectedModelID
        )
        saveSelection(
            sanitizedSettings.screenText.selectedModel,
            providerKey: keys.screenTextSelectedProviderID,
            modelKey: keys.screenTextSelectedModelID
        )
        saveSelection(
            sanitizedSettings.voice.selectedModel,
            providerKey: keys.voiceSelectedProviderID,
            modelKey: keys.voiceSelectedModelID
        )

        Defaults[keys.customGrammarInstructions] = sanitizedSettings.grammar.customInstructions
        Defaults[keys.customScreenshotInstructions] = sanitizedSettings.screenText.customInstructions
        Defaults[keys.voiceCustomInstructions] = sanitizedSettings.voice.customInstructions
        Defaults[keys.voiceHotKeyTriggerKind] = sanitizedSettings.voice.hotKey.triggerKind.rawValue
        Defaults[keys.voiceHotKeyCode] = Int(sanitizedSettings.voice.hotKey.carbonKeyCode)
        Defaults[keys.voiceHotKeyModifiers] = Int(sanitizedSettings.voice.hotKey.carbonModifiers)
        Defaults[keys.voiceHotKeyMouseButtonNumber] = sanitizedSettings.voice.hotKey.mouseButtonNumber
        Defaults[keys.clipboardHistoryEnabled] = sanitizedSettings.clipboardHistory.isEnabled
        Defaults[keys.clipboardHistoryMaxStoredRecords] = sanitizedSettings.clipboardHistory.maxStoredRecords

        clearLegacyModelKeys()
    }

    private func readSelection(
        providerKey: Defaults.Key<String>,
        modelKey: Defaults.Key<String>
    ) -> LLMModelSelection? {
        let rawProviderID = Defaults[providerKey].trimmed
        let rawModelID = Defaults[modelKey].trimmed

        guard !rawProviderID.isEmpty, !rawModelID.isEmpty, let providerID = LLMProviderID(rawValue: rawProviderID)
        else {
            return nil
        }

        return LLMModelSelection(providerID: providerID, modelID: rawModelID)
    }

    private func saveSelection(
        _ selection: LLMModelSelection?,
        providerKey: Defaults.Key<String>,
        modelKey: Defaults.Key<String>
    ) {
        Defaults[providerKey] = selection?.providerID.rawValue ?? ""
        Defaults[modelKey] = selection?.modelID ?? ""
    }

    private func legacySelection(for feature: LLMFeature) -> LLMModelSelection? {
        switch feature {
        case .grammar:
            return LLMModelSelection(
                providerID: .openAI,
                modelID: legacyProviderModelID(for: .openAI)
            )
        case .screenText:
            return LLMModelSelection(
                providerID: .gemini,
                modelID: legacyProviderModelID(for: .gemini)
            )
        case .voice:
            let providerID = legacyVoiceProviderID()
            return LLMModelSelection(
                providerID: providerID,
                modelID: legacyVoiceModelID(for: providerID)
            )
        }
    }

    private func legacyProviderModelID(for providerID: LLMProviderID) -> String {
        let key = keys.legacyProviderModelKey(for: providerID)
        let rawModelID = (keys.userDefaults.string(forKey: key) ?? "").trimmed
        return rawModelID.isEmpty ? LLMModelCatalog.defaultModelID(for: providerID) : rawModelID
    }

    private func legacyVoiceProviderID() -> LLMProviderID {
        let rawVoiceProviderID = (keys.userDefaults.string(forKey: "voiceProviderID") ?? "").trimmed
        return LLMProviderID(rawValue: rawVoiceProviderID) ?? .gemini
    }

    private func legacyVoiceModelID(for providerID: LLMProviderID) -> String {
        switch providerID {
        case .gemini:
            let rawModelID = (keys.userDefaults.string(forKey: "voiceGeminiModelID") ?? "").trimmed
            return rawModelID.isEmpty ? LLMModelCatalog.defaultModelID(for: .gemini) : rawModelID
        case .openAI:
            let rawModelID = (keys.userDefaults.string(forKey: "voiceOpenAIModelID") ?? "").trimmed
            return rawModelID.isEmpty ? "gpt-4o-mini-transcribe" : rawModelID
        }
    }

    private func clearLegacyModelKeys() {
        for providerID in Self.supportedProviders {
            keys.userDefaults.removeObject(forKey: keys.legacyProviderModelKey(for: providerID))
        }

        keys.userDefaults.removeObject(forKey: "voiceProviderID")
        keys.userDefaults.removeObject(forKey: "voiceGeminiModelID")
        keys.userDefaults.removeObject(forKey: "voiceOpenAIModelID")
    }
}
