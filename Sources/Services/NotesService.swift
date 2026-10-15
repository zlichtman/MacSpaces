import Foundation
import Combine

@MainActor final class NotesService: ObservableObject {
    @Published private(set) var notes: [StoredNote] = []
    @Published private(set) var error: String?
    private var repository: NoteRepository?
    init(url: URL? = nil, legacyText: String? = nil) {
        do {
            let isolated = Bundle.main.bundleIdentifier != "dev.opensource.MacSpaces"
            let defaultURL = isolated
                ? FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures/" + (Bundle.main.bundleIdentifier ?? "tests") + "/notes-v1.json")
                : FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSpaces/notes-v1.json")
            repository = try NoteRepository(url: url ?? defaultURL, legacyText: legacyText ?? UserDefaults.standard.string(forKey: "quickNote") ?? "")
            refresh()
        } catch { self.error = error.localizedDescription }
    }
    var active: [StoredNote] { notes.filter { !$0.current.deleted } }
    func create() -> UUID? {
        do {
            guard repository != nil else { return nil }
            let id = try repository?.create(); refresh(); return id
        } catch { self.error = error.localizedDescription; return nil }
    }
    @discardableResult func save(_ id: UUID, text: String, deleted: Bool = false, base: UUID? = nil) -> Bool {
        do {
            guard repository != nil else { return false }
            try repository?.update(id, text: text, deleted: deleted, base: base); refresh(); return true
        } catch { self.error = error.localizedDescription; return false }
    }
    func restoreVersion(note: UUID, revision: UUID) {
        do { try repository?.restoreVersion(note: note, revision: revision); refresh() }
        catch { self.error = error.localizedDescription }
    }
    private func refresh() { notes = repository?.notes ?? []; error = nil }
}
