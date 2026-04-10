import Foundation
import XCTest
@testable import StewardCore

final class OpenAIClientTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testCheckAccessStatusReturnsAvailableOnHTTP200() async {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models/gpt-5.4")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        let result = await client.checkAccessStatus(apiKey: "sk-test", modelID: "gpt-5.4")

        XCTAssertEqual(result.status, .available)
        XCTAssertTrue(result.hasAccess)
    }

    func testCheckAccessStatusReturnsInvalidCredentials() async {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        let result = await client.checkAccessStatus(apiKey: "sk-test", modelID: "gpt-5.4")

        XCTAssertEqual(result.status, .invalidCredentials)
    }

    func testCorrectGrammarSuccessReturnsCorrectedTextAndSendsReasoningForGPT5() async throws {
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
        let correctedText = try await client.correctGrammar(
            apiKey: "sk-test",
            modelID: "gpt-5.4",
            customInstructions: "Use concise language.",
            text: "This are bad grammar."
        )

        XCTAssertEqual(correctedText, "This is bad grammar.")
    }

    func testCorrectGrammarOmitsReasoningForNonGPT5Model() async throws {
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
        let correctedText = try await client.correctGrammar(
            apiKey: "sk-test",
            modelID: "gpt-4.1-mini",
            customInstructions: "",
            text: "bad text"
        )

        XCTAssertEqual(correctedText, "ok")
    }

    func testCorrectGrammarReturnsNormalizedErrorMessageForInvalidCredentials() async {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"error":{"message":"Invalid API key."}}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 401, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("OpenAI API key is invalid.") {
            try await client.correctGrammar(
                apiKey: "bad-key",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text"
            )
        }
    }

    func testCorrectGrammarReturnsProviderMessageForBadRequest() async {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"error":{"message":"Unsupported response format."}}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("Unsupported response format.") {
            try await client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text"
            )
        }
    }

    func testCorrectGrammarReturnsServiceMessageForTemporaryFailure() async {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("OpenAI is temporarily unavailable.") {
            try await client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text"
            )
        }
    }

    func testCorrectGrammarReturnsEmptyResponseErrorWhenDataIsMissing() async {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("OpenAI returned an empty response.") {
            try await client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text"
            )
        }
    }

    func testCorrectGrammarReturnsEmptyOutputErrorWhenNoOutputTextPresent() async {
        URLProtocolStub.configure(handler: { request in
            let data = """
                {"output":[{"type":"message","content":[{"type":"input_text","text":"ignored"}]}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let client = makeClient()
        await assertThrowsErrorMessage("OpenAI returned no corrected text.") {
            try await client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text"
            )
        }
    }

    func testCorrectGrammarPropagatesTransportError() async {
        URLProtocolStub.configure(stubError: URLError(.timedOut))

        let client = makeClient()
        do {
            _ = try await client.correctGrammar(
                apiKey: "sk-test",
                modelID: "gpt-5.4",
                customInstructions: "",
                text: "text"
            )
            XCTFail("Expected failure but got success")
        } catch {
            let urlError = error as? URLError
            XCTAssertEqual(urlError?.code, .timedOut)
        }
    }

    func testExtractMarkdownTextSuccessReturnsExtractedTextAndSendsImageInput() async throws {
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
        let extractedText = try await client.extractMarkdownText(
            apiKey: "sk-test",
            modelID: "gpt-5.4",
            imageData: imageData,
            mimeType: "image/png",
            customInstructions: ""
        )

        XCTAssertEqual(extractedText, "Extracted text")
    }

    func testTranscribeAudioSuccessReturnsTranscriptAndUploadsMultipartAudio() async throws {
        let audioData = Data("audio-bytes".utf8)

        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer sk-test")
            XCTAssertTrue((request.value(forHTTPHeaderField: "Content-Type") ?? "").contains("multipart/form-data"))

            let body = String(data: try XCTUnwrap(request.bodyData()), encoding: .utf8) ?? ""
            XCTAssertTrue(body.contains("name=\"model\""))
            XCTAssertTrue(body.contains("gpt-4o-mini-transcribe"))
            XCTAssertTrue(body.contains("name=\"prompt\""))
            XCTAssertTrue(body.contains("do not translate"))
            XCTAssertTrue(body.contains("name=\"response_format\""))
            XCTAssertTrue(body.contains("text"))
            XCTAssertTrue(body.contains("name=\"file\"; filename=\"dictation.wav\""))
            XCTAssertTrue(body.contains("Content-Type: audio/wav"))
            XCTAssertTrue(body.contains("audio-bytes"))

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("Hello from OpenAI.".utf8))
        })

        let client = makeClient()
        let transcript = try await client.transcribeAudio(
            apiKey: "sk-test",
            modelID: "gpt-4o-mini-transcribe",
            audioData: audioData,
            mimeType: "audio/wav",
            customInstructions: ""
        )

        XCTAssertEqual(transcript, "Hello from OpenAI.")
    }

    func testTranscribeAudioReturnsEmptyTranscriptErrorWhenBodyIsBlank() async {
        URLProtocolStub.configure(handler: { request in
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("   ".utf8))
        })

        let client = makeClient()
        await assertThrowsErrorMessage("OpenAI returned no transcript.") {
            try await client.transcribeAudio(
                apiKey: "sk-test",
                modelID: "gpt-4o-mini-transcribe",
                audioData: Data("audio".utf8),
                mimeType: "audio/wav",
                customInstructions: ""
            )
        }
    }

    private func makeClient() -> OpenAIClient {
        OpenAIClient(session: URLProtocolStub.makeSession())
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
