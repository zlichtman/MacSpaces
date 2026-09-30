import Foundation
import CryptoKit

/// Reserve before dispatch. A process exit between reservation and dispatch leaves an
/// uncertain receipt; reconnects never turn that uncertainty into a duplicate action.
final class BridgeReceiptStore {
    struct Receipt: Codable {
        var digest: String
        var response: MacSpacesBridge.Response?
    }
    private let url: URL
    private var receipts: [String: Receipt]
    init(url: URL) throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard data.count <= 16 * 1024 * 1024 else { throw MacSpacesBridge.Failure("Bridge receipt storage needs attention.") }
            receipts = try JSONDecoder().decode([String: Receipt].self, from: data)
        } else { receipts = [:] }
    }
    func existing(_ request: MacSpacesBridge.Request, owner: String) throws -> MacSpacesBridge.Response? {
        guard let receipt = receipts[key(request, owner)] else { return nil }
        guard receipt.digest == digest(request) else { throw MacSpacesBridge.Failure("This request identifier was already used for different content.") }
        return receipt.response ?? .init(error: "The earlier send has an uncertain outcome. Check the conversation; it will not be sent again.")
    }
    func reserve(_ request: MacSpacesBridge.Request, owner: String) throws {
        guard receipts.count < 20_000 else { throw MacSpacesBridge.Failure("Bridge receipt storage is full. No task was sent.") }
        let key = key(request, owner)
        guard receipts[key] == nil else { throw MacSpacesBridge.Failure("Request already reserved.") }
        receipts[key] = .init(digest: digest(request))
        do { try save() } catch { receipts.removeValue(forKey: key); throw error }
    }
    func complete(_ request: MacSpacesBridge.Request, owner: String, response: MacSpacesBridge.Response) throws {
        let key = key(request, owner)
        guard receipts[key] != nil else { throw MacSpacesBridge.Failure("Missing receipt.") }
        receipts[key]?.response = response
        try save()
    }
    private func key(_ request: MacSpacesBridge.Request, _ owner: String) -> String { owner + ":" + request.id.uuidString }
    private func digest(_ request: MacSpacesBridge.Request) -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        return SHA256.hash(data: try! encoder.encode(request)).map { String(format: "%02x", $0) }.joined()
    }
    private func save() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        try JSONEncoder().encode(receipts).write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
