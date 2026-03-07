import Foundation
import XCTest
@testable import StewardCore

final class GeminiClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testCheckAccessReturnsTrueOnHTTP200() {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview?key=test-key"
            )

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        let hasAccess: Bool = waitForValue { completion in
            client.checkAccess(apiKey: "test-key", modelID: "gemini-3.1-flash-lite-preview", completion: completion)
        }

        XCTAssertTrue(hasAccess)
    }

    func testCheckAccessReturnsFalseForInvalidBaseURL() {
        let client = makeClient(baseURL: "://invalid-url")
        let hasAccess: Bool = waitForValue { completion in
            client.checkAccess(apiKey: "test-key", modelID: "gemini-3.1-flash-lite-preview", completion: completion)
        }

        XCTAssertFalse(hasAccess)
    }

    func testExtractMarkdownTextSuccessParsesAndTrimsOutput() {
        let imageData = Data("image-bytes".utf8)

        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=test-key"
            )
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")

            let requestBody = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])

            let systemInstruction = try XCTUnwrap(payload["system_instruction"] as? [String: Any])
            let systemParts = try XCTUnwrap(systemInstruction["parts"] as? [[String: Any]])
            XCTAssertEqual(systemParts.first?["text"] as? String, """
                You are an OCR assistant. Extract all visible text from the provided image and return only the extracted text in Markdown.
                Preserve headings, paragraphs, lists, tables, and code blocks when they are visually clear.
                Do not add explanations, summaries, or commentary.
                """)

            let contents = try XCTUnwrap(payload["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
            XCTAssertEqual(
                parts.first?["text"] as? String,
                "Extract all visible text from this screenshot selection and return Markdown only."
            )

            let inlineData = try XCTUnwrap(parts.last?["inline_data"] as? [String: Any])
            XCTAssertEqual(inlineData["mime_type"] as? String, "image/png")
            XCTAssertEqual(inlineData["data"] as? String, imageData.base64EncodedString())

            let data = """
                {"candidates":[{"content":{"parts":[{"text":" Heading"},{"text":"Body text "}]}}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: imageData,
                mimeType: "image/png",
                completion: completion
            )
        }

        switch result {
        case .success(let text):
            XCTAssertEqual(text, "Heading\nBody text")
        case .failure(let error):
            XCTFail("Expected success but got error: \(error)")
        }
    }

    func testExtractMarkdownTextReturnsAPIErrorMessageForNon2xx() {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"error":{"message":"Quota exceeded."}}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "Quota exceeded.")
    }

    func testExtractMarkdownTextReturnsFallbackErrorMessageForNon2xxWithoutBody() {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "Gemini request failed with HTTP 500.")
    }

    func testExtractMarkdownTextReturnsEmptyResponseErrorWhenDataIsMissing() {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "Gemini returned an empty response.")
    }

    func testExtractMarkdownTextReturnsEmptyOutputErrorWhenTextIsBlank() {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"candidates":[{"content":{"parts":[{"text":"   "} ]}}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "Gemini returned no extracted text.")
    }

    func testExtractMarkdownTextPropagatesTransportError() {
        URLProtocolStub.configure(stubError: URLError(.notConnectedToInternet))

        let client = makeClient()
        let result: Result<String, Error> = waitForValue { completion in
            client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png",
                completion: completion
            )
        }

        switch result {
        case .success(let text):
            XCTFail("Expected failure but got success: \(text)")
        case .failure(let error):
            let urlError = error as? URLError
            XCTAssertEqual(urlError?.code, .notConnectedToInternet)
        }
    }

    func testExtractMarkdownTextReturnsInvalidURLErrorWhenBaseURLIsInvalid() {
        let client = makeClient(baseURL: "://invalid-url")
        let result: Result<String, Error> = waitForValue { completion in
            client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png",
                completion: completion
            )
        }

        assertFailureMessage(result, equals: "Gemini request URL is invalid.")
    }

    private func makeClient(baseURL: String = "https://generativelanguage.googleapis.com") -> GeminiClient {
        GeminiClient(session: URLProtocolStub.makeSession(), callbackQueue: .main, apiBaseURL: baseURL)
    }

    private func assertFailureMessage(
        _ result: Result<String, Error>,
        equals expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        switch result {
        case .success(let text):
            XCTFail("Expected failure but got success: \(text)", file: file, line: line)
        case .failure(let error):
            XCTAssertEqual(error.localizedDescription, expectedMessage, file: file, line: line)
        }
    }
}
