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

    func testPerformRoutesGrammarRequestsToOpenAI() async throws {
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
            LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "bad text", customInstructions: ""))
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
                providerID: .gemini,
                task: .screenOCR(imageData: Data("image".utf8), mimeType: "image/png", customInstructions: "")
            )
        )

        XCTAssertEqual(response.textValue, "Extracted")
    }

    func testPerformFailsWhenProviderIsNotConfigured() async {
        let router = makeRouter(configured: [])

        do {
            _ = try await router.perform(
                LLMRequest(providerID: .openAI, task: .grammarCorrection(text: "text", customInstructions: ""))
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

    func testPerformUsesModelOverrideWhenPresent() async throws {
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
                providerID: .openAI,
                task: .grammarCorrection(text: "bad text", customInstructions: ""),
                modelIDOverride: "voice-model-openai"
            )
        )

        XCTAssertEqual(response.textValue, "good text")
    }

    func testPerformVoiceTaskFailsUntilProviderImplementationsExist() async {
        let router = makeRouter(configured: [.gemini])

        do {
            _ = try await router.perform(
                LLMRequest(
                    providerID: .gemini,
                    task: .voiceTranscription(
                        audioData: Data("audio".utf8),
                        mimeType: "audio/wav",
                        customInstructions: ""
                    ),
                    modelIDOverride: "voice-model-gemini"
                )
            )
            XCTFail("Expected unsupported voice task error")
        } catch {
            guard case let LLMRouterError.unsupportedTask(taskName) = error else {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(taskName, "Voice dictation")
        }
    }

    func testCheckAccessReturnsRequestedProviderHealth() async throws {
        URLProtocolStub.configure(handler: { request in
            XCTAssertEqual(request.httpMethod, "GET")
            XCTAssertEqual(request.url?.absoluteString, "https://api.openai.com/v1/models/model-openAI")

            let response = HTTPURLResponse(url: try XCTUnwrap(request.url), statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, nil)
        })

        let router = makeRouter(configured: [.openAI], openAISession: URLProtocolStub.makeSession())
        let health = try await router.checkAccess(for: .openAI)

        XCTAssertEqual(health.providerID, .openAI)
        XCTAssertEqual(health.state, .available)
        XCTAssertTrue(health.hasAccess)
    }

    func testCheckAccessReturnsNotConfiguredDiagnostic() async throws {
        let router = makeRouter(configured: [])

        let health = try await router.checkAccess(for: .openAI)

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
            openAIClient: OpenAIClient(session: openAISession),
            geminiClient: GeminiClient(session: geminiSession)
        )
    }

    private func makeSettings(configured: Set<LLMProviderID>) -> LLMSettings {
        var settings = LLMSettings.empty()

        for providerID in configured {
            settings.providerProfiles[providerID] = LLMProviderProfile(
                apiKey: "key-\(providerID.rawValue)",
                modelID: "model-\(providerID.rawValue)"
            )
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
