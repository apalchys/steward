import AppKit
import HotKey

enum AppHotKeyValidationError: LocalizedError, Equatable {
    case requiresModifier
    case requiresNonModifierKey
    case requiresMouseButton
    case conflictsWithFeature(String)
    case unavailable

    var errorDescription: String? {
        switch self {
        case .requiresModifier:
            return "Dictate shortcuts must include at least one modifier key."
        case .requiresNonModifierKey:
            return "Dictate shortcuts must include a non-modifier key."
        case .requiresMouseButton:
            return "Dictate mouse shortcuts must use an extra mouse button."
        case .conflictsWithFeature(let featureName):
            return "Dictate shortcut conflicts with \(featureName)."
        case .unavailable:
            return "Dictate shortcut is already in use by another app."
        }
    }
}

struct AppHotKeyValidator {
    static func validateVoiceDictationHotKey(
        _ hotKey: AppHotKey,
        isShortcutAvailable: (Key, NSEvent.ModifierFlags) -> Bool
    ) -> AppHotKeyValidationError? {
        if hotKey == .grammarCheck {
            return .conflictsWithFeature("Refine")
        }

        if hotKey == .screenTextCapture {
            return .conflictsWithFeature("Capture")
        }

        if hotKey.isMouseButton {
            guard hotKey.mouseButtonNumber >= 2 else {
                return .requiresMouseButton
            }

            return nil
        }

        guard !hotKey.modifiers.intersection([.command, .shift, .option, .control]).isEmpty else {
            return .requiresModifier
        }

        guard let key = hotKey.key, !key.isModifierKey else {
            return .requiresNonModifierKey
        }

        guard isShortcutAvailable(key, hotKey.modifiers) else {
            return .unavailable
        }

        return nil
    }
}

private extension Key {
    var isModifierKey: Bool {
        switch self {
        case .command, .rightCommand, .option, .rightOption, .control, .rightControl, .shift, .rightShift, .function,
            .capsLock:
            return true
        default:
            return false
        }
    }
}
