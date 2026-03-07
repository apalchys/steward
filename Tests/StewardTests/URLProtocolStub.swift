import Foundation

final class URLProtocolStub: URLProtocol {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data?)
    typealias Observer = @Sendable (URLRequest) -> Void

    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler?
    nonisolated(unsafe) private static var observer: Observer?
    nonisolated(unsafe) private static var stubError: Error?

    static func configure(
        handler: Handler? = nil,
        observer: Observer? = nil,
        stubError: Error? = nil
    ) {
        lock.lock()
        self.handler = handler
        self.observer = observer
        self.stubError = stubError
        lock.unlock()
    }

    static func reset() {
        configure()
    }

    static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [URLProtocolStub.self]
        return URLSession(configuration: configuration)
    }

    override class func canInit(with request: URLRequest) -> Bool {
        true
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        URLProtocolStub.lock.lock()
        let handler = URLProtocolStub.handler
        let observer = URLProtocolStub.observer
        let stubError = URLProtocolStub.stubError
        URLProtocolStub.lock.unlock()

        observer?(request)

        if let stubError {
            client?.urlProtocol(self, didFailWithError: stubError)
            return
        }

        guard let handler else {
            let missingHandlerError = NSError(
                domain: "URLProtocolStub",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "URLProtocolStub handler is not configured."]
            )
            client?.urlProtocol(self, didFailWithError: missingHandlerError)
            return
        }

        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)

            if let data {
                client?.urlProtocol(self, didLoad: data)
            }

            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
