import Foundation
@main enum NoteChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("notes.json")
        var local = try NoteRepository(url: url, legacyText: "Existing scratchpad")
        let id = local.notes[0].id, base = local.notes[0].current.id
        precondition(local.notes[0].current.text == "Existing scratchpad")
        let reopened = try NoteRepository(url: url, legacyText: "Do not duplicate")
        precondition(reopened.notes.count == 1 && reopened.notes[0].id == id)
        try local.update(id, text: "Local edit")
        let remote = StoredNote(id: id, current: .init(id: UUID(), parent: base, text: "Offline edit", modified: Date(), deleted: false))
        try local.merge(remote); try local.merge(remote)
        precondition(local.notes[0].current.text == "Local edit" && local.notes[0].conflicts.count == 1)
        try local.update(id, text: "Local edit", deleted: true)
        precondition(local.notes[0].current.deleted)
        try local.update(id, text: "Local edit")
        precondition(!local.notes[0].current.deleted)
        let currentRevision = local.notes[0].current.id
        try local.update(id, text: "First window")
        try local.update(id, text: "Second window", base: currentRevision)
        let conflict = local.notes[0].conflicts.first { $0.text == "Second window" }!
        precondition(local.notes[0].current.text == "First window")
        try local.restoreVersion(note: id, revision: conflict.id)
        precondition(local.notes[0].current.text == "Second window" && local.notes[0].conflicts.contains { $0.text == "First window" })
        let before = try Data(contentsOf: url)
        do { try local.update(id, text: String(repeating: "x", count: 300_000)); preconditionFailure() } catch {}
        let after = try Data(contentsOf: url); precondition(after == before)
        try Data(#"{"version":99,"notes":[]}"#.utf8).write(to: url)
        do { _ = try NoteRepository(url: url); preconditionFailure() } catch {}
        let untouched = try String(contentsOf: url, encoding: .utf8)
        precondition(untouched.contains("99"))
        print("Notes checks passed: stable migration, conflicts, duplicate merge, delete/restore, oversized edit rejection and future schema preservation")
    }
}
