import Foundation
import Combine

/// One editor's working copy of a note and the revision it was loaded from.
struct NoteDraft: Equatable {
    let id: UUID
    var text: String
    fileprivate(set) var base: UUID
    fileprivate(set) var saved: String
    var isDirty: Bool { text != saved }
}

@MainActor final class NotesService: ObservableObject {
    @Published private(set) var notes: [StoredNote] = []
    @Published private(set) var error: String?
    private var repository: NoteRepository?
    init(url: URL? = nil, legacyText: String? = nil) {
        do {
            let isolated = Bundle.main.bundleIdentifier != "dev.opensource.MacSpaces"
            let fixtureURL = ProcessInfo.processInfo.environment["MACSPACES_DEMO_FIXTURE_ROOT"]
                .map { URL(fileURLWithPath: $0).appendingPathComponent("notes-v1.json") }
            let defaultURL = isolated
                ? (fixtureURL ?? FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures/" + (Bundle.main.bundleIdentifier ?? "tests") + "/notes-v1.json"))
                : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSpaces/notes-v1.json")
            repository = try NoteRepository(url: url ?? defaultURL, legacyText: legacyText ?? UserDefaults.standard.string(forKey: "quickNote") ?? "")
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    var active: [StoredNote] { notes.filter { !$0.current.deleted } }
    var deleted: [StoredNote] { notes.filter { $0.current.deleted } }
    func create() -> UUID? {
        do {
            guard repository != nil else { return nil }
            let id = try repository?.create(); refresh(); return id
        } catch { self.error = error.localizedDescription; return nil }
    }
    /// An empty note if one is waiting, so New without typing doesn't pile them up.
    func blankNote() -> UUID? { active.first { $0.current.text.isEmpty }?.id ?? create() }
    @discardableResult func save(_ id: UUID, text: String, deleted: Bool = false, base: UUID? = nil) -> Bool {
        do {
            guard repository != nil else { return false }
            try repository?.update(id, text: text, deleted: deleted, base: base); refresh(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func draft(of id: UUID) -> NoteDraft? {
        notes.first { $0.id == id }.map { .init(id: $0.id, text: $0.current.text, base: $0.current.id, saved: $0.current.text) }
    }
    /// Saves a draft if it changed, then reloads it. When the note moved on since the draft's base, the
    /// repository keeps the draft's text under Other versions and the draft becomes the current version;
    /// holding on to the old base or text would pile up a version per save, and moving to the new base
    /// with the old text would overwrite the other edit.
    func commit(_ draft: inout NoteDraft) -> Bool {
        guard draft.isDirty else { return true }
        guard save(draft.id, text: draft.text, base: draft.base), let fresh = self.draft(of: draft.id) else { return false }
        draft = fresh
        return true
    }
    /// Moves a note to Recently Deleted. A stale base keeps the deletion under Other versions instead.
    func trash(_ id: UUID, text: String, base: UUID?) -> Bool { save(id, text: text, deleted: true, base: base) }
    /// Brings a note back from Recently Deleted.
    func restore(_ id: UUID) -> Bool {
        guard let note = notes.first(where: { $0.id == id }) else { return false }
        return save(id, text: note.current.text)
    }
    func restoreVersion(note: UUID, revision: UUID) {
        do { try repository?.restoreVersion(note: note, revision: revision); refresh() }
        catch { self.error = error.localizedDescription }
    }
    private func refresh() { notes = repository?.notes ?? []; error = nil }
}
