import Foundation

public struct OpenAIClient: Sendable {
    private static let provider = "OpenAI"
    public let defaultModelID: String
    private let session: URLSession
    private static let responsesURL = URL(string: "https://api.openai.com/v1/responses")!
    private static let transcriptionURL = URL(string: "https://api.openai.com/v1/audio/transcriptions")!

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

    public init(defaultModelID: String, session: URLSession = .shared) {
        self.defaultModelID = defaultModelID.trimmingCharacters(in: .whitespacesAndNewlines)
        self.session = session
    }

    public func checkAccessStatus(apiKey: String, modelID: String) async -> LLMHealthCheckResult {
        let resolvedModelID = resolvedModelID(modelID)
        guard !resolvedModelID.isEmpty else {
            return LLMHealthCheckResult(status: .unknown, message: "OpenAI model identifier is invalid.")
        }

        let encodedModelID =
            resolvedModelID.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? resolvedModelID

        guard let apiURL = URL(string: "https://api.openai.com/v1/models/\(encodedModelID)") else {
            return LLMHealthCheckResult(status: .unknown, message: "OpenAI model identifier is invalid.")
        }

        var request = URLRequest(url: apiURL)
        request.httpMethod = "GET"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await performLLMDataRequest(request, session: session)
            guard let httpResponse = response as? HTTPURLResponse else {
                return LLMHealthCheckResult(status: .unknown, message: "OpenAI returned an unexpected response.")
            }

            return llmHealthCheckResult(for: httpResponse.statusCode, provider: Self.provider)
        } catch let error as URLError {
            return LLMHealthCheckResult(
                status: .networkIssue, message: llmNetworkErrorMessage(for: error, provider: Self.provider))
        } catch {
            return LLMHealthCheckResult(status: .unknown, message: error.localizedDescription)
        }
    }

    public func refineText(
        apiKey: String,
        modelID: String,
        customInstructions: String,
        text: String
    ) async throws -> String {
        let resolvedModelID = resolvedModelID(modelID)
        guard !resolvedModelID.isEmpty else {
            throw LLMClientError.requestFailed("OpenAI model identifier is invalid.")
        }

        let requestBody = ResponsesRequest(
            model: resolvedModelID,
            instructions: buildRefinePrompt(customInstructions: customInstructions),
            input: text,
            reasoning: reasoningEffort(for: resolvedModelID).map { ResponsesRequest.Reasoning(effort: $0) }
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            throw LLMClientError.encodingFailed(provider: Self.provider)
        }

        var request = URLRequest(url: Self.responsesURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

        let apiResponse = try JSONDecoder().decode(ResponsesResponse.self, from: data)

        guard let correctedText = apiResponse.outputText else {
            throw LLMClientError.emptyOutput(provider: Self.provider, detail: "OpenAI returned no corrected text.")
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
        let resolvedModelID = resolvedModelID(modelID)
        guard !resolvedModelID.isEmpty else {
            throw LLMClientError.requestFailed("OpenAI model identifier is invalid.")
        }

        let imageDataURL = "data:\(mimeType);base64,\(imageData.base64EncodedString())"
        let requestBody = ResponsesVisionRequest(
            model: resolvedModelID,
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
            reasoning: reasoningEffort(for: resolvedModelID).map { ResponsesVisionRequest.Reasoning(effort: $0) }
        )

        guard let httpBody = try? JSONEncoder().encode(requestBody) else {
            throw LLMClientError.encodingFailed(provider: Self.provider)
        }

        var request = URLRequest(url: Self.responsesURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
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

        let apiResponse = try JSONDecoder().decode(ResponsesResponse.self, from: data)

        guard let extractedText = apiResponse.outputText else {
            throw LLMClientError.emptyOutput(provider: Self.provider, detail: "OpenAI returned no corrected text.")
        }

        return extractedText
    }

    public func transcribeAudio(
        apiKey: String,
        modelID: String,
        audioData: Data,
        mimeType: String,
        options: VoiceTranscriptionOptions
    ) async throws -> String {
        let resolvedModelID = resolvedModelID(modelID)
        guard !resolvedModelID.isEmpty else {
            throw LLMClientError.requestFailed("OpenAI model identifier is invalid.")
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        let httpBody = multipartTranscriptionBody(
            boundary: boundary,
            modelID: resolvedModelID,
            prompt: buildVoiceTranscriptionPrompt(options: options),
            audioData: audioData,
            mimeType: mimeType
        )

        var request = URLRequest(url: Self.transcriptionURL)
        request.httpMethod = "POST"
        request.addValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.addValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.httpBody = httpBody

        let (data, response) = try await performLLMDataRequest(request, session: session)

        if let httpResponse = response as? HTTPURLResponse, !(200...299).contains(httpResponse.statusCode) {
            throw LLMClientError.requestFailed(
                llmRequestFailureMessage(statusCode: httpResponse.statusCode, data: data, provider: Self.provider))
        }

        guard !data.isEmpty else {
            throw LLMClientError.emptyResponse(provider: Self.provider)
        }

        guard let transcript = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
            !transcript.isEmpty
        else {
            throw LLMClientError.emptyOutput(provider: Self.provider, detail: "OpenAI returned no transcript.")
        }

        return transcript
    }

    private func reasoningEffort(for modelID: String) -> String? {
        return modelID.lowercased().hasPrefix("gpt-5") ? "none" : nil
    }

    private func resolvedModelID(_ modelID: String) -> String {
        let overrideModelID = modelID.trimmingCharacters(in: .whitespacesAndNewlines)
        return overrideModelID.isEmpty ? defaultModelID : overrideModelID
    }

    private func multipartTranscriptionBody(
        boundary: String,
        modelID: String,
        prompt: String,
        audioData: Data,
        mimeType: String
    ) -> Data {
        var body = Data()
        body.appendMultipartField(named: "model", value: modelID, boundary: boundary)
        body.appendMultipartField(named: "prompt", value: prompt, boundary: boundary)
        body.appendMultipartField(named: "response_format", value: "text", boundary: boundary)
        body.appendMultipartFile(
            named: "file",
            filename: "dictation.wav",
            mimeType: mimeType,
            data: audioData,
            boundary: boundary
        )
        body.appendString("--\(boundary)--\r\n")
        return body
    }
}

extension OpenAIClient: LLMClient {}

private extension Data {
    mutating func appendMultipartField(named name: String, value: String, boundary: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString("\(value)\r\n")
    }

    mutating func appendMultipartFile(
        named name: String,
        filename: String,
        mimeType: String,
        data: Data,
        boundary: String
    ) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        appendString("Content-Type: \(mimeType)\r\n\r\n")
        append(data)
        appendString("\r\n")
    }

    mutating func appendString(_ string: String) {
        append(Data(string.utf8))
    }
}
