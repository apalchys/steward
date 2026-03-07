import Foundation
import XCTest
@testable import Steward
@testable import StewardCore

final class LLMProviderAdapterTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testOpenAIAdapterMapsGrammarTaskToOpenAIClient() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")

            let body = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["model"] as? String, "gpt-5.4")
            XCTAssertEqual(payload["input"] as? String, "bad text")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
                {"output":[{"type":"message","content":[{"type":"output_text","text":"good text"}]}]}
                """.data(using: .utf8)
            return (response, data)
        })

        let provider = OpenAILLMProvider(
            client: OpenAIClient(session: URLProtocolStub.makeSession())
        )

        let result = try await provider.perform(
            task: .grammarCorrection(text: "bad text", customInstructions: ""),
            configuration: LLMProviderConfiguration(apiKey: "sk-test", modelID: "gpt-5.4", baseURL: nil)
        )

        XCTAssertEqual(result.textValue, "good text")
    }

    func testGeminiAdapterMapsOCRTaskToGeminiClient() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=test-key"
            )

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
                {"candidates":[{"content":{"parts":[{"text":"Extracted"}]}}]}
                """.data(using: .utf8)
            return (response, data)
        })

        let provider = GeminiLLMProvider(
            client: GeminiClient(session: URLProtocolStub.makeSession())
        )

        let result = try await provider.perform(
            task: .screenOCR(
                imageData: Data("image".utf8),
                mimeType: "image/png",
                customInstructions: ""
            ),
            configuration: LLMProviderConfiguration(
                apiKey: "test-key",
                modelID: GeminiClient.defaultModelID,
                baseURL: nil
            )
        )

        XCTAssertEqual(result.textValue, "Extracted")
    }

    func testOpenAIAdapterMapsOCRTaskToOpenAIClient() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")

            let body = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["model"] as? String, "gpt-5.4")

            let input = try XCTUnwrap(payload["input"] as? [[String: Any]])
            let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
            XCTAssertEqual(content.first?["type"] as? String, "input_text")
            XCTAssertEqual(content.last?["type"] as? String, "input_image")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
                {"output":[{"type":"message","content":[{"type":"output_text","text":"Extracted"}]}]}
                """.data(using: .utf8)
            return (response, data)
        })

        let provider = OpenAILLMProvider(
            client: OpenAIClient(session: URLProtocolStub.makeSession())
        )

        let result = try await provider.perform(
            task: .screenOCR(
                imageData: Data("image".utf8),
                mimeType: "image/png",
                customInstructions: "Keep layout."
            ),
            configuration: LLMProviderConfiguration(apiKey: "sk-test", modelID: "gpt-5.4", baseURL: nil)
        )

        XCTAssertEqual(result.textValue, "Extracted")
    }

    func testGeminiAdapterMapsGrammarTaskToGeminiClient() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=test-key"
            )

            let body = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            let contents = try XCTUnwrap(payload["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
            XCTAssertEqual(parts.first?["text"] as? String, "bad text")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
                {"candidates":[{"content":{"parts":[{"text":"good text"}]}}]}
                """.data(using: .utf8)
            return (response, data)
        })

        let provider = GeminiLLMProvider(
            client: GeminiClient(session: URLProtocolStub.makeSession())
        )

        let result = try await provider.perform(
            task: .grammarCorrection(text: "bad text", customInstructions: "Be concise"),
            configuration: LLMProviderConfiguration(
                apiKey: "test-key",
                modelID: GeminiClient.defaultModelID,
                baseURL: nil
            )
        )

        XCTAssertEqual(result.textValue, "good text")
    }
}
