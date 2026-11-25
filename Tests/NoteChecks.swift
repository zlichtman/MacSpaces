import Foundation
@main @MainActor enum NoteChecks {
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
        checkDrafts(directory.appendingPathComponent("drafts.json"))
        print("Notes checks passed: stable migration, conflicts, duplicate merge, delete/restore, oversized edit rejection, future schema preservation, autosave drafts with a stale base and search")
    }

    /// What the Notes page's autosave does, through NotesService as the page calls it.
    private static func checkDrafts(_ url: URL) {
        let service = NotesService(url: url, legacyText: "")
        let id = service.create()!
        func note() -> StoredNote { service.notes.first { $0.id == id }! }
        var page = service.draft(of: id)!
        var otherScreen = service.draft(of: id)!
        precondition(service.commit(&page) && note().current.text.isEmpty, "An unchanged draft saves nothing")

        // Autosave after autosave: each builds on the last, with no conflict.
        page.text = "One"; precondition(page.isDirty && service.commit(&page))
        precondition(!page.isDirty && page.base == note().current.id)
        page.text = "One two"; precondition(service.commit(&page))
        precondition(note().current.text == "One two" && note().conflicts.isEmpty)

        // An autosave from a stale base keeps both edits, and the editor moves to the current version.
        otherScreen.text = "Stale edit"; precondition(service.commit(&otherScreen))
        precondition(note().current.text == "One two" && note().conflicts.map(\.text) == ["Stale edit"])
        precondition(otherScreen.text == "One two" && otherScreen.base == note().current.id && !otherScreen.isDirty)
        // The next autosaves neither overwrite the other edit unseen nor pile up versions.
        precondition(service.commit(&otherScreen) && note().conflicts.count == 1)
        otherScreen.text = "One two three"; precondition(service.commit(&otherScreen))
        precondition(note().current.text == "One two three" && note().conflicts.map(\.text) == ["Stale edit"])

        // Leaving with an untouched draft from a stale base adds no version.
        precondition(service.commit(&page) && note().conflicts.count == 1)
        page = service.draft(of: id)!

        // Delete and restore; a delete from a stale base waits under Other versions.
        var stale = page
        page.text = "Latest"; precondition(service.commit(&page))
        precondition(service.trash(id, text: stale.text, base: stale.base))
        precondition(!note().current.deleted && note().conflicts.contains { $0.deleted })
        stale = service.draft(of: id)!
        precondition(service.trash(id, text: stale.text, base: stale.base) && note().current.deleted)
        precondition(service.active.isEmpty && service.deleted.map(\.id) == [id])
        precondition(service.restore(id) && !note().current.deleted && note().current.text == "Latest")

        // Search covers title and text, ignores case, and skips nothing for an untitled note.
        let body = service.create()!, blank = service.create()!
        service.save(body, text: "Groceries\nOat milk")
        let found = { (query: String) in StoredNote.ids(matching: query, in: service.active) }
        precondition(found("groceries") == [body] && found("OAT") == [body] && found("untitled") == [blank] && found("nothing").isEmpty)
    }
}
