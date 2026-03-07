import Foundation

public struct OpenAIClient {
    public static let defaultModelID = "gpt-5.4"
    private let session: URLSession
    private let callbackQueue: DispatchQueue
    private let apiBaseURL: String
    private static let ocrInstruction = """
        You are an OCR assistant. Extract all visible text from the provided image and return only the extracted text in Markdown.
        Preserve headings, paragraphs, lists, tables, and code blocks when they are visually clear.
        Do not add explanations, summaries, or commentary.
        """

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
        case invalidURL
        case encodingFailed
        case requestFailed(String)
        case emptyResponse
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "OpenAI request URL is invalid."
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

    public init(
        session: URLSession = .shared,
        callbackQueue: DispatchQueue = .main,
        apiBaseURL: String = "https://api.openai.com"
    ) {
        self.session = session
        self.callbackQueue = callbackQueue
        self.apiBaseURL = apiBaseURL
    }

    public func checkAccess(apiKey: String, modelID: String, completion: @escaping (Bool) -> Void) {
        let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID

        guard let apiURL = makeURL(path: "/v1/models/\(encodedModelID)") else {
            complete(false, into: completion)
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        session.dataTask(with: request) { _, response, _ in
            let hasAccess = (response as? HTTPURLResponse)?.statusCode == 200
            complete(hasAccess, into: completion)
        }.resume()
    }

    public func correctGrammar(
        apiKey: String,
        modelID: String,
        customInstructions: String,
        text: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let requestBody = ResponsesRequest(
            model: modelID,
            instructions: buildGrammarPrompt(customInstructions: customInstructions),
            input: text,
            reasoning: reasoningEffort(for: modelID).map { ResponsesRequest.Reasoning(effort: $0) }
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            complete(.failure(ClientError.encodingFailed), into: completion)
            return
        }

        guard let apiURL = makeURL(path: "/v1/responses") else {
            complete(.failure(ClientError.invalidURL), into: completion)
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        session.dataTask(with: request) { data, response, error in
            if let error {
                complete(.failure(error), into: completion)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let message = errorMessage(from: data) ?? "OpenAI request failed with HTTP \(httpResponse.statusCode)."
                complete(.failure(ClientError.requestFailed(message)), into: completion)
                return
            }

            guard let data, !data.isEmpty else {
                complete(.failure(ClientError.emptyResponse), into: completion)
                return
            }

            do {
                let apiResponse = try JSONDecoder().decode(ResponsesResponse.self, from: data)

                guard let correctedText = apiResponse.outputText else {
                    complete(.failure(ClientError.emptyOutput), into: completion)
                    return
                }

                complete(.success(correctedText), into: completion)
            } catch {
                complete(.failure(error), into: completion)
            }
        }.resume()
    }

    public func extractMarkdownText(
        apiKey: String,
        modelID: String,
        imageData: Data,
        mimeType: String,
        customInstructions: String = "",
        completion: @escaping (Result<String, Error>) -> Void
    ) {
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
            complete(.failure(ClientError.encodingFailed), into: completion)
            return
        }

        guard let apiURL = makeURL(path: "/v1/responses") else {
            complete(.failure(ClientError.invalidURL), into: completion)
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        session.dataTask(with: request) { data, response, error in
            if let error {
                complete(.failure(error), into: completion)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let message = errorMessage(from: data) ?? "OpenAI request failed with HTTP \(httpResponse.statusCode)."
                complete(.failure(ClientError.requestFailed(message)), into: completion)
                return
            }

            guard let data, !data.isEmpty else {
                complete(.failure(ClientError.emptyResponse), into: completion)
                return
            }

            do {
                let apiResponse = try JSONDecoder().decode(ResponsesResponse.self, from: data)

                guard let extractedText = apiResponse.outputText else {
                    complete(.failure(ClientError.emptyOutput), into: completion)
                    return
                }

                complete(.success(extractedText), into: completion)
            } catch {
                complete(.failure(error), into: completion)
            }
        }.resume()
    }

    private var normalizedBaseURL: String {
        apiBaseURL.hasSuffix("/") ? String(apiBaseURL.dropLast()) : apiBaseURL
    }

    private func makeURL(path: String) -> URL? {
        guard let baseURL = validatedBaseURL() else {
            return nil
        }

        return URL(string: path, relativeTo: baseURL)?.absoluteURL
    }

    private func validatedBaseURL() -> URL? {
        guard let baseURL = URL(string: normalizedBaseURL),
            let scheme = baseURL.scheme, !scheme.isEmpty,
            let host = baseURL.host, !host.isEmpty
        else {
            return nil
        }

        return baseURL
    }

    private func reasoningEffort(for modelID: String) -> String? {
        return modelID.lowercased().hasPrefix("gpt-5") ? "none" : nil
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

    private func complete<T>(_ value: T, into completion: @escaping (T) -> Void) {
        callbackQueue.async {
            completion(value)
        }
    }
}

extension OpenAIClient: LLMClient {}
