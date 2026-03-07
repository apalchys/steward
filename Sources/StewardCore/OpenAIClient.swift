import Foundation

public struct OpenAIClient: Sendable {
    public static let defaultModelID = "gpt-5.4"
    private let session: URLSession
    private static let ocrInstruction = """
        You are an OCR assistant. Extract all visible text from the provided image and return only the extracted text in Markdown.
        Preserve headings, paragraphs, lists, tables, and code blocks when they are visually clear.
        Do not add explanations, summaries, or commentary.
        """
    private static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!

    private struct ResponsesRequest: Encodable {
        struct Reasoning: Encodable {
            let effort: String
        }

        let model: String
        let instructions: String
        let input: String
        let reasoning: Reasoning?
    }

    private struct ResponsesVisionRequest: Encodable {
        struct Reasoning: Encodable {
            let effort: String
        }

        struct InputItem: Encodable {
            let role: String
            let content: [ContentItem]
        }

        struct ContentItem: Encodable {
            let type: String
            let text: String?
            let imageURL: String?

            enum CodingKeys: String, CodingKey {
                case type
                case text
                case imageURL = "image_url"
            }

            static func inputText(_ text: String) -> ContentItem {
                ContentItem(type: "input_text", text: text, imageURL: nil)
            }

            static func inputImage(url: String) -> ContentItem {
                ContentItem(type: "input_image", text: nil, imageURL: url)
            }
        }

        let model: String
        let instructions: String
        let input: [InputItem]
        let reasoning: Reasoning?
    }

    private struct ResponsesResponse: Decodable {
        struct OutputItem: Decodable {
            struct ContentItem: Decodable {
                let type: String
                let text: String?
            }

            let type: String
            let content: [ContentItem]?
        }

        let output: [OutputItem]

        var outputText: String? {
            let text =
                output
                .filter { $0.type == "message" }
                .flatMap { $0.content ?? [] }
                .filter { $0.type == "output_text" }
                .compactMap { $0.text }
                .joined()

            return text.isEmpty ? nil : text
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
                return "Failed to encode the OpenAI request."
            case .requestFailed(let message):
                return message
            case .emptyResponse:
                return "OpenAI returned an empty response."
            case .emptyOutput:
                return "OpenAI returned no corrected text."
            }
        }
    }

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func checkAccess(apiKey: String, modelID: String) async -> Bool {
        await checkAccessStatus(apiKey: apiKey, modelID: modelID).hasAccess
    }

    public func checkAccessStatus(apiKey: String, modelID: String) async -> LLMHealthCheckResult {
        let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID

        guard let apiURL = URL(string: "https://api.openai.com/v1/models/\(encodedModelID)") else {
            return LLMHealthCheckResult(status: .unknown, message: "OpenAI model identifier is invalid.")
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await performDataRequest(request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return LLMHealthCheckResult(status: .unknown, message: "OpenAI returned an unexpected response.")
            }

            return healthCheckResult(for: httpResponse.statusCode)
        } catch let error as URLError {
            return LLMHealthCheckResult(status: .networkIssue, message: networkErrorMessage(for: error))
        } catch {
            return LLMHealthCheckResult(status: .unknown, message: error.localizedDescription)
        }
    }

    public func correctGrammar(
        apiKey: String,
        modelID: String,
        customInstructions: String,
        text: String
    ) async throws -> String {
        let requestBody = ResponsesRequest(
            model: modelID,
            instructions: buildGrammarPrompt(customInstructions: customInstructions),
            input: text,
            reasoning: reasoningEffort(for: modelID).map { ResponsesRequest.Reasoning(effort: $0) }
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            throw ClientError.encodingFailed
        }

        var request = URLRequest(url: Self.responsesURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let (data, response) = try await performDataRequest(request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = errorMessage(from: data) ?? "OpenAI request failed with HTTP \(httpResponse.statusCode)."
            throw ClientError.requestFailed(message)
        }

        guard !data.isEmpty else {
            throw ClientError.emptyResponse
        }

        let apiResponse = try JSONDecoder().decode(ResponsesResponse.self, from: data)

        guard let correctedText = apiResponse.outputText else {
            throw ClientError.emptyOutput
        }

        return correctedText
    }

    public func extractMarkdownText(
        apiKey: String,
        modelID: String,
        imageData: Data,
        mimeType: String,
        customInstructions: String = ""
    ) async throws -> String {
        let imageDataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        let requestBody = ResponsesVisionRequest(
            model: modelID,
            instructions: buildOCRPrompt(customInstructions: customInstructions),
            input: [
                .init(
                    role: "user",
                    content: [
                        .inputText("Extract all visible text from this screenshot selection and return Markdown only."),
                        .inputImage(url: imageDataURL),
                    ]
                )
            ],
            reasoning: reasoningEffort(for: modelID).map { ResponsesVisionRequest.Reasoning(effort: $0) }
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            throw ClientError.encodingFailed
        }

        var request = URLRequest(url: Self.responsesURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let (data, response) = try await performDataRequest(request)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            let message = errorMessage(from: data) ?? "OpenAI request failed with HTTP \(httpResponse.statusCode)."
            throw ClientError.requestFailed(message)
        }

        guard !data.isEmpty else {
            throw ClientError.emptyResponse
        }

        let apiResponse = try JSONDecoder().decode(ResponsesResponse.self, from: data)

        guard let extractedText = apiResponse.outputText else {
            throw ClientError.emptyOutput
        }

        return extractedText
    }

    private func reasoningEffort(for modelID: String) -> String? {
        return modelID.lowercased().hasPrefix("gpt-5") ? "none" : nil
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
            return LLMHealthCheckResult(status: .available, message: "OpenAI is configured.")
        case 401, 403:
            return LLMHealthCheckResult(status: .invalidCredentials, message: "OpenAI API key is invalid.")
        case 404:
            return LLMHealthCheckResult(status: .invalidModel, message: "OpenAI model was not found.")
        case 429:
            return LLMHealthCheckResult(status: .rateLimited, message: "OpenAI is rate limiting requests.")
        case 500, 502, 503, 504:
            return LLMHealthCheckResult(status: .serviceIssue, message: "OpenAI is temporarily unavailable.")
        default:
            return LLMHealthCheckResult(
                status: .unknown,
                message: "OpenAI access check failed with HTTP \(statusCode)."
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
            return "OpenAI request timed out."
        default:
            return "OpenAI could not be reached."
        }
    }

    private func errorMessage(from data: Data?) -> String? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(APIErrorResponse.self, from: data).error.message
    }

    private func buildOCRPrompt(customInstructions: String) -> String {
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

extension OpenAIClient: LLMClient {}
