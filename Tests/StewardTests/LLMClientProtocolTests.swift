import XCTest
@testable import StewardCore

final class LLMClientProtocolTests: XCTestCase {
    func testOpenAIAndGeminiConformToLLMClient() {
        assertConformance(OpenAIClient.self)
        assertConformance(GeminiClient.self)
    }

    private func assertConformance<T: LLMClient>(_: T.Type) {}
}

