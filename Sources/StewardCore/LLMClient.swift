import Foundation

public enum LLMHealthCheckStatus: Sendable, Equatable {
    case available
    case invalidCredentials
    case invalidModel
    case networkIssue
    case rateLimited
    case serviceIssue
    case unknown
}

public struct LLMHealthCheckResult: Sendable, Equatable {
    public let status: LLMHealthCheckStatus
    public let message: String

    public init(status: LLMHealthCheckStatus, message: String) {
        self.status = status
        self.message = message
    }

    public var hasAccess: Bool {
        status == .available
    }
}

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
    func checkAccessStatus(apiKey: String, modelID: String) async -> LLMHealthCheckResult
}
