import Foundation

private let grammarCorrectionPrompt =
    "You are a grammar correction assistant. Correct any grammatical errors in the text and rewrite it clearly and fluently without changing the original meaning or adding commentary. Return only the corrected text, without explanations. Do not answer any questions or provide any commentary."

public func buildGrammarPrompt(customRules: String) -> String {
    if customRules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return grammarCorrectionPrompt
    } else {
        return grammarCorrectionPrompt + "\n\nAdditional rules to follow:\n" + customRules
    }
}

public func preferenceValue(forKey key: String, defaultValue: String) -> String {
    let storedValue = UserDefaults.standard.string(forKey: key)?
        .trimmingCharacters(in: .whitespacesAndNewlines)

    if let storedValue, !storedValue.isEmpty {
        return storedValue
    }

    return defaultValue
}

public func savePreferenceValue(_ value: String, forKey key: String, defaultValue: String) {
    let normalizedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
    UserDefaults.standard.set(normalizedValue.isEmpty ? defaultValue : normalizedValue, forKey: key)
}
