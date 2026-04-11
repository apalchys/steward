import Foundation
import XCTest
@testable import Steward
@testable import StewardCore

@MainActor
final class LLMRouterTests: XCTestCase {
    override func tearDown() {
        URLProtocolStub.reset()
        super.tearDown()
    }

    func testPerformRoutesRefineRequestsToOpenAI() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/responses")

            let body = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["model"] as? String, "model-openAI")
            XCTAssertEqual(payload["input"] as? String, "bad text")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
                {"output":[{"type":"message","content":[{"type":"output_text","text":"good text"}]}]}
                """.data(using: .utf8)
            return (response, data)
        })

        let router = makeRouter(configured: [.openAI], openAISession: URLProtocolStub.makeSession())

        let response = try await router.perform(
            LLMRequest(
                selection: LLMModelSelection(providerID: .openAI, modelID: "model-openAI"),
                task: .refineText(text: "bad text", customInstructions: "")
            )
        )

        XCTAssertEqual(response.textValue, "good text")
    }

    func testPerformRoutesOCRRequestsToGemini() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://generativelanguage.googleapis.com/v1beta/models/model-gemini:generateContent?key=key-gemini"
            )

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
                {"candidates":[{"content":{"parts":[{"text":"Extracted"}]}}]}
                """.data(using: .utf8)
            return (response, data)
        })

        let router = makeRouter(configured: [.gemini], geminiSession: URLProtocolStub.makeSession())

        let response = try await router.perform(
            LLMRequest(
                selection: LLMModelSelection(providerID: .gemini, modelID: "model-gemini"),
                task: .screenOCR(imageData: Data("image".utf8), mimeType: "image/png", customInstructions: "")
            )
        )

        XCTAssertEqual(response.textValue, "Extracted")
    }

    func testPerformFailsWhenProviderIsNotConfigured() async {
        let router = makeRouter(configured: [])

        do {
            _ = try await router.perform(
                LLMRequest(
                    selection: LLMModelSelection(providerID: .openAI, modelID: "model-openAI"),
                    task: .refineText(text: "text", customInstructions: "")
                )
            )
            XCTFail("Expected configuration error")
        } catch {
            guard case let LLMRouterError.providerNotConfigured(providerID) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(providerID, .openAI)
        }
    }

    func testPerformUsesSelectedModelWhenPresent() async throws {
        URLProtocolStub.configure(handler: { request in
            let body = try XCTUnwrap(request.bodyData())
            let payload = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
            XCTAssertEqual(payload["model"] as? String, "voice-model-openai")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            let data = """
                {"output":[{"type":"message","content":[{"type":"output_text","text":"good text"}]}]}
                """.data(using: .utf8)
            return (response, data)
        })

        let router = makeRouter(configured: [.openAI], openAISession: URLProtocolStub.makeSession())

        let response = try await router.perform(
            LLMRequest(
                selection: LLMModelSelection(providerID: .openAI, modelID: "voice-model-openai"),
                task: .refineText(text: "bad text", customInstructions: "")
            )
        )

        XCTAssertEqual(response.textValue, "good text")
    }

    func testPerformRoutesVoiceRequestsToGemini() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(
                request.url?.absoluteString,
                "https://generativelanguage.googleapis.com/v1beta/models/voice-model-gemini:generateContent?key=key-gemini"
            )

            let data = """
                {"candidates":[{"content":{"parts":[{"text":"Dictated text"}]}}]}
                """.data(using: .utf8)
            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, data)
        })

        let router = makeRouter(configured: [.gemini], geminiSession: URLProtocolStub.makeSession())
        let response = try await router.perform(
            LLMRequest(
                selection: LLMModelSelection(providerID: .gemini, modelID: "voice-model-gemini"),
                task: .voiceTranscription(
                    audioData: Data("audio".utf8),
                    mimeType: "audio/wav",
                    options: VoiceTranscriptionOptions()
                )
            )
        )

        XCTAssertEqual(response.textValue, "Dictated text")
    }

    func testPerformRoutesVoiceRequestsToOpenAI() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/audio/transcriptions")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("OpenAI dictated text".utf8))
        })

        let router = makeRouter(configured: [.openAI], openAISession: URLProtocolStub.makeSession())
        let response = try await router.perform(
            LLMRequest(
                selection: LLMModelSelection(providerID: .openAI, modelID: "voice-model-openai"),
                task: .voiceTranscription(
                    audioData: Data("audio".utf8),
                    mimeType: "audio/wav",
                    options: VoiceTranscriptionOptions()
                )
            )
        )

        XCTAssertEqual(response.textValue, "OpenAI dictated text")
    }

    func testCheckAccessReturnsRequestedProviderHealth() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models/model-openAI")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let router = makeRouter(configured: [.openAI], openAISession: URLProtocolStub.makeSession())
        let health = try await router.checkAccess(for: LLMModelSelection(providerID: .openAI, modelID: "model-openAI"))

        XCTAssertEqual(health.providerID, .openAI)
        XCTAssertEqual(health.state, .available)
        XCTAssertTrue(health.hasAccess)
    }

    func testCheckAccessReturnsNotConfiguredDiagnostic() async throws {
        let router = makeRouter(configured: [])

        let health = try await router.checkAccess(for: LLMModelSelection(providerID: .openAI, modelID: "model-openAI"))

        XCTAssertEqual(health.providerID, .openAI)
        XCTAssertEqual(health.state, .notConfigured)
    }

    private func makeRouter(
        configured: Set<LLMProviderID>,
        openAISession: URLSession = .shared,
        geminiSession: URLSession = .shared
    ) -> LLMRouter {
        LLMRouter(
            settingsStore: FakeSettingsStore(settings: makeSettings(configured: configured)),
            openAIClient: OpenAIClient(
                defaultModelID: LLMModelCatalog.defaultModelID(for: .openAI),
                session: openAISession
            ),
            geminiClient: GeminiClient(
                defaultModelID: LLMModelCatalog.defaultModelID(for: .gemini),
                session: geminiSession
            )
        )
    }

    private func makeSettings(configured: Set<LLMProviderID>) -> LLMSettings {
        var settings = LLMSettings.empty()

        for providerID in configured {
            settings.providerSettings[providerID] = LLMProviderSettings(apiKey: "key-\(providerID.rawValue)")
        }

        return settings
    }
}

private final class FakeSettingsStore: AppSettingsProviding {
    var settings: LLMSettings

    init(settings: LLMSettings) {
        self.settings = settings
    }

    func loadSettings() -> LLMSettings { settings }

    func saveSettings(_ settings: LLMSettings) {
        self.settings = settings
    }
}
