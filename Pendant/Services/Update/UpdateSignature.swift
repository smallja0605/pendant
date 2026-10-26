import CryptoKit
import Foundation

/// The signature of an update package (Ed25519, made with the developer's private key by `scripts/update-signing.swift`; the key
/// never leaves the developer's Keychain). The package's SHA-256 file comes from the same release as the package, so it only guards
/// against a damaged download: this signature is what tells the app that the package really is the developer's.
enum UpdateSignature {
    /// The developer's public key (base64, 32 bytes). Whoever does not have the private key cannot make a signature that this accepts.
    static let publicKeyBase64 = "Uh2sSj2w1IeInPQSXMM7J6kK3qA1vaOhF0dxVpJGJKI="

    /// What is signed: a label, the version (an old signed package cannot pass as a new release) and the package's digest.
    static func message(version: String, sha256: String) -> Data {
        Data("pendant-update-v1\n\(version)\n\(sha256.lowercased())".utf8)
    }

    static func verify(
        signatureBase64: String, version: String, sha256: String, publicKeyBase64: String = Self.publicKeyBase64
    ) -> Bool {
        let cleaned = signatureBase64.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let signature = Data(base64Encoded: cleaned), let raw = Data(base64Encoded: publicKeyBase64),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw) else { return false }
        return key.isValidSignature(signature, for: message(version: version, sha256: sha256))
    }
}
