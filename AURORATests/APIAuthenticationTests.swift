import Foundation
import XCTest
@testable import AURORA

final class APIAuthenticationTests: XCTestCase {
    private let backend = URL(string: "https://todo-app-production-afcc.up.railway.app")!
    private let token = String(repeating: "A", count: 64)

    func testDeviceCredentialIsScopedToExactHTTPSOrigin() {
        XCTAssertEqual(AURORAAPITokenStore.account(for: backend),
                       "https://todo-app-production-afcc.up.railway.app")
        XCTAssertNil(AURORAAPITokenStore.account(for:
            URL(string: "http://todo-app-production-afcc.up.railway.app")!))
        XCTAssertEqual(AURORAAPITokenStore.account(for:
            URL(string: "https://todo-app-production-afcc.up.railway.app:8443")!),
                       "https://todo-app-production-afcc.up.railway.app:8443")
    }

    func testValidBearerOnlyAddedToTrustedAPIRoute() {
        var request = URLRequest(url: URL(string: "/api/jobs/recent", relativeTo: backend)!)
        AURORAAuthTransport.attach(token, to: &request, backend: backend)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(token)")
        XCTAssertNil(request.url?.query)
    }

    func testNoCredentialOnUnrelatedOriginOrDowngradedHTTP() {
        for url in [
            URL(string: "https://untrusted.example.net/api/jobs")!,
            URL(string: "http://todo-app-production-afcc.up.railway.app/api/jobs")!,
            URL(string: "https://todo-app-production-afcc.up.railway.app:8443/api/jobs")!
        ] {
            var request = URLRequest(url: url)
            AURORAAuthTransport.attach(token, to: &request, backend: backend)
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"),
                         "Auth token must not be sent to a different origin")
        }
    }

    func testRejectHeaderInjectionWhitespaceAndShortCredentials() {
        for invalid in ["", "short", "Bearer foo", "this is not a valid token",
                        token + "\r\nX-Injected: true", token + " ",
                        String(repeating: "A", count: 300)] {
            XCTAssertNil(AURORAAuthTransport.bearerHeader(invalid))
        }
        XCTAssertEqual(AURORAAuthTransport.bearerHeader(token), "Bearer \(token)")
        XCTAssertNil(AURORAAuthTransport.bearerHeader(nil))
    }

    func testNoAuthorizationIsSynthesizedWhenNoTokenIsProvided() {
        var request = URLRequest(url: URL(string: "/api/validate", relativeTo: backend)!)
        AURORAAuthTransport.attach(nil, to: &request, backend: backend)
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
    }
}
