import Foundation

/// A Markdown file linked to To-Dos (an Obsidian inbox or daily note, say): its checkbox lines
/// show with your notes' to-dos. The file is the only copy. It's read afresh each time, and
/// written only by ticking a to-do or adding one: the file is read again just before, the one
/// line changed or added, and the whole written back atomically; a line that's no longer that
/// to-do is left alone. Nothing else in it is ever touched.
enum TodoFile {
    /// Stands in for a note's id on the file's to-dos.
    static let noteID = UUID(uuidString: "00000000-0000-0000-0000-00000000F11E")!
    /// Larger files aren't read: this is a list, not an archive.
    static let limit = 2 * 1024 * 1024

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func read(_ url: URL) throws -> String {
        let size = (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        guard size <= limit else { throw Failure(message: "\(url.lastPathComponent) is too large to use for to-dos.") }
        guard let text = String(data: try Data(contentsOf: url), encoding: .utf8) else {
            throw Failure(message: "\(url.lastPathComponent) isn't plain text.")
        }
        return text
    }

    /// Ticks or clears that to-do's box in the file. False when the line is no longer that
    /// to-do (the file changed): nothing is written.
    static func toggle(_ task: NoteTask, in url: URL) throws -> Bool {
        guard let changed = NoteTasks.toggled(try read(url), task: task) else { return false }
        try changed.write(to: url, atomically: true, encoding: .utf8)
        return true
    }

    /// Adds a to-do on a line of its own at the end of the file.
    static func append(_ title: String, to url: URL) throws {
        try NoteTasks.adding(title, to: try read(url)).write(to: url, atomically: true, encoding: .utf8)
    }
}

/// Says when anything in the linked file's folder changes (editors save by replacing the file,
/// which only its folder notices), while the To-Dos list is showing.
final class TodoFileWatcher: ObservableObject {
    @Published private(set) var changes = 0
    private var source: DispatchSourceFileSystemObject?
    private var watched: URL?

    func watch(_ url: URL?) {
        guard url != watched else { return }
        source?.cancel()
        source = nil
        watched = url
        guard let folder = url?.deletingLastPathComponent() else { return }
        let descriptor = open(folder.path, O_EVTONLY)
        guard descriptor >= 0 else { return }
        let made = DispatchSource.makeFileSystemObjectSource(fileDescriptor: descriptor, eventMask: .write, queue: .main)
        made.setEventHandler { [weak self] in self?.changes &+= 1 }
        made.setCancelHandler { close(descriptor) }
        made.resume()
        source = made
    }

    deinit { source?.cancel() }
}
