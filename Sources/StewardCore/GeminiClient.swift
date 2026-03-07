import Foundation

public struct GeminiClient: Sendable {
    public static let defaultModelID = "gemini-3.1-flash-lite-preview"
    private let session: URLSession

    private static let ocrInstruction = """
        You are an OCR assistant. Extract all visible text from the provided image and return only the extracted text in Markdown.
        Preserve headings, paragraphs, lists, tables, and code blocks when they are visually clear.
        Do not add explanations, summaries, or commentary.
        """

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

    private struct APIErrorResponse: Decodable {
        struct APIError: Decodable {
            let message: String
        }

        let error: APIError
    }

    private enum ClientError: LocalizedError {
        case encodingFailed
        case requestFailed(String)
        case emptyResponse
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .encodingFailed:
                return "Failed to encode the Gemini request."
            case .requestFailed(let message):
                return message
            case .emptyResponse:
                return "Gemini returned an empty response."
            case .emptyOutput:
                return "Gemini returned no extracted text."
            }
        }
    }

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func checkAccessStatus(apiKey: String, modelID: String) async -> LLMHealthCheckResult {
        let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID
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
            let (_, response) = try await performDataRequest(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return LLMHealthCheckResult(status: .unknown, message: "Gemini returned an unexpected response.")
            }

            return healthCheckResult(for: httpResponse.statusCode)
        } catch let error as URLError {
            return LLMHealthCheckResult(status: .networkIssue, message: networkErrorMessage(for: error))
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
        let combinedInstructions = buildOCRInstructions(customInstructions: customInstructions)
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
            throw ClientError.encodingFailed
        }

        let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID
        guard
            let apiURL = makeURL(
                path: "/v1beta/models/\(encodedModelID):generateContent",
                queryItems: [URLQueryItem(name: "key", value: apiKey)])
        else {
            throw ClientError.requestFailed("Gemini model identifier is invalid.")
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let (data, response) = try await performDataRequest(request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw ClientError.requestFailed(requestFailureMessage(statusCode: httpResponse.statusCode, data: data))
        }

        guard !data.isEmpty else {
            throw ClientError.emptyResponse
        }

        let apiResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

        guard let extractedText = apiResponse.outputText else {
            throw ClientError.emptyOutput
        }

        return extractedText
    }

    public func correctGrammar(
        apiKey: String,
        modelID: String,
        customInstructions: String,
        text: String
    ) async throws -> String {
        let requestBody = GenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: buildGrammarPrompt(customInstructions: customInstructions))]),
            contents: [
                .init(parts: [
                    .init(text: text)
                ])
            ]
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            throw ClientError.encodingFailed
        }

        let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID
        guard
            let apiURL = makeURL(
                path: "/v1beta/models/\(encodedModelID):generateContent",
                queryItems: [URLQueryItem(name: "key", value: apiKey)])
        else {
            throw ClientError.requestFailed("Gemini model identifier is invalid.")
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let (data, response) = try await performDataRequest(request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw ClientError.requestFailed(requestFailureMessage(statusCode: httpResponse.statusCode, data: data))
        }

        guard !data.isEmpty else {
            throw ClientError.emptyResponse
        }

        let apiResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

        guard let correctedText = apiResponse.outputText else {
            throw ClientError.emptyOutput
        }

        return correctedText
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

    private func requestFailureMessage(statusCode: Int, data: Data?) -> String {
        switch statusCode {
        case 400:
            return apiErrorMessage(from: data) ?? "Gemini rejected the request."
        case 401, 403:
            return "Gemini API key is invalid."
        case 404:
            return "Gemini model was not found."
        case 429:
            return "Gemini is rate limiting requests."
        case 500, 502, 503, 504:
            return "Gemini is temporarily unavailable."
        default:
            return apiErrorMessage(from: data) ?? "Gemini request failed with HTTP \(statusCode)."
        }
    }

    private func apiErrorMessage(from data: Data?) -> String? {
        guard let data else {
            return nil
        }

        let message = try? JSONDecoder().decode(APIErrorResponse.self, from: data).error.message
        return message?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func performDataRequest(_ request: URLRequest) async throws -> (Data, URLResponse) {
        var attempt = 0
        var retryDelayMilliseconds = 200

        while true {
            do {
                let response = try await session.data(for: request)
                if let httpResponse = response.1 as? HTTPURLResponse,
                    shouldRetry(statusCode: httpResponse.statusCode),
                    attempt < 2
                {
                    attempt += 1
                    try? await Task.sleep(for: .milliseconds(retryDelayMilliseconds))
                    retryDelayMilliseconds *= 2
                    continue
                }

                return response
            } catch let error as URLError {
                guard shouldRetry(error: error), attempt < 2 else {
                    throw error
                }

                attempt += 1
                try? await Task.sleep(for: .milliseconds(retryDelayMilliseconds))
                retryDelayMilliseconds *= 2
            }
        }
    }

    private func healthCheckResult(for statusCode: Int) -> LLMHealthCheckResult {
        switch statusCode {
        case 200:
            return LLMHealthCheckResult(status: .available, message: "Gemini is configured.")
        case 401, 403:
            return LLMHealthCheckResult(status: .invalidCredentials, message: "Gemini API key is invalid.")
        case 404:
            return LLMHealthCheckResult(status: .invalidModel, message: "Gemini model was not found.")
        case 429:
            return LLMHealthCheckResult(status: .rateLimited, message: "Gemini is rate limiting requests.")
        case 500, 502, 503, 504:
            return LLMHealthCheckResult(status: .serviceIssue, message: "Gemini is temporarily unavailable.")
        default:
            return LLMHealthCheckResult(
                status: .unknown,
                message: "Gemini access check failed with HTTP \(statusCode)."
            )
        }
    }

    private func shouldRetry(statusCode: Int) -> Bool {
        [429, 500, 502, 503, 504].contains(statusCode)
    }

    private func shouldRetry(error: URLError) -> Bool {
        switch error.code {
        case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
            .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    private func networkErrorMessage(for error: URLError) -> String {
        switch error.code {
        case .notConnectedToInternet:
            return "No internet connection."
        case .timedOut:
            return "Gemini request timed out."
        default:
            return "Gemini could not be reached."
        }
    }

    private func buildOCRInstructions(customInstructions: String) -> String {
        let trimmedCustomInstructions = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedCustomInstructions.isEmpty else {
            return Self.ocrInstruction
        }

        return """
            \(Self.ocrInstruction)

            Additional instructions to follow:
            \(trimmedCustomInstructions)
            """
    }
}

extension GeminiClient: LLMClient {}
