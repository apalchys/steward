import Foundation

// MARK: - Shared error type

/// Reusable error enum for LLM provider HTTP clients. Parameterized by provider
/// name so that each client's messages stay provider-specific.
public enum LLMClientError: LocalizedError, Equatable {
    case encodingFailed(provider: String)
    case requestFailed(String)
    case emptyResponse(provider: String)
    case emptyOutput(provider: String, detail: String)

    public var errorDescription: String? {
        switch self {
        case .encodingFailed(let provider):
            return "Failed to encode the \(provider) request."
        case .requestFailed(let message):
            return message
        case .emptyResponse(let provider):
            return "\(provider) returned an empty response."
        case .emptyOutput(_, let detail):
            return detail
        }
    }
}

// MARK: - Shared API error body

struct APIErrorBody: Decodable {
    struct Inner: Decodable {
        let message: String
    }

    let error: Inner
}

// MARK: - Retry helpers

func shouldRetryStatusCode(_ statusCode: Int) -> Bool {
    [429, 500, 502, 503, 504].contains(statusCode)
}

func shouldRetryURLError(_ error: URLError) -> Bool {
    switch error.code {
    case .timedOut, .networkConnectionLost, .notConnectedToInternet, .cannotConnectToHost, .cannotFindHost,
        .dnsLookupFailed:
        return true
    default:
        return false
    }
}

// MARK: - Retry-aware data request

func performLLMDataRequest(
    _ request: URLRequest,
    session: URLSession,
    maxRetries: Int = 2,
    initialDelayMilliseconds: Int = 200
) async throws -> (Data, URLResponse) {
    var attempt = 0
    var retryDelayMilliseconds = initialDelayMilliseconds

    while true {
        do {
            let response = try await session.data(for: request)
            if let httpResponse = response.1 as? HTTPURLResponse,
                shouldRetryStatusCode(httpResponse.statusCode),
                attempt < maxRetries
            {
                attempt += 1
                try? await Task.sleep(for: .milliseconds(retryDelayMilliseconds))
                retryDelayMilliseconds *= 2
                continue
            }

            return response
        } catch let error as URLError {
            guard shouldRetryURLError(error), attempt < maxRetries else {
                throw error
            }

            attempt += 1
            try? await Task.sleep(for: .milliseconds(retryDelayMilliseconds))
            retryDelayMilliseconds *= 2
        }
    }
}

// MARK: - Health check result builder

func llmHealthCheckResult(for statusCode: Int, provider: String) -> LLMHealthCheckResult {
    switch statusCode {
    case 200:
        return LLMHealthCheckResult(status: .available, message: "\(provider) is configured.")
    case 401, 403:
        return LLMHealthCheckResult(status: .invalidCredentials, message: "\(provider) API key is invalid.")
    case 404:
        return LLMHealthCheckResult(status: .invalidModel, message: "\(provider) model was not found.")
    case 429:
        return LLMHealthCheckResult(status: .rateLimited, message: "\(provider) is rate limiting requests.")
    case 500, 502, 503, 504:
        return LLMHealthCheckResult(status: .serviceIssue, message: "\(provider) is temporarily unavailable.")
    default:
        return LLMHealthCheckResult(
            status: .unknown,
            message: "\(provider) access check failed with HTTP \(statusCode)."
        )
    }
}

// MARK: - Network / request failure messages

func llmNetworkErrorMessage(for error: URLError, provider: String) -> String {
    switch error.code {
    case .notConnectedToInternet:
        return "No internet connection."
    case .timedOut:
        return "\(provider) request timed out."
    default:
        return "\(provider) could not be reached."
    }
}

func llmRequestFailureMessage(statusCode: Int, data: Data?, provider: String) -> String {
    switch statusCode {
    case 400:
        return llmApiErrorMessage(from: data) ?? "\(provider) rejected the request."
    case 401, 403:
        return "\(provider) API key is invalid."
    case 404:
        return "\(provider) model was not found."
    case 429:
        return "\(provider) is rate limiting requests."
    case 500, 502, 503, 504:
        return "\(provider) is temporarily unavailable."
    default:
        return llmApiErrorMessage(from: data) ?? "\(provider) request failed with HTTP \(statusCode)."
    }
}

func llmApiErrorMessage(from data: Data?) -> String? {
    guard let data else {
        return nil
    }

    let message = try? JSONDecoder().decode(APIErrorBody.self, from: data).error.message
    return message?.trimmingCharacters(in: .whitespacesAndNewlines)
}

// MARK: - Shared OCR prompt

private let ocrInstruction = """
    You are an OCR assistant. Extract all visible text from the provided image and return only the extracted text in Markdown.
    Preserve headings, paragraphs, lists, tables, and code blocks when they are visually clear.
    Do not add explanations, summaries, or commentary.
    """

func buildOCRPrompt(customInstructions: String) -> String {
    let trimmed = customInstructions.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return ocrInstruction
    }

    return """
        \(ocrInstruction)

        Additional instructions to follow:
        \(trimmed)
        """
}
