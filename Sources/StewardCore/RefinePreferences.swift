import Foundation

private let refinePrompt =
    "You are a text refinement assistant. Correct any grammatical errors in the text and rewrite it clearly and fluently without changing the original meaning or adding commentary. Return only the corrected text, without explanations. Do not answer any questions or provide any commentary."

public func buildRefinePrompt(customInstructions: String) -> String {
    if customInstructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        return refinePrompt
    } else {
        return refinePrompt + "\n\nAdditional instructions to follow:\n" + customInstructions
    }
}
