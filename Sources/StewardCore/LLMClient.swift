import Foundation

public protocol LLMClient {
    func correctGrammar(
        apiKey: String,
        modelID: String,
        customInstructions: String,
        text: String,
        completion: @escaping (Result<String, Error>) -> Void
    )

    func extractMarkdownText(
        apiKey: String,
        modelID: String,
        imageData: Data,
        mimeType: String,
        customInstructions: String,
        completion: @escaping (Result<String, Error>) -> Void
    )
}
