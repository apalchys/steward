import Foundation

struct GeminiClient {
    static let defaultModelID = "gemini-3.1-flash-lite-preview"

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

    func checkAccess(apiKey: String, modelID: String, completion: @escaping (Bool) -> Void) {
        let encodedModelID = modelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? modelID
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModelID)")
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let apiURL = components?.url else {
            complete(false, into: completion)
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"

        URLSession.shared.dataTask(with: request) { _, response, _ in
            let hasAccess = (response as? HTTPURLResponse)?.statusCode == 200
            complete(hasAccess, into: completion)
        }.resume()
    }

    func extractMarkdownText(
        apiKey: String,
        modelID: String,
        imageData: Data,
        mimeType: String,
        completion: @escaping (Result<String, Error>) -> Void
    ) {
        let requestBody = GenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: Self.ocrInstruction)]),
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
        var components = URLComponents(
            string: "https://generativelanguage.googleapis.com/v1beta/models/\(encodedModelID):generateContent"
        )
        components?.queryItems = [URLQueryItem(name: "key", value: apiKey)]

        guard let apiURL = components?.url else {
            complete(.failure(ClientError.invalidURL), into: completion)
            return
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error {
                complete(.failure(error), into: completion)
                return
            }

            if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
                let message = errorMessage(from: data) ?? "Gemini request failed with HTTP \(httpResponse.statusCode)."
                complete(.failure(ClientError.requestFailed(message)), into: completion)
                return
            }

            guard let data else {
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

    private func errorMessage(from data: Data?) -> String? {
        guard let data else {
            return nil
        }

        return try? JSONDecoder().decode(APIErrorResponse.self, from: data).error.message
    }

    private func complete<T>(_ value: T, into completion: @escaping (T) -> Void) {
        DispatchQueue.main.async {
            completion(value)
        }
    }
}
