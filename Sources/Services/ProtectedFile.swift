import Foundation

/// A saved file that is never replaced or removed after it failed to load.
///
/// A file that exists but can't be read, decrypted or decoded may still be
/// recoverable (a key that comes back, a fixed decoder), so it is left exactly as
/// it is: writes and removals are refused until the owner explicitly sets it
/// aside, which renames it beside the original instead of deleting it.
struct ProtectedFile {
    enum Load<Value> {
        case missing
        case loaded(Value)
        case unreadable(String)
    }

    struct Blocked: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    let url: URL
    /// Why the saved file couldn't be read; while set, nothing is written over it.
    private(set) var unreadable: String?

    init(url: URL) { self.url = url }

    var isWritable: Bool { unreadable == nil }

    mutating func load<Value>(_ decode: (Data) throws -> Value) -> Load<Value> {
        guard FileManager.default.fileExists(atPath: url.path) else { unreadable = nil; return .missing }
        do {
            let value = try decode(Data(contentsOf: url))
            unreadable = nil
            return .loaded(value)
        } catch {
            unreadable = error.localizedDescription
            return .unreadable(error.localizedDescription)
        }
    }

    /// Writes `data` (atomically, owner-only) unless the saved file is unreadable.
    func write(_ data: Data, options: Data.WritingOptions = []) throws {
        if let unreadable { throw Blocked(reason: "The saved file couldn't be read, so it was kept as it is (\(unreadable)).") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: options.union(.atomic))
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    /// Removes the file (an explicit "keep nothing") unless it is unreadable.
    func remove() throws {
        if let unreadable { throw Blocked(reason: "The saved file couldn't be read, so it was kept as it is (\(unreadable)).") }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    /// The owner's explicit reset: the unreadable file is renamed beside the original
    /// (`name-unreadable-<date>.ext`), never deleted, and new saves may begin.
    @discardableResult
    mutating func setAside(now: Date = Date()) throws -> URL? {
        guard unreadable != nil else { return nil }
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let name = url.deletingPathExtension().lastPathComponent + "-unreadable-" + stamp
        let destination = url.deletingLastPathComponent().appendingPathComponent(name).appendingPathExtension(url.pathExtension)
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.moveItem(at: url, to: destination) }
        unreadable = nil
        return destination
    }
}
