import Foundation
import Security

/// Bearer material is device-local and scoped to the exact HTTPS backend origin.
/// Never store it in UserDefaults, project JSON, SwiftData, logs, or artifacts.
enum AURORAAPITokenStore {
    private static let service = "com.auroraindustrial.native.api.access"

    enum StoreError: LocalizedError {
        case invalidEndpoint
        case invalidToken
        case keychain(OSStatus)

        var errorDescription: String? {
            switch self {
            case .invalidEndpoint: return "A valid HTTPS backend is required."
            case .invalidToken: return "Enter a valid issued API token (43–256 printable ASCII characters)."
            case .keychain(let status): return "Secure Keychain operation failed (\(status))."
            }
        }
    }

    static func account(for endpoint: URL) -> String? {
        // AURORAAPI builds relative API URLs; always resolve the actual origin
        // before enforcing a bearer-token destination match.
        let absolute = endpoint.absoluteURL
        guard absolute.scheme?.lowercased() == "https",
              let host = absolute.host?.lowercased(), !host.isEmpty else { return nil }
        let port = absolute.port.map { ":\($0)" } ?? ""
        return "https://\(host)\(port)"
    }

    private static func match(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    static func load(for endpoint: URL) -> String? {
        guard let account = account(for: endpoint) else { return nil }
        var query = match(account)
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8),
              AURORAAuthTransport.bearerHeader(token) != nil else { return nil }
        return token
    }

    static func save(_ token: String, for endpoint: URL) throws {
        guard let account = account(for: endpoint) else { throw StoreError.invalidEndpoint }
        guard AURORAAuthTransport.bearerHeader(token) != nil,
              let data = token.data(using: .utf8) else { throw StoreError.invalidToken }

        let existing = match(account)
        let updated = SecItemUpdate(existing as CFDictionary, [
            kSecValueData as String: data
        ] as CFDictionary)
        if updated == errSecSuccess { return }
        guard updated == errSecItemNotFound else { throw StoreError.keychain(updated) }

        var entry = existing
        entry[kSecValueData as String] = data
        entry[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let inserted = SecItemAdd(entry as CFDictionary, nil)
        guard inserted == errSecSuccess else { throw StoreError.keychain(inserted) }
    }

    static func remove(for endpoint: URL) throws {
        guard let account = account(for: endpoint) else { throw StoreError.invalidEndpoint }
        let status = SecItemDelete(match(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw StoreError.keychain(status)
        }
    }
}

/// Testable request contract. A token must not be sent to a different host or
/// downgrade to HTTP. The server only accepts a single Authorization: Bearer.
enum AURORAAuthTransport {
    static func bearerHeader(_ token: String?) -> String? {
        guard let token, (43...256).contains(token.utf8.count),
              token.unicodeScalars.allSatisfy({ (33...126).contains($0.value) }) else {
            return nil
        }
        return "Bearer \(token)"
    }

    static func attach(_ token: String?, to request: inout URLRequest, backend: URL) {
        guard let destination = request.url,
              let expected = AURORAAPITokenStore.account(for: backend),
              AURORAAPITokenStore.account(for: destination) == expected,
              let header = bearerHeader(token) else { return }
        request.setValue(header, forHTTPHeaderField: "Authorization")
    }

    static func authorize(_ request: URLRequest, backend: URL) -> URLRequest {
        var secured = request
        attach(AURORAAPITokenStore.load(for: backend), to: &secured, backend: backend)
        return secured
    }
}
