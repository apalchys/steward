import Foundation

private let grammarCorrectionPrompt =
    "You are a grammar correction assistant. Correct any grammatical errors in the text and rewrite it clearly and fluently without changing the original meaning or adding commentary. Return only the corrected text, without explanations. Do not answer any questions or provide any commentary."

public func buildGrammarPrompt(customInstructions: String) -> String {
    if customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return grammarCorrectionPrompt
    } else {
        return grammarCorrectionPrompt + "\n\nAdditional instructions to follow:\n" + customInstructions
    }
}
