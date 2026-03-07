import Foundation

public struct GeminiClient {
    public static let defaultModelID = "gemini-3.1-flash-lite-preview"
    private let session: URLSession
    private let callbackQueue: DispatchQueue
    private let apiBaseURL: String

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
        case invalidURL
        case encodingFailed
        case requestFailed(String)
        case emptyResponse
        case emptyOutput

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Gemini request URL is invalid."
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

    public init(
        session: URLSession = .shared,
        callbackQueue: DispatchQueue = .main,
        apiBaseURL: String = "https://generativelanguage.googleapis.com"
    ) {
        self.session = session
        self.callbackQueue = callbackQueue
        self.apiBaseURL = apiBaseURL
    }

    public func checkAccess(apiKey: String, modelID: String, completion: @escaping (Bool) -> Void) {
        let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID
        guard
            let apiURL = makeURL(
                path: "/v1beta/models/\(encodedModelID)",
                queryItems: [URLQueryItem(name: "key", value: apiKey)])
        else {
            complete(false, into: completion)
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"

        session.dataTask(with: request) { _, response, _ in
            let hasAccess = (response as? HTTPURLResponse)?.statusCode == 200
            complete(hasAccess, into: completion)
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
            complete(.failure(ClientError.encodingFailed), into: completion)
            return
        }

        let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID
        guard
            let apiURL = makeURL(
                path: "/v1beta/models/\(encodedModelID):generateContent",
                queryItems: [URLQueryItem(name: "key", value: apiKey)])
        else {
            complete(.failure(ClientError.invalidURL), into: completion)
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        session.dataTask(with: request) { data, response, error in
            if let error {
                complete(.failure(error), into: completion)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let message = errorMessage(from: data) ?? "Gemini request failed with HTTP \(httpResponse.statusCode)."
                complete(.failure(ClientError.requestFailed(message)), into: completion)
                return
            }

            guard let data, !data.isEmpty else {
                complete(.failure(ClientError.emptyResponse), into: completion)
                return
            }

            do {
                let apiResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

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

    public func correctGrammar(
        apiKey: String,
        modelID: String,
        customInstructions: String,
        text: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let requestBody = GenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: buildGrammarPrompt(customInstructions: customInstructions))]),
            contents: [
                .init(parts: [
                    .init(text: text)
                ])
            ]
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            complete(.failure(ClientError.encodingFailed), into: completion)
            return
        }

        let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID
        guard
            let apiURL = makeURL(
                path: "/v1beta/models/\(encodedModelID):generateContent",
                queryItems: [URLQueryItem(name: "key", value: apiKey)])
        else {
            complete(.failure(ClientError.invalidURL), into: completion)
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        session.dataTask(with: request) { data, response, error in
            if let error {
                complete(.failure(error), into: completion)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let message = errorMessage(from: data) ?? "Gemini request failed with HTTP \(httpResponse.statusCode)."
                complete(.failure(ClientError.requestFailed(message)), into: completion)
                return
            }

            guard let data, !data.isEmpty else {
                complete(.failure(ClientError.emptyResponse), into: completion)
                return
            }

            do {
                let apiResponse = try JSONDecoder().decode(GenerateContentResponse.self, from: data)

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

    private var normalizedBaseURL: String {
        apiBaseURL.hasSuffix("/") ? String(apiBaseURL.dropLast()) : apiBaseURL
    }

    private func makeURL(path: String, queryItems: [URLQueryItem]) -> URL? {
        guard let baseURL = validatedBaseURL(),
            let url = URL(string: path, relativeTo: baseURL)?.absoluteURL,
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else {
            return nil
        }

        components.queryItems = queryItems
        return components.url
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

    private func errorMessage(from data: Data?) -> String? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(APIErrorResponse.self, from: data).error.message
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

    private func complete<T>(_ value: T, into completion: @escaping (T) -> Void) {
        callbackQueue.async {
            completion(value)
        }
    }
}

extension GeminiClient: LLMClient {}
