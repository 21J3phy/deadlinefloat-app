import CryptoKit
import Foundation

/// Proof Key for Code Exchange (RFC 7636), method `S256`.
///
/// A public desktop client cannot keep a secret, so the authorisation code is
/// bound to a one-time verifier that never leaves this process.
struct PKCE: Sendable, Equatable {
    let verifier: String
    let challenge: String
    let method = "S256"

    init(verifier: String) {
        self.verifier = verifier
        self.challenge = Self.challenge(for: verifier)
    }

    static func generate() -> PKCE {
        PKCE(verifier: base64URL(randomBytes(64)))
    }

    static func challenge(for verifier: String) -> String {
        let digest = SHA256.hash(data: Data(verifier.utf8))
        return base64URL(Data(digest))
    }

    /// Cryptographically random bytes; falls back to `SystemRandomNumberGenerator`
    /// only if the security framework refuses, which it does not in practice.
    static func randomBytes(_ count: Int) -> Data {
        var bytes = [UInt8](repeating: 0, count: count)
        if SecRandomCopyBytes(kSecRandomDefault, count, &bytes) != errSecSuccess {
            var generator = SystemRandomNumberGenerator()
            bytes = (0..<count).map { _ in UInt8.random(in: 0...255, using: &generator) }
        }
        return Data(bytes)
    }

    /// Unpadded base64url, as required for both the verifier and the challenge.
    static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// Opaque value echoed back by Google to defeat cross-site request forgery.
    static func stateToken() -> String { base64URL(randomBytes(24)) }
}
