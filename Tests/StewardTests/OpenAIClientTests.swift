import Foundation
import XCTest
@testable import StewardCore

final class OpenAIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testCheckAccessReturnsTrueOnHTTP200() {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models/gpt-5.4")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        let hasAccess: Bool = waitForValue { completion in
            client.checkAccess(apiKey: "sk-test", modelID: "gpt-5.4", completion: completion)
        }

        XCTAssertTrue(hasAccess)
    }

    func testCheckAccessReturnsFalseForInvalidBaseURL() {
        let client = makeClient(baseURL: "://invalid-url")
        let hasAccess: Bool = waitForValue { completion in
            client.checkAccess(apiKey: "sk-test", modelID: "gpt-5.4", completion: completion)
        }

        XCTAssertFalse(hasAccess)
    }

    func testCorrectGrammarSuccessReturnsCorrectedTextAndSendsReasoningForGPT5() {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let requestBody = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
            XCTAssertEqual(payload["model"] as? String, "gpt-5.4")
            XCTAssertEqual(payload["input"] as? String, "This are bad grammar.")
            XCTAssertTrue((payload["instructions"] as? String)?.contains("Additional instructions to follow:") ?? false)

            let reasoning = try XCTUnwrap(payload["reasoning"] as? [String: Any])
            XCTAssertEqual(reasoning["effort"] as? String, "none")

            let data = """
                {"output":[{"type":"message","content":[{"type":"output_text","text":"This is bad grammar."}]}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "Use concise language.",
                text: "This are bad grammar.",
                completion: completion
            )
        }

        switch result {
        case .success(let correctedText):
            XCTAssertEqual(correctedText, "This is bad grammar.")
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }

    func testCorrectGrammarOmitsReasoningForNonGPT5Model() {
        URLProtocolStub.configure(handler: { request in
            let requestBody = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
            XCTAssertNil(payload["reasoning"])

            let data = """
                {"output":[{"type":"message","content":[{"type":"output_text","text":"ok"}]}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-4.1-mini",
                customInstructions: "",
                text: "bad text",
                completion: completion
            )
        }

        switch result {
        case .success(let correctedText):
            XCTAssertEqual(correctedText, "ok")
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }

    func testCorrectGrammarReturnsAPIErrorMessageForNon2xx() {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"error":{"message":"Invalid API key."}}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.correctGrammar(
                apiKey: "bad-key",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "Invalid API key.")
    }

    func testCorrectGrammarReturnsFallbackErrorMessageForNon2xxWithoutBody() {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "OpenAI request failed with HTTP 503.")
    }

    func testCorrectGrammarReturnsEmptyResponseErrorWhenDataIsMissing() {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "OpenAI returned an empty response.")
    }

    func testCorrectGrammarReturnsEmptyOutputErrorWhenNoOutputTextPresent() {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"output":[{"type":"message","content":[{"type":"input_text","text":"ignored"}]}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "OpenAI returned no corrected text.")
    }

    func testCorrectGrammarPropagatesTransportError() {
        URLProtocolStub.configure(stubError: URLError(.timedOut))

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text",
                completion: completion
            )
        }

        switch result {
        case .success(let correctedText):
            XCTFail("Expected failure but got success: \(correctedText)")
        case .failure(let error):
            let urlError = error as? URLError
            XCTAssertEqual(urlError?.code, .timedOut)
        }
    }

    func testCorrectGrammarReturnsInvalidURLErrorWhenBaseURLIsInvalid() {
        let client = makeClient(baseURL: "://invalid-url")
        let result: Result<String, Error> = waitForValue { completion in
            client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "OpenAI request URL is invalid.")
    }

    func testExtractMarkdownTextSuccessReturnsExtractedTextAndSendsImageInput() {
        let imageData = Data("image-bytes".utf8)

        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")

            let requestBody = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
            XCTAssertEqual(payload["model"] as? String, "gpt-5.4")

            let input = try XCTUnwrap(payload["input"] as? [[String: Any]])
            let content = try XCTUnwrap(input.first?["content"] as? [[String: Any]])
            XCTAssertEqual(content.first?["type"] as? String, "input_text")
            XCTAssertEqual(content.last?["type"] as? String, "input_image")

            let imageURL = try XCTUnwrap(content.last?["image_url"] as? String)
            XCTAssertTrue(imageURL.hasPrefix("data:image/png;base64,"))
            XCTAssertTrue(imageURL.hasSuffix(imageData.base64EncodedString()))

            let data = """
                {"output":[{"type":"message","content":[{"type":"output_text","text":"Extracted text"}]}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.extractMarkdownText(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                imageData: imageData,
                mimeType: "image/png",
                customInstructions: "",
                completion: completion
            )
        }

        switch result {
        case .success(let extractedText):
            XCTAssertEqual(extractedText, "Extracted text")
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }

    func testExtractMarkdownTextReturnsInvalidURLErrorWhenBaseURLIsInvalid() {
        let client = makeClient(baseURL: "://invalid-url")
        let result: Result<String, Error> = waitForValue { completion in
            client.extractMarkdownText(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                imageData: Data("image".utf8),
                mimeType: "image/png",
                customInstructions: "",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "OpenAI request URL is invalid.")
    }

    private func makeClient(baseURL: String = "https://api.openai.com") -> OpenAIClient {
        OpenAIClient(session: URLProtocolStub.makeSession(), callbackQueue: .main, apiBaseURL: baseURL)
    }

    private func assertFailureMessage(
        _ result: Result<String, Error>,
        equals expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success(let correctedText):
            XCTFail("Expected failure but got success: \(correctedText)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, expectedMessage, file: file, line: line)
        }
    }
}
