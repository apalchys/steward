import Foundation
import XCTest
@testable import Steward
@testable import StewardCore

final class LLMProviderAdapterTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testOpenAIAdapterMapsGrammarTaskToOpenAIClient() {
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
            client: OpenAIClient(session: URLProtocolStub.makeSession(), callbackQueue: .main)
        )

        let result: Result<LLMResult, Error> = waitForValue { completion in
            provider.perform(
                task: .grammarCorrection(text: "bad text", customRules: ""),
                configuration: LLMProviderConfiguration(apiKey: "sk-test", modelID: "gpt-5.4", baseURL: nil),
                completion: completion
            )
        }

        switch result {
        case .success(let llmResult):
            XCTAssertEqual(llmResult.textValue, "good text")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testGeminiAdapterMapsOCRTaskToGeminiClient() {
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
            client: GeminiClient(session: URLProtocolStub.makeSession(), callbackQueue: .main)
        )

        let result: Result<LLMResult, Error> = waitForValue { completion in
            provider.perform(
                task: .screenOCR(imageData: Data("image".utf8), mimeType: "image/png"),
                configuration: LLMProviderConfiguration(
                    apiKey: "test-key",
                    modelID: GeminiClient.defaultModelID,
                    baseURL: nil
                ),
                completion: completion
            )
        }

        switch result {
        case .success(let llmResult):
            XCTAssertEqual(llmResult.textValue, "Extracted")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }

    func testOpenAICompatibleAdapterUsesConfiguredBaseURL() {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://compatible.example/v1/responses")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer comp-key")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
                {"output":[{"type":"message","content":[{"type":"output_text","text":"compat ok"}]}]}
                """.data(using: .utf8)
            return (response, data)
        })

        let provider = OpenAICompatibleLLMProvider(
            session: URLProtocolStub.makeSession(),
            callbackQueue: .main
        )

        let result: Result<LLMResult, Error> = waitForValue { completion in
            provider.perform(
                task: .grammarCorrection(text: "text", customRules: ""),
                configuration: LLMProviderConfiguration(
                    apiKey: "comp-key",
                    modelID: "gpt-compatible",
                    baseURL: "https://compatible.example"
                ),
                completion: completion
            )
        }

        switch result {
        case .success(let llmResult):
            XCTAssertEqual(llmResult.textValue, "compat ok")
        case .failure(let error):
            XCTFail("Expected success, got \(error)")
        }
    }
}
