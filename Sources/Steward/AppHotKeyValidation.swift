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
    static func validateDictateHotKey(
        _ hotKey: AppHotKey,
        conflictingDictateHotKeys: [(AppHotKey, String)] = [],
        isShortcutAvailable: (Key, NSEvent.ModifierFlags) -> Bool
    ) -> AppHotKeyValidationError? {
        if hotKey == .refine {
            return .conflictsWithFeature("Refine")
        }

        if hotKey == .screenTextCapture {
            return .conflictsWithFeature("Capture")
        }

        for (conflictingHotKey, featureName) in conflictingDictateHotKeys where hotKey == conflictingHotKey {
            return .conflictsWithFeature(featureName)
        }

        if hotKey.isMouseButton {
            guard hotKey.mouseButtonNumber >= 2 else {
                return .requiresMouseButton
            }

            return nil
        }

        guard let key = hotKey.key, !key.isModifierKey else {
            return .requiresNonModifierKey
        }

        if !key.isFunctionKey {
            guard !hotKey.modifiers.intersection([.command, .shift, .option, .control]).isEmpty else {
                return .requiresModifier
            }
        }

        guard isShortcutAvailable(key, hotKey.modifiers) else {
            return .unavailable
        }

        return nil
    }
}

private extension Key {
    var isFunctionKey: Bool {
        switch self {
        case .f1, .f2, .f3, .f4, .f5, .f6, .f7, .f8, .f9, .f10,
            .f11, .f12, .f13, .f14, .f15, .f16, .f17, .f18, .f19, .f20:
            return true
        default:
            return false
        }
    }

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
