import CryptoKit
import Foundation
import Security

/// Encrypts what MacSpaces saves about you (clipboard history when kept, pins
/// and snippets, teleprompter scripts) with AES-GCM.
///
/// The key comes from the Secure Enclave where there is one: a P-256 key that
/// never leaves it, agreed with a stored public key and stretched with HKDF.
/// Only an opaque, device-bound blob is written to disk, useless on any other
/// Mac. Macs without a Secure Enclave keep a random key in the login keychain.
/// Older plaintext files are read once and written back encrypted.
enum SecureStorage {
    static let magic = Data("MSE1".utf8)

    /// Encrypts with the device key; on any failure the caller keeps its data unsaved rather than in plaintext.
    static func seal(_ plaintext: Data) throws -> Data {
        try seal(plaintext, with: key())
    }

    /// Plaintext from an encrypted file, or a legacy plaintext file as is.
    static func open(_ data: Data) throws -> Data {
        guard data.starts(with: magic) else { return data }
        return try open(data, with: key())
    }

    static func isSealed(_ data: Data) -> Bool { data.starts(with: magic) }

    // MARK: Testable core

    static func seal(_ plaintext: Data, with key: SymmetricKey) throws -> Data {
        guard let combined = try AES.GCM.seal(plaintext, using: key).combined else { throw CocoaError(.coderInvalidValue) }
        return magic + combined
    }

    static func open(_ data: Data, with key: SymmetricKey) throws -> Data {
        guard data.starts(with: magic) else { return data }
        return try AES.GCM.open(AES.GCM.SealedBox(combined: data.dropFirst(magic.count)), using: key)
    }

    // MARK: Key

    nonisolated(unsafe) private static var cached: SymmetricKey?
    private static let lock = NSLock()

    static func key() throws -> SymmetricKey {
        lock.lock(); defer { lock.unlock() }
        if let cached { return cached }
        let key = SecureEnclave.isAvailable ? try enclaveKey() : try keychainKey()
        cached = key
        return key
    }

    private static var directory: URL {
        let isolated = Bundle.main.bundleIdentifier != "dev.opensource.MacSpaces"
        return isolated ? FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures")
            : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSpaces")
    }

    /// The enclave key (as its device-bound blob) and the peer public key it agrees with.
    private static func enclaveKey() throws -> SymmetricKey {
        let url = directory.appendingPathComponent("storage-key.json")
        struct Stored: Codable { var enclave: Data; var peer: Data }
        let stored: Stored
        if let data = try? Data(contentsOf: url), let saved = try? JSONDecoder().decode(Stored.self, from: data) {
            stored = saved
        } else {
            let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            let peer = P256.KeyAgreement.PrivateKey()
            stored = Stored(enclave: enclave.dataRepresentation, peer: peer.publicKey.rawRepresentation)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try JSONEncoder().encode(stored).write(to: url, options: .atomic)
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
        let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey(dataRepresentation: stored.enclave)
        let peer = try P256.KeyAgreement.PublicKey(rawRepresentation: stored.peer)
        let secret = try enclave.sharedSecretFromKeyAgreement(with: peer)
        return secret.hkdfDerivedSymmetricKey(using: SHA256.self, salt: Data("MacSpaces storage".utf8),
                                              sharedInfo: Data("v1".utf8), outputByteCount: 32)
    }

    /// A random key kept in the login keychain, for Macs without a Secure Enclave.
    private static func keychainKey() throws -> SymmetricKey {
        let service = "dev.opensource.MacSpaces.storage"
        var query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
                                    kSecAttrService as String: service, kSecAttrAccount as String: "storage-key",
                                    kSecReturnData as String: true]
        var item: CFTypeRef?
        if SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data, data.count == 32 {
            return SymmetricKey(data: data)
        }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        query.removeValue(forKey: kSecReturnData as String)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess || status == errSecDuplicateItem else { throw CocoaError(.fileWriteNoPermission) }
        return key
    }
}
