import Foundation
import Security

/// Persistence for OAuth tokens.
protocol TokenStoring: Sendable {
    func load() throws -> OAuthTokens?
    func save(_ tokens: OAuthTokens) throws
    func clear() throws
}

enum KeychainError: LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus(let status):
            let message = SecCopyErrorMessageString(status, nil) as String? ?? "Keychain error \(status)"
            return message
        }
    }
}

/// Stores the token set as a single generic-password item in the login keychain.
///
/// Nothing else about the account is kept: no email address, no calendar data.
struct KeychainTokenStore: TokenStoring {
    let service: String
    let account: String

    init(service: String = AppInfo.bundleIdentifier, account: String = "google-oauth") {
        self.service = service
        self.account = account
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }

    func load() throws -> OAuthTokens? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
        guard let data = item as? Data else { return nil }
        return try JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    func save(_ tokens: OAuthTokens) throws {
        let data = try JSONEncoder().encode(tokens)

        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]

        let status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return }
        if status == errSecItemNotFound {
            var insert = baseQuery
            insert.merge(attributes) { _, new in new }
            insert[kSecAttrDescription as String] = "DeadlineFloat Google Calendar tokens"
            let addStatus = SecItemAdd(insert as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError.unexpectedStatus(addStatus) }
            return
        }
        throw KeychainError.unexpectedStatus(status)
    }

    func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}

/// In-memory store used by the unit tests and by `--demo`, so neither touches the
/// real keychain.
final class InMemoryTokenStore: TokenStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var tokens: OAuthTokens?

    init(tokens: OAuthTokens? = nil) { self.tokens = tokens }

    func load() throws -> OAuthTokens? {
        lock.lock(); defer { lock.unlock() }
        return tokens
    }

    func save(_ tokens: OAuthTokens) throws {
        lock.lock(); defer { lock.unlock() }
        self.tokens = tokens
    }

    func clear() throws {
        lock.lock(); defer { lock.unlock() }
        tokens = nil
    }
}
