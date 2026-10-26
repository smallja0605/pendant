#!/usr/bin/env swift
// Signs Pendant's update packages with the developer's own Ed25519 key.
// The private key lives only in this Mac's login Keychain (service com.smallja.pendant.update-signing); it is never printed, written to a
// file or committed. The matching public key is built into the app (Pendant/Services/Update/UpdateSignature.swift).
//
//   swift scripts/update-signing.swift keygen              creates the key once (does nothing if it exists) and prints the PUBLIC key
//   swift scripts/update-signing.swift public              prints the public key
//   swift scripts/update-signing.swift sign <version> <zip>  writes <zip>.sig (base64) next to the package
//
// The signed message is exactly what UpdateSignature.message(version:sha256:) builds in the app:
//   "pendant-update-v1\n<version>\n<sha256 of the zip, lower-case hex>"
import CryptoKit
import Foundation
import Security

let service = "com.smallja.pendant.update-signing"
let account = "ed25519-private-key"

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(1)
}

func readKey() -> Curve25519.Signing.PrivateKey? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
        kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: AnyObject?
    guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess, let data = result as? Data,
          let text = String(data: data, encoding: .utf8), let raw = Data(base64Encoded: text) else { return nil }
    return try? Curve25519.Signing.PrivateKey(rawRepresentation: raw)
}

func storeKey(_ key: Curve25519.Signing.PrivateKey) {
    let item: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
        kSecValueData as String: Data(key.rawRepresentation.base64EncodedString().utf8),
        kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        kSecAttrLabel as String: "Pendant update signing key (Ed25519)",
    ]
    guard SecItemAdd(item as CFDictionary, nil) == errSecSuccess else { fail("could not store the key in the Keychain") }
}

func sha256Hex(of path: String) -> String {
    guard let handle = FileHandle(forReadingAtPath: path) else { fail("cannot read \(path)") }
    var hasher = SHA256()
    while case let chunk = handle.readData(ofLength: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

let arguments = Array(CommandLine.arguments.dropFirst())
switch arguments.first {
case "keygen":
    if let key = readKey() {
        print("The key already exists. Public key:")
        print(key.publicKey.rawRepresentation.base64EncodedString())
    } else {
        let key = Curve25519.Signing.PrivateKey()
        storeKey(key)
        print("Key created in the Keychain. Public key:")
        print(key.publicKey.rawRepresentation.base64EncodedString())
    }
case "public":
    guard let key = readKey() else { fail("no key yet: run keygen") }
    print(key.publicKey.rawRepresentation.base64EncodedString())
case "sign":
    guard arguments.count == 3 else { fail("usage: sign <version> <zip>") }
    guard let key = readKey() else { fail("no key yet: run keygen") }
    let version = arguments[1], zip = arguments[2]
    let message = Data("pendant-update-v1\n\(version)\n\(sha256Hex(of: zip))".utf8)
    guard let signature = try? key.signature(for: message) else { fail("signing failed") }
    do { try Data(signature.base64EncodedString().utf8).write(to: URL(fileURLWithPath: zip + ".sig")) } catch { fail("cannot write \(zip).sig") }
    print("signed \(zip)")
default:
    fail("usage: update-signing.swift keygen | public | sign <version> <zip>")
}
