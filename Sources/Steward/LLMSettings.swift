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

struct RefineSettings: Equatable {
    static let `default` = RefineSettings(selectedModel: nil)

    var selectedModel: LLMModelSelection?
    var customInstructions: String

    init(selectedModel: LLMModelSelection? = RefineSettings.default.selectedModel, customInstructions: String = "") {
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

struct DictateMode: Equatable, Identifiable, Codable {
    static let defaultModeID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!

    let id: UUID
    var name: String
    var customInstructions: String
    var isDefault: Bool

    static func defaultMode(customInstructions: String = "") -> DictateMode {
        DictateMode(id: defaultModeID, name: "Default", customInstructions: customInstructions, isDefault: true)
    }
}

struct VoiceSettings: Equatable {
    static let `default` = VoiceSettings(selectedModel: nil, hotKey: .defaultVoiceDictation)
    static let maxPreferredRecognitionLanguages = 5

    var selectedModel: LLMModelSelection?
    var modes: [DictateMode]
    var activeModeID: UUID?
    var hotKey: AppHotKey
    var preferredRecognitionLanguages: [VoiceLanguage]
    var translateToLanguageEnabled: Bool
    var translationTargetLanguage: VoiceLanguage?
    private var legacyRegularModeHotKey: AppHotKey

    var activeMode: DictateMode {
        if let activeModeID, let mode = modes.first(where: { $0.id == activeModeID }) {
            return mode
        }
        return modes.first ?? DictateMode.defaultMode()
    }

    var customInstructions: String {
        get { activeMode.customInstructions }
        set {
            if let activeModeID, let index = modes.firstIndex(where: { $0.id == activeModeID }) {
                modes[index].customInstructions = newValue
            } else if let index = modes.indices.first {
                modes[index].customInstructions = newValue
            }
        }
    }

    init(
        selectedModel: LLMModelSelection? = nil,
        customInstructions: String = "",
        hotKey: AppHotKey = .defaultVoiceDictation,
        legacyRegularModeHotKey: AppHotKey = .defaultVoiceDictationRegular,
        preferredRecognitionLanguages: [VoiceLanguage] = [],
        translateToLanguageEnabled: Bool = false,
        translationTargetLanguage: VoiceLanguage? = nil,
        modes: [DictateMode] = [],
        activeModeID: UUID? = nil
    ) {
        self.selectedModel = selectedModel
        self.hotKey = hotKey
        self.preferredRecognitionLanguages = Self.sanitizedPreferredRecognitionLanguages(preferredRecognitionLanguages)
        self.translateToLanguageEnabled = translateToLanguageEnabled
        self.translationTargetLanguage = translationTargetLanguage
        self.legacyRegularModeHotKey = legacyRegularModeHotKey
        if modes.isEmpty {
            self.modes = [DictateMode.defaultMode(customInstructions: customInstructions)]
        } else {
            self.modes = modes
        }
        self.activeModeID = activeModeID
    }

    var pushToTalkHotKey: AppHotKey {
        get { hotKey }
        set { hotKey = newValue }
    }

    var regularModeHotKey: AppHotKey {
        get { legacyRegularModeHotKey }
        set { legacyRegularModeHotKey = newValue }
    }

    func sanitized() -> VoiceSettings {
        var sanitizedModes = modes
        if !sanitizedModes.contains(where: { $0.isDefault }) {
            sanitizedModes.insert(DictateMode.defaultMode(), at: 0)
        }
        let validActiveModeID = activeModeID.flatMap { id in
            sanitizedModes.contains(where: { $0.id == id }) ? id : nil
        }
        return VoiceSettings(
            selectedModel: selectedModel,
            hotKey: hotKey,
            legacyRegularModeHotKey: legacyRegularModeHotKey,
            preferredRecognitionLanguages: Self.sanitizedPreferredRecognitionLanguages(preferredRecognitionLanguages),
            translateToLanguageEnabled: translateToLanguageEnabled,
            translationTargetLanguage: translationTargetLanguage,
            modes: sanitizedModes,
            activeModeID: validActiveModeID
        )
    }

    static func == (lhs: VoiceSettings, rhs: VoiceSettings) -> Bool {
        lhs.selectedModel == rhs.selectedModel
            && lhs.modes == rhs.modes
            && lhs.activeModeID == rhs.activeModeID
            && lhs.hotKey == rhs.hotKey
            && lhs.preferredRecognitionLanguages == rhs.preferredRecognitionLanguages
            && lhs.translateToLanguageEnabled == rhs.translateToLanguageEnabled
            && lhs.translationTargetLanguage == rhs.translationTargetLanguage
    }

    private static func sanitizedPreferredRecognitionLanguages(_ languages: [VoiceLanguage]) -> [VoiceLanguage] {
        var seen: Set<VoiceLanguage> = []
        var result: [VoiceLanguage] = []

        for language in languages where !seen.contains(language) {
            seen.insert(language)
            result.append(language)

            if result.count == maxPreferredRecognitionLanguages {
                break
            }
        }

        return result
    }
}

struct AppHotKey: Equatable, Hashable {
    enum TriggerKind: String, Equatable, Hashable {
        case keyboard
        case mouseButton
    }

    static let refine = AppHotKey(
        carbonKeyCode: Key.f.carbonKeyCode,
        carbonModifiers: NSEvent.ModifierFlags([.command, .shift]).carbonFlags
    )
    static let screenTextCapture = AppHotKey(
        carbonKeyCode: Key.r.carbonKeyCode,
        carbonModifiers: NSEvent.ModifierFlags([.command, .shift]).carbonFlags
    )
    static let defaultVoiceDictation = AppHotKey(
        carbonKeyCode: Key.space.carbonKeyCode,
        carbonModifiers: NSEvent.ModifierFlags([.control, .shift]).carbonFlags
    )
    static let defaultVoiceDictationRegular = AppHotKey(
        carbonKeyCode: Key.d.carbonKeyCode,
        carbonModifiers: NSEvent.ModifierFlags([.command, .option]).carbonFlags
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
    var refine: RefineSettings
    var screenText: ScreenTextSettings
    var voice: VoiceSettings
    var clipboardHistory: ClipboardHistorySettings

    static func empty() -> LLMSettings {
        LLMSettings(
            providerSettings: [:],
            refine: .default,
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

        sanitizedSettings.refine.selectedModel = LLMModelCatalog.sanitizedSelection(
            sanitizedSettings.refine.selectedModel,
            for: .refine,
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
        sanitizedSettings.voice = sanitizedSettings.voice.sanitized()

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
        let refineSelectedProviderID: Defaults.Key<String>
        let refineSelectedModelID: Defaults.Key<String>
        let customRefineInstructions: Defaults.Key<String>
        let screenTextSelectedProviderID: Defaults.Key<String>
        let screenTextSelectedModelID: Defaults.Key<String>
        let customScreenshotInstructions: Defaults.Key<String>
        let voiceSelectedProviderID: Defaults.Key<String>
        let voiceSelectedModelID: Defaults.Key<String>
        let voiceCustomInstructions: Defaults.Key<String>
        let voiceDictateModes: Defaults.Key<String>
        let voiceActiveModeID: Defaults.Key<String>
        let voiceDictateHotKeyTriggerKind: Defaults.Key<String>
        let voiceDictateHotKeyCode: Defaults.Key<Int>
        let voiceDictateHotKeyModifiers: Defaults.Key<Int>
        let voiceDictateHotKeyMouseButtonNumber: Defaults.Key<Int>
        let voicePreferredRecognitionLanguageIDs: Defaults.Key<[String]>
        let voiceTranslateToLanguageEnabled: Defaults.Key<Bool>
        let voiceTranslationTargetLanguageID: Defaults.Key<String>
        let clipboardHistoryEnabled: Defaults.Key<Bool>
        let clipboardHistoryMaxStoredRecords: Defaults.Key<Int>

        init(userDefaults: UserDefaults) {
            refineSelectedProviderID = Defaults.Key<String>(
                "refineSelectedProviderID",
                default: "",
                suite: userDefaults
            )
            refineSelectedModelID = Defaults.Key<String>(
                "refineSelectedModelID",
                default: "",
                suite: userDefaults
            )
            customRefineInstructions = Defaults.Key<String>(
                "customRefineInstructions",
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
            voiceDictateModes = Defaults.Key<String>(
                "voiceDictateModes",
                default: "",
                suite: userDefaults
            )
            voiceActiveModeID = Defaults.Key<String>(
                "voiceActiveModeID",
                default: "",
                suite: userDefaults
            )
            voiceDictateHotKeyTriggerKind = Defaults.Key<String>(
                "voiceDictateHotKeyTriggerKind",
                default: AppHotKey.TriggerKind.keyboard.rawValue,
                suite: userDefaults
            )
            voiceDictateHotKeyCode = Defaults.Key<Int>(
                "voiceDictateHotKeyCode",
                default: Int(AppHotKey.defaultVoiceDictation.carbonKeyCode),
                suite: userDefaults
            )
            voiceDictateHotKeyModifiers = Defaults.Key<Int>(
                "voiceDictateHotKeyModifiers",
                default: Int(AppHotKey.defaultVoiceDictation.carbonModifiers),
                suite: userDefaults
            )
            voiceDictateHotKeyMouseButtonNumber = Defaults.Key<Int>(
                "voiceDictateHotKeyMouseButtonNumber",
                default: 0,
                suite: userDefaults
            )
            voicePreferredRecognitionLanguageIDs = Defaults.Key<[String]>(
                "voicePreferredRecognitionLanguageIDs",
                default: [],
                suite: userDefaults
            )
            voiceTranslateToLanguageEnabled = Defaults.Key<Bool>(
                "voiceTranslateToLanguageEnabled",
                default: false,
                suite: userDefaults
            )
            voiceTranslationTargetLanguageID = Defaults.Key<String>(
                "voiceTranslationTargetLanguageID",
                default: "",
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
    }

    private let keys: Keys
    private let userDefaults: UserDefaults
    private let secretsStore: any LLMSecretsStoring

    private enum LegacyVoiceHotKeyKey {
        static let triggerKind = "voiceHotKeyTriggerKind"
        static let code = "voiceHotKeyCode"
        static let modifiers = "voiceHotKeyModifiers"
        static let mouseButtonNumber = "voiceHotKeyMouseButtonNumber"
        static let regularTriggerKind = "voiceRegularHotKeyTriggerKind"
        static let regularCode = "voiceRegularHotKeyCode"
        static let regularModifiers = "voiceRegularHotKeyModifiers"
        static let regularMouseButtonNumber = "voiceRegularHotKeyMouseButtonNumber"
    }

    init(
        userDefaults: UserDefaults = .standard,
        secretsStore: any LLMSecretsStoring = UserDefaultsLLMSecretsStore()
    ) {
        self.userDefaults = userDefaults
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

        let refineSelection = readSelection(
            providerKey: keys.refineSelectedProviderID,
            modelKey: keys.refineSelectedModelID
        )
        let screenTextSelection = readSelection(
            providerKey: keys.screenTextSelectedProviderID,
            modelKey: keys.screenTextSelectedModelID
        )
        let voiceSelection = readSelection(
            providerKey: keys.voiceSelectedProviderID,
            modelKey: keys.voiceSelectedModelID
        )

        let voiceDictateHotKeyTriggerKind =
            AppHotKey.TriggerKind(rawValue: Defaults[keys.voiceDictateHotKeyTriggerKind]) ?? .keyboard
        let dictateHotKey = readHotKey(
            triggerKind: voiceDictateHotKeyTriggerKind,
            code: Defaults[keys.voiceDictateHotKeyCode],
            modifiers: Defaults[keys.voiceDictateHotKeyModifiers],
            mouseButtonNumber: Defaults[keys.voiceDictateHotKeyMouseButtonNumber]
        )

        let preferredRecognitionLanguages = Defaults[keys.voicePreferredRecognitionLanguageIDs].compactMap(
            VoiceLanguage.init(rawValue:))
        let translationTargetLanguage = VoiceLanguage(rawValue: Defaults[keys.voiceTranslationTargetLanguageID].trimmed)

        let dictateModes = loadDictateModes()
        let activeModeID = UUID(uuidString: Defaults[keys.voiceActiveModeID].trimmed)

        let settings = LLMSettings(
            providerSettings: providerSettings,
            refine: RefineSettings(
                selectedModel: refineSelection,
                customInstructions: Defaults[keys.customRefineInstructions]
            ),
            screenText: ScreenTextSettings(
                selectedModel: screenTextSelection,
                customInstructions: Defaults[keys.customScreenshotInstructions]
            ),
            voice: VoiceSettings(
                selectedModel: voiceSelection,
                hotKey: dictateHotKey,
                preferredRecognitionLanguages: preferredRecognitionLanguages,
                translateToLanguageEnabled: Defaults[keys.voiceTranslateToLanguageEnabled],
                translationTargetLanguage: translationTargetLanguage,
                modes: dictateModes,
                activeModeID: activeModeID
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
            sanitizedSettings.refine.selectedModel,
            providerKey: keys.refineSelectedProviderID,
            modelKey: keys.refineSelectedModelID
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

        Defaults[keys.customRefineInstructions] = sanitizedSettings.refine.customInstructions
        Defaults[keys.customScreenshotInstructions] = sanitizedSettings.screenText.customInstructions
        saveDictateModes(sanitizedSettings.voice.modes)
        Defaults[keys.voiceActiveModeID] = sanitizedSettings.voice.activeModeID?.uuidString ?? ""
        Defaults[keys.voiceCustomInstructions] = ""
        Defaults[keys.voiceDictateHotKeyTriggerKind] = sanitizedSettings.voice.hotKey.triggerKind.rawValue
        Defaults[keys.voiceDictateHotKeyCode] = Int(sanitizedSettings.voice.hotKey.carbonKeyCode)
        Defaults[keys.voiceDictateHotKeyModifiers] = Int(sanitizedSettings.voice.hotKey.carbonModifiers)
        Defaults[keys.voiceDictateHotKeyMouseButtonNumber] = sanitizedSettings.voice.hotKey.mouseButtonNumber
        Defaults[keys.voicePreferredRecognitionLanguageIDs] = sanitizedSettings.voice.preferredRecognitionLanguages.map(
            \.rawValue)
        Defaults[keys.voiceTranslateToLanguageEnabled] = sanitizedSettings.voice.translateToLanguageEnabled
        Defaults[keys.voiceTranslationTargetLanguageID] =
            sanitizedSettings.voice.translationTargetLanguage?.rawValue ?? ""
        Defaults[keys.clipboardHistoryEnabled] = sanitizedSettings.clipboardHistory.isEnabled
        Defaults[keys.clipboardHistoryMaxStoredRecords] = sanitizedSettings.clipboardHistory.maxStoredRecords
        clearLegacyVoiceHotKeyKeys()
    }

    private func readHotKey(
        triggerKind: AppHotKey.TriggerKind,
        code: Int,
        modifiers: Int,
        mouseButtonNumber: Int
    ) -> AppHotKey {
        switch triggerKind {
        case .keyboard:
            return AppHotKey(
                carbonKeyCode: UInt32(max(0, code)),
                carbonModifiers: UInt32(max(0, modifiers))
            )
        case .mouseButton:
            return AppHotKey(
                mouseButtonNumber: max(0, mouseButtonNumber),
                carbonModifiers: UInt32(max(0, modifiers))
            )
        }
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

    private func loadDictateModes() -> [DictateMode] {
        let json = Defaults[keys.voiceDictateModes]
        if !json.isEmpty,
            let data = json.data(using: .utf8),
            let modes = try? JSONDecoder().decode([DictateMode].self, from: data),
            !modes.isEmpty
        {
            return modes
        }
        let legacyInstructions = Defaults[keys.voiceCustomInstructions]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return [DictateMode.defaultMode(customInstructions: legacyInstructions)]
    }

    private func saveDictateModes(_ modes: [DictateMode]) {
        if let data = try? JSONEncoder().encode(modes),
            let json = String(data: data, encoding: .utf8)
        {
            Defaults[keys.voiceDictateModes] = json
        }
    }

    private func clearLegacyVoiceHotKeyKeys() {
        userDefaults.removeObject(forKey: LegacyVoiceHotKeyKey.triggerKind)
        userDefaults.removeObject(forKey: LegacyVoiceHotKeyKey.code)
        userDefaults.removeObject(forKey: LegacyVoiceHotKeyKey.modifiers)
        userDefaults.removeObject(forKey: LegacyVoiceHotKeyKey.mouseButtonNumber)
        userDefaults.removeObject(forKey: LegacyVoiceHotKeyKey.regularTriggerKind)
        userDefaults.removeObject(forKey: LegacyVoiceHotKeyKey.regularCode)
        userDefaults.removeObject(forKey: LegacyVoiceHotKeyKey.regularModifiers)
        userDefaults.removeObject(forKey: LegacyVoiceHotKeyKey.regularMouseButtonNumber)
    }

}
