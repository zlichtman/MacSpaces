import CryptoKit
import Foundation
import os
import Security

/// Encrypts what MacSpaces saves about you (clipboard history when kept, pins
/// and snippets, teleprompter scripts) with AES-GCM.
///
/// The key comes from the Secure Enclave where there is one: a P-256 key that
/// never leaves it, agreed with a stored public key and stretched with HKDF.
/// Only an opaque, device-bound blob is written to disk, useless on any other
/// Mac. Macs without a Secure Enclave keep a random key in the login keychain.
/// Older plaintext files are read once and written back encrypted.
///
/// A key that exists but can't be read is never replaced: a new key would make
/// everything already saved unreadable. Sealing fails instead, so nothing new is
/// saved and the existing files stay as they are until the key reads again.
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

    /// The saved key exists but couldn't be read; it is kept as it is.
    struct KeyUnreadable: LocalizedError {
        let reason: String
        var errorDescription: String? {
            "The encryption key couldn't be read (\(reason)), so it was kept and nothing new was saved."
        }
    }

    /// The value saved at `url`, or a new one from `create` (written owner-only)
    /// when there is no file. A file that exists but can't be read or decoded is
    /// left exactly as it is and `KeyUnreadable` is thrown: it is never overwritten.
    static func loadOrCreate<Value: Codable>(_ type: Value.Type, at url: URL, create: () throws -> Value) throws -> Value {
        if FileManager.default.fileExists(atPath: url.path) {
            do { return try JSONDecoder().decode(Value.self, from: Data(contentsOf: url)) }
            catch { throw KeyUnreadable(reason: "\(url.lastPathComponent): \(error.localizedDescription)") }
        }
        let value = try create()
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Atomic, so a crash never leaves a half-written key behind to be refused on the next launch.
        try JSONEncoder().encode(value).write(to: url, options: .atomic)
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        return value
    }

    // MARK: Key

    /// Only a key that loaded is cached; a failure is tried again on the next save.
    private static let cache = OSAllocatedUnfairLock<SymmetricKey?>(initialState: nil)

    static func key() throws -> SymmetricKey {
        try cache.withLockUnchecked { cached in
            if let cached { return cached }
            let key = SecureEnclave.isAvailable ? try enclaveKey() : try keychainKey()
            cached = key
            return key
        }
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
        let stored = try loadOrCreate(Stored.self, at: url) {
            let enclave = try SecureEnclave.P256.KeyAgreement.PrivateKey()
            let peer = P256.KeyAgreement.PrivateKey()
            return Stored(enclave: enclave.dataRepresentation, peer: peer.publicKey.rawRepresentation)
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
        func saved() throws -> SymmetricKey? {
            var item: CFTypeRef?
            let status = SecItemCopyMatching(query as CFDictionary, &item)
            if status == errSecItemNotFound { return nil }
            // Locked, denied or damaged: the item is kept, and no other key is made in its place.
            guard status == errSecSuccess, let data = item as? Data, data.count == 32 else {
                throw KeyUnreadable(reason: "keychain status \(status)")
            }
            return SymmetricKey(data: data)
        }
        if let key = try saved() { return key }
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        query.removeValue(forKey: kSecReturnData as String)
        query[kSecValueData as String] = data
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        let status = SecItemAdd(query as CFDictionary, nil)
        if status == errSecSuccess { return key }
        // Added meanwhile by someone else: use theirs, never the unsaved one.
        query.removeValue(forKey: kSecValueData as String)
        query.removeValue(forKey: kSecAttrAccessible as String)
        query[kSecReturnData as String] = true
        if status == errSecDuplicateItem, let key = try saved() { return key }
        throw CocoaError(.fileWriteNoPermission)
    }
}
