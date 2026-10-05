import Foundation

struct NoteRevision: Codable, Equatable, Identifiable {
    var id: UUID
    var parent: UUID?
    var text: String
    var modified: Date
    var deleted: Bool
}
struct StoredNote: Codable, Equatable, Identifiable {
    var id: UUID
    var current: NoteRevision
    var conflicts: [NoteRevision] = []
    var title: String { String(current.text.split(separator: "\n").first.map(String.init)?.prefix(70) ?? "Untitled note") }
}
struct NoteRepository {
    private struct Envelope: Codable { var version = 1; var notes: [StoredNote] }
    private(set) var notes: [StoredNote]
    let url: URL
    init(url: URL, legacyText: String = "") throws {
        self.url = url
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            guard data.count <= 16 * 1024 * 1024 else { throw Failure("Notes file exceeds the safe size limit.") }
            let envelope = try JSONDecoder().decode(Envelope.self, from: data)
            guard envelope.version == 1 else { throw Failure("These notes require a newer MacSpaces version.") }
            guard Set(envelope.notes.map(\.id)).count == envelope.notes.count else { throw Failure("Notes contain duplicate identifiers.") }
            notes = envelope.notes
        } else {
            notes = []
            if !legacyText.isEmpty { notes = [.init(id: UUID(), current: .init(id: UUID(), text: legacyText, modified: Date(), deleted: false))] }
            try save()
        }
    }
    @discardableResult mutating func create(text: String = "") throws -> UUID {
        guard notes.count < 2_000 else { throw Failure("The local note limit has been reached.") }
        let id = UUID()
        try mutate { $0.append(.init(id: id, current: .init(id: UUID(), text: text, modified: Date(), deleted: false))) }
        return id
    }
    mutating func update(_ id: UUID, text: String, deleted: Bool = false, base: UUID? = nil) throws {
        guard text.utf8.count <= 256 * 1024 else { throw Failure("A note can contain up to 256 KiB of text.") }
        guard let index = notes.firstIndex(where: { $0.id == id }) else { throw Failure("Note no longer exists.") }
        guard notes[index].current.text != text || notes[index].current.deleted != deleted else { return }
        try mutate { notes in
            if let base, base != notes[index].current.id {
                if !notes[index].conflicts.contains(where: { $0.text == text && $0.deleted == deleted }) {
                    notes[index].conflicts.append(.init(id: UUID(), parent: base, text: text, modified: Date(), deleted: deleted))
                }
            } else {
                notes[index].current = .init(id: UUID(), parent: notes[index].current.id, text: text, modified: Date(), deleted: deleted)
            }
        }
    }
    mutating func restoreVersion(note id: UUID, revision: UUID) throws {
        guard let index = notes.firstIndex(where: { $0.id == id }),
              let version = notes[index].conflicts.first(where: { $0.id == revision }) else { throw Failure("That note version is unavailable.") }
        try mutate { notes in
            let previous = notes[index].current
            notes[index].conflicts.removeAll { $0.id == revision }
            if !notes[index].conflicts.contains(where: { $0.id == previous.id }) { notes[index].conflicts.append(previous) }
            notes[index].current = .init(id: UUID(), parent: previous.id, text: version.text, modified: Date(), deleted: version.deleted)
        }
    }
    /// Applies a direct successor; concurrent edits remain recoverable, including edit/delete conflicts.
    mutating func merge(_ incoming: StoredNote) throws {
        guard incoming.current.text.utf8.count <= 256 * 1024 else { throw Failure("Incoming note is too large.") }
        try mutate { notes in
            guard let index = notes.firstIndex(where: { $0.id == incoming.id }) else { notes.append(incoming); return }
            guard notes[index].current.id != incoming.current.id else { return }
            if incoming.current.parent == notes[index].current.id { notes[index].current = incoming.current }
            else if notes[index].current.parent != incoming.current.id && !notes[index].conflicts.contains(where: { $0.id == incoming.current.id }) {
                notes[index].conflicts.append(incoming.current)
            }
        }
    }
    private mutating func mutate(_ change: (inout [StoredNote]) -> Void) throws {
        let original = notes; change(&notes)
        do { try save() } catch { notes = original; throw error }
    }
    private func save() throws {
        let data = try JSONEncoder().encode(Envelope(notes: notes))
        guard data.count <= 16 * 1024 * 1024 else { throw Failure("Notes storage is full; no edits were overwritten.") }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.deletingLastPathComponent().path)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUnlessOpen])
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
    struct Failure: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
