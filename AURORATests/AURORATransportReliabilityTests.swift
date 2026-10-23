import Foundation
import XCTest
@testable import AURORA

// The transport contract must tolerate intermittent reads without ever duplicating writes.
private final class AURORATransportStub: URLProtocol {
    enum Reply {
        case failure(URLError.Code)
        case json(Int, String)
    }

    private static let lock = NSLock()
    private static var replies: [Reply] = []
    private static var attempts = 0

    static func reset(_ values: [Reply]) {
        lock.lock()
        replies = values
        attempts = 0
        lock.unlock()
    }

    static var requestCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return attempts
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.lock()
        Self.attempts += 1
        let next = Self.replies.isEmpty ? Reply.failure(.unknown) : Self.replies.removeFirst()
        Self.lock.unlock()

        switch next {
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        case .json(let status, let text):
            guard let response = HTTPURLResponse(
                url: request.url!, statusCode: status,
                httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "application/json"]
            ) else {
                client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
                return
            }
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(text.utf8))
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}

final class AURORATransportReliabilityTests: XCTestCase {
    private func makeAPI() -> (AURORAAPI, URLSession) {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [AURORATransportStub.self]
        let session = URLSession(configuration: configuration)
        return (AURORAAPI(session: session), session)
    }

    func testHealthRetriesOneTransientReadFailure() async throws {
        AURORATransportStub.reset([
            .failure(.networkConnectionLost),
            .json(200, "{\"status\":\"online\"}")
        ])
        let (api, session) = makeAPI()
        defer { session.invalidateAndCancel() }

        let result = try await api.health()
        XCTAssertEqual(result.firstString(["status"]), "online")
        XCTAssertEqual(AURORATransportStub.requestCount, 2)
    }

    func testOfflineHealthFailsWithoutConnectivityWaitOrRetry() async {
        AURORATransportStub.reset([.failure(.notConnectedToInternet)])
        let (api, session) = makeAPI()
        defer { session.invalidateAndCancel() }

        do {
            _ = try await api.health()
            XCTFail("An offline error must not be interpreted as a healthy server")
        } catch {
            XCTAssertEqual(AURORATransportStub.requestCount, 1)
        }
    }

    func testExportCreationIsNeverRetriedOnAmbiguousTimeout() async {
        AURORATransportStub.reset([.failure(.timedOut)])
        let (api, session) = makeAPI()
        defer { session.invalidateAndCancel() }

        do {
            _ = try await api.queuedExport(.object([:]), format: "pdf")
            XCTFail("A failed POST must not be repeated automatically")
        } catch {
            XCTAssertEqual(AURORATransportStub.requestCount, 1)
        }
    }
}
