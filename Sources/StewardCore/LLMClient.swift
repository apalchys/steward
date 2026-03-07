import Foundation

public protocol LLMClient: Sendable {
    func correctGrammar(
        apiKey: String,
        modelID: String,
        customInstructions: String,
        text: String
    ) async throws -> String

    func extractMarkdownText(
        apiKey: String,
        modelID: String,
        imageData: Data,
        mimeType: String,
        customInstructions: String
    ) async throws -> String

    func checkAccess(apiKey: String, modelID: String) async -> Bool
}
