import Foundation
import XCTest
@testable import StewardCore

final class GeminiClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testCheckAccessReturnsTrueOnHTTP200() async {
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
        let hasAccess = await client.checkAccess(apiKey: "test-key", modelID: "gemini-3.1-flash-lite-preview")

        XCTAssertTrue(hasAccess)
    }

    func testCheckAccessStatusReturnsInvalidCredentials() async {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        let result = await client.checkAccessStatus(apiKey: "test-key", modelID: "gemini-3.1-flash-lite-preview")

        XCTAssertEqual(result.status, .invalidCredentials)
    }

    func testExtractMarkdownTextSuccessParsesAndTrimsOutput() async throws {
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
        let text = try await client.extractMarkdownText(
            apiKey: "test-key",
            modelID: "gemini-3.1-flash-lite-preview",
            imageData: imageData,
            mimeType: "image/png"
        )

        XCTAssertEqual(text, "Heading\nBody text")
    }

    func testExtractMarkdownTextReturnsNormalizedErrorMessageForRateLimit() async {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"error":{"message":"Quota exceeded."}}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 429, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("Gemini is rate limiting requests.") {
            try await client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png"
            )
        }
    }

    func testExtractMarkdownTextReturnsProviderMessageForBadRequest() async {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"error":{"message":"Malformed inline_data payload."}}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("Malformed inline_data payload.") {
            try await client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png"
            )
        }
    }

    func testExtractMarkdownTextReturnsServiceMessageForTemporaryFailure() async {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("Gemini is temporarily unavailable.") {
            try await client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png"
            )
        }
    }

    func testExtractMarkdownTextReturnsEmptyResponseErrorWhenDataIsMissing() async {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("Gemini returned an empty response.") {
            try await client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png"
            )
        }
    }

    func testExtractMarkdownTextReturnsEmptyOutputErrorWhenTextIsBlank() async {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"candidates":[{"content":{"parts":[{"text":"   "} ]}}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("Gemini returned no extracted text.") {
            try await client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png"
            )
        }
    }

    func testExtractMarkdownTextPropagatesTransportError() async {
        URLProtocolStub.configure(stubError: URLError(.notConnectedToInternet))

        let client = makeClient()
        do {
            _ = try await client.extractMarkdownText(
                apiKey: "test-key",
                modelID: "gemini-3.1-flash-lite-preview",
                imageData: Data("image".utf8),
                mimeType: "image/png"
            )
            XCTFail("Expected failure but got success")
        } catch {
            let urlError = error as? URLError
            XCTAssertEqual(urlError?.code, .notConnectedToInternet)
        }
    }

    func testCorrectGrammarSuccessParsesOutput() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://generativelanguage.googleapis.com/v1beta/models/gemini-3.1-flash-lite-preview:generateContent?key=test-key"
            )

            let requestBody = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: requestBody) as? [String: Any])
            let contents = try XCTUnwrap(payload["contents"] as? [[String: Any]])
            let parts = try XCTUnwrap(contents.first?["parts"] as? [[String: Any]])
            XCTAssertEqual(parts.first?["text"] as? String, "bad text")

            let data = """
                {"candidates":[{"content":{"parts":[{"text":"good text"}]}}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        let text = try await client.correctGrammar(
            apiKey: "test-key",
            modelID: "gemini-3.1-flash-lite-preview",
            customInstructions: "Keep concise",
            text: "bad text"
        )

        XCTAssertEqual(text, "good text")
    }

    private func makeClient() -> GeminiClient {
        GeminiClient(session: URLProtocolStub.makeSession())
    }

    private func assertThrowsErrorMessage(
        _ expectedMessage: String,
        file: StaticString = #filePath,
        line: UInt = #line,
        _ operation: () async throws -> some Any
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected failure but got success", file: file, line: line)
        } catch {
            XCTAssertEqual(error.localizedDescription, expectedMessage, file: file, line: line)
        }
    }
}
