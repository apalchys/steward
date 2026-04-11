import Foundation

public struct GeminiClient: Sendable {
    private static let provider = "Gemini"
    public let defaultModelID: String
    private let session: URLSession

    private struct GenerateContentRequest: Encodable {
        struct Content: Encodable {
            let parts: [Part]
        }

        struct Part: Encodable {
            let text: String?
            let inlineData: InlineData?

            init(text: String) {
                self.text = text
                self.inlineData = nil
            }

            init(inlineData: InlineData) {
                self.text = nil
                self.inlineData = inlineData
            }

            enum CodingKeys: String, CodingKey {
                case text
                case inlineData = "inline_data"
            }
        }

        struct InlineData: Encodable {
            let mimeType: String
            let data: String

            enum CodingKeys: String, CodingKey {
                case mimeType = "mime_type"
                case data
            }
        }

        let systemInstruction: Content
        let contents: [Content]

        enum CodingKeys: String, CodingKey {
            case systemInstruction = "system_instruction"
            case contents
        }
    }

    private struct GenerateContentResponse: Decodable {
        struct Candidate: Decodable {
            struct Content: Decodable {
                struct Part: Decodable {
                    let text: String?
                }

                let parts: [Part]?
            }

            let content: Content?
        }

        let candidates: [Candidate]?

        var outputText: String? {
            let text = candidates?
                .compactMap { $0.content?.parts }
                .flatMap { $0 }
                .compactMap { $0.text }
                .joined(separator: "\n")

            guard let text else {
                return nil
            }

            let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmedText.isEmpty ? nil : trimmedText
        }
    }

    public init(defaultModelID: String, session: URLSession = .shared) {
        self.defaultModelID = defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func checkAccessStatus(apiKey: String, modelID: String) async -> LLMHealthCheckResult {
        let resolvedModelID = resolvedModelID(modelID)
        guard !resolvedModelID.isEmpty else {
            return LLMHealthCheckResult(status: .unknown, message: "Gemini model identifier is invalid.")
        }

        let encodedModelID =
            resolvedModelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? resolvedModelID
        guard
            let apiURL = makeURL(
                path: "/v1beta/models/\(encodedModelID)",
                queryItems: [URLQueryItem(name: "key", value: apiKey)])
        else {
            return LLMHealthCheckResult(status: .unknown, message: "Gemini model identifier is invalid.")
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"

        do {
            let (_, response) = try await performLLMDataRequest(request, session: session)
            guard let httpResponse = response as? HTTPURLResponse else {
                return LLMHealthCheckResult(status: .unknown, message: "Gemini returned an unexpected response.")
            }

            return llmHealthCheckResult(for: httpResponse.statusCode, provider: Self.provider)
        } catch let error as URLError {
            return LLMHealthCheckResult(
                status: .networkIssue, message: llmNetworkErrorMessage(for: error, provider: Self.provider))
        } catch {
            return LLMHealthCheckResult(status: .unknown, message: error.localizedDescription)
        }
    }

    public func extractMarkdownText(
        apiKey: String,
        modelID: String,
        imageData: Data,
        mimeType: String,
        customInstructions: String = ""
    ) async throws -> String {
        let resolvedModelID = resolvedModelID(modelID)
        guard !resolvedModelID.isEmpty else {
            throw LLMClientError.requestFailed("Gemini model identifier is invalid.")
        }

        let combinedInstructions = buildOCRPrompt(customInstructions: customInstructions)
        let requestBody = GenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: combinedInstructions)]),
            contents: [
                .init(parts: [
                    .init(text: "Extract all visible text from this screenshot selection and return Markdown only."),
                    .init(inlineData: .init(mimeType: mimeType, data: imageData.base64EncodedString())),
                ])
            ]
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            throw LLMClientError.encodingFailed(provider: Self.provider)
        }

        let encodedModelID =
            resolvedModelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? resolvedModelID
        guard
            let apiURL = makeURL(
                path: "/v1beta/models/\(encodedModelID):generateContent",
                queryItems: [URLQueryItem(name: "key", value: apiKey)])
        else {
            throw LLMClientError.requestFailed("Gemini model identifier is invalid.")
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let (data, response) = try await performLLMDataRequest(request, session: session)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw LLMClientError.requestFailed(
                llmRequestFailureMessage(statusCode: httpResponse.statusCode, data: data, provider: Self.provider))
        }

        guard !data.isEmpty else {
            throw LLMClientError.emptyResponse(provider: Self.provider)
        }

        let apiResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

        guard let extractedText = apiResponse.outputText else {
            throw LLMClientError.emptyOutput(provider: Self.provider, detail: "Gemini returned no extracted text.")
        }

        return extractedText
    }

    public func correctGrammar(
        apiKey: String,
        modelID: String,
        customInstructions: String,
        text: String
    ) async throws -> String {
        let resolvedModelID = resolvedModelID(modelID)
        guard !resolvedModelID.isEmpty else {
            throw LLMClientError.requestFailed("Gemini model identifier is invalid.")
        }

        let requestBody = GenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: buildGrammarPrompt(customInstructions: customInstructions))]),
            contents: [
                .init(parts: [
                    .init(text: text)
                ])
            ]
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            throw LLMClientError.encodingFailed(provider: Self.provider)
        }

        let encodedModelID =
            resolvedModelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? resolvedModelID
        guard
            let apiURL = makeURL(
                path: "/v1beta/models/\(encodedModelID):generateContent",
                queryItems: [URLQueryItem(name: "key", value: apiKey)])
        else {
            throw LLMClientError.requestFailed("Gemini model identifier is invalid.")
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let (data, response) = try await performLLMDataRequest(request, session: session)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw LLMClientError.requestFailed(
                llmRequestFailureMessage(statusCode: httpResponse.statusCode, data: data, provider: Self.provider))
        }

        guard !data.isEmpty else {
            throw LLMClientError.emptyResponse(provider: Self.provider)
        }

        let apiResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

        guard let correctedText = apiResponse.outputText else {
            throw LLMClientError.emptyOutput(provider: Self.provider, detail: "Gemini returned no corrected text.")
        }

        return correctedText
    }

    public func transcribeAudio(
        apiKey: String,
        modelID: String,
        audioData: Data,
        mimeType: String,
        customInstructions: String
    ) async throws -> String {
        let resolvedModelID = resolvedModelID(modelID)
        guard !resolvedModelID.isEmpty else {
            throw LLMClientError.requestFailed("Gemini model identifier is invalid.")
        }

        let requestBody = GenerateContentRequest(
            systemInstruction: .init(parts: [
                .init(text: buildVoiceTranscriptionPrompt(customInstructions: customInstructions))
            ]),
            contents: [
                .init(parts: [
                    .init(text: "Transcribe this dictation and return only the final text."),
                    .init(inlineData: .init(mimeType: mimeType, data: audioData.base64EncodedString())),
                ])
            ]
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            throw LLMClientError.encodingFailed(provider: Self.provider)
        }

        let encodedModelID =
            resolvedModelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? resolvedModelID
        guard
            let apiURL = makeURL(
                path: "/v1beta/models/\(encodedModelID):generateContent",
                queryItems: [URLQueryItem(name: "key", value: apiKey)])
        else {
            throw LLMClientError.requestFailed("Gemini model identifier is invalid.")
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let (data, response) = try await performLLMDataRequest(request, session: session)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw LLMClientError.requestFailed(
                llmRequestFailureMessage(statusCode: httpResponse.statusCode, data: data, provider: Self.provider))
        }

        guard !data.isEmpty else {
            throw LLMClientError.emptyResponse(provider: Self.provider)
        }

        let apiResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

        guard let transcript = apiResponse.outputText else {
            throw LLMClientError.emptyOutput(provider: Self.provider, detail: "Gemini returned no transcript.")
        }

        return transcript
    }

    private func resolvedModelID(_ modelID: String) -> String {
        let overrideModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return overrideModelID.isEmpty ? defaultModelID : overrideModelID
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        guard let baseURL = URL(string: "https://generativelanguage.googleapis.com"),
            let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.queryItems = queryItems
        return components.url
    }
}

extension GeminiClient: LLMClient {}
