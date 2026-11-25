import SwiftUI

/// The Notes page's To-Dos: every checkbox line (`- [ ] …`) in your notes in one list, a group per
/// note in the order to do them (timed first, then by priority), the first of each group the one
/// to do now. Ticking one rewrites its line in the note; one with an estimate can start a timer
/// named after it. New ones go to the To-Dos note, made when first needed. A Markdown file can be
/// linked (`TodoFile`): its to-dos lead the list, ticking one rewrites its line in the file, and
/// new ones go to the file instead. The notes and the file are read off the main thread, and a
/// superseded reading never lands.
struct NoteTasksPane: View {
    @ObservedObject var service: NotesService
    var addFocused: FocusState<Bool>.Binding
    /// Opens a note in the editor.
    let open: (UUID) -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var groups: [Group] = NoteTasksPane.startGroups
    @State private var reading: Task<Void, Never>?
    @State private var loaded = NoteTasksPane.startLoaded
    @State private var newTitle = ""
    /// The linked Markdown file's path; empty is none.
    @AppStorage(WidgetOptions.Keys.todoFilePath) private var filePath = ""
    @StateObject private var watcher = TodoFileWatcher()
    /// Why the linked file couldn't be read or changed.
    @State private var fileProblem: String?
    #if DEBUG
    /// Check renders: the list as it stands at once (a picture is taken before a reading lands),
    /// and no timers are started.
    static var preview: [Group]?
    private static var startGroups: [Group] { preview ?? [] }
    private static var startLoaded: Bool { preview != nil }
    #else
    private static var startGroups: [Group] { [] }
    private static var startLoaded: Bool { false }
    #endif

    /// The groups of these notes: each note with to-dos left, in the order to do them.
    nonisolated static func groups(of notes: [StoredNote]) -> [Group] {
        notes.compactMap { note -> Group? in
            if Task.isCancelled { return nil }
            let tasks = NoteTasks.plan(NoteTasks.tasks(in: note.current.text, note: note.id))
            return tasks.isEmpty ? nil : Group(id: note.id, title: note.title.isEmpty ? "Untitled note" : note.title, tasks: tasks)
        }
    }

    struct Group: Identifiable, Equatable {
        let id: UUID
        let title: String
        let tasks: [NoteTask]
        /// The linked file's, not a note's.
        var isFile = false
    }

    private var fileURL: URL? { filePath.isEmpty ? nil : URL(fileURLWithPath: filePath) }

    /// The note quick-added to-dos go to: the first whose first line is this.
    static let inboxTitle = "To-Dos"

    var body: some View {
        let all = groups.flatMap(\.tasks)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text("To-Dos").font(.headline).lineLimit(1)
                if !all.isEmpty {
                    Text(summary(all)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                fileMenu
            }
            .frame(height: 24)
            addField
            if let fileProblem {
                Text(fileProblem).font(.caption).foregroundStyle(.orange).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            if all.isEmpty {
                Spacer()
                Text(loaded ? "Nothing to do. Add one above, or write “- [ ] Call Sam ~15m” in any note." : "")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        ForEach(groups) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                Button {
                                    if group.isFile { if let fileURL { NSWorkspace.shared.open(fileURL) } } else { open(group.id) }
                                } label: {
                                    HStack(spacing: 3) {
                                        if group.isFile { Image(systemName: "link").font(.system(size: 8, weight: .bold)) }
                                        Text(group.title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                                    }
                                    .foregroundStyle(.secondary)
                                }
                                .buttonStyle(.plain).help(group.isFile ? "Open this file" : "Open this note")
                                ForEach(Array(group.tasks.enumerated()), id: \.element.id) { index, task in
                                    row(task, now: index == 0)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { watcher.watch(fileURL); read() }
        .onDisappear { reading?.cancel(); watcher.watch(nil) }
        .onChange(of: service.notes) { _ in read() }
        .onChange(of: filePath) { _ in fileProblem = nil; watcher.watch(fileURL); read() }
        .onChange(of: watcher.changes) { _ in read() }
    }

    /// Link a Markdown file, or open or unlink the one that's linked.
    private var fileMenu: some View {
        NookMenu {
            if let fileURL {
                NookMenuHeading(fileURL.lastPathComponent)
                NookMenuRow("Open File", systemImage: "arrow.up.forward.square") { NSWorkspace.shared.open(fileURL) }
                NookMenuRow("Unlink", systemImage: "xmark") { filePath = "" }
            } else {
                NookMenuRow("Link a Markdown File", systemImage: "link") { chooseFile() }
            }
        } label: { Image(systemName: fileURL == nil ? "ellipsis" : "link") }
            .buttonStyle(WidgetChipStyle(height: 22))
            .help(fileURL.map { "Linked to \($0.lastPathComponent)" } ?? "Link a Markdown file, such as an Obsidian note: its to-dos show here")
            .accessibilityLabel("To-Dos file")
    }

    private func chooseFile() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.plainText, .init(filenameExtension: "md")].compactMap { $0 }
        panel.message = "Choose a Markdown file. Its “- [ ]” lines show in To-Dos; ticking or adding one changes only that line."
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        filePath = url.path
    }

    private var addField: some View {
        HStack(spacing: 5) {
            Image(systemName: "plus").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            TextField("Add a to-do: Call Sam ~15m !", text: $newTitle)
                .textFieldStyle(.plain).font(.system(size: 12))
                .focused(addFocused)
                .onSubmit(add)
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("~25m is how long it takes, ! to !!! its priority, @14:30 when it's due (you're notified then)")
    }

    private func row(_ task: NoteTask, now: Bool) -> some View {
        HStack(spacing: 7) {
            Button { toggle(task) } label: {
                Image(systemName: "circle").font(.system(size: 13, weight: task.priority > 0 ? .bold : .regular))
                    .foregroundStyle(Self.colour(task.priority) ?? theme.nookForeground.opacity(0.55))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Done").accessibilityLabel("Mark \(task.title) done")
            Text(task.title).font(.system(size: 12, weight: now ? .semibold : .regular)).lineLimit(1)
                .foregroundStyle(now ? theme.nookForeground : theme.nookForeground.opacity(0.75))
            Spacer(minLength: 4)
            if let due = task.due {
                Text(NoteTasks.clock(due, uses24Hour: Self.uses24Hour)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(.secondary)
            }
            if let minutes = task.minutes {
                Button { startTimer(task, minutes: minutes) } label: {
                    HStack(spacing: 3) {
                        Image(systemName: "timer").font(.system(size: 9, weight: .semibold))
                        Text(NoteTasks.duration(minutes)).font(.system(size: 10, weight: .medium)).monospacedDigit()
                    }
                }
                .buttonStyle(WidgetChipStyle(height: 20))
                .help("Start a \(NoteTasks.duration(minutes)) timer for this")
            }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(Color.primary.opacity(now ? 0.07 : 0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func summary(_ tasks: [NoteTask]) -> String {
        let minutes = NoteTasks.minutesLeft(tasks)
        return "\(tasks.count) to do" + (minutes > 0 ? " · about \(NoteTasks.duration(minutes))" : "")
    }

    /// Yellow, orange and red for ! to !!!.
    static func colour(_ priority: Int) -> Color? {
        switch priority { case 1: return .yellow; case 2: return .orange; case 3: return .red; default: return nil }
    }

    private static var uses24Hour: Bool {
        !(DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current) ?? "").contains("a")
    }

    private func read() {
        #if DEBUG
        if Self.preview != nil { return }
        #endif
        reading?.cancel()
        let notes = service.active
        let file = fileURL
        reading = Task { @MainActor in
            let work = Task.detached(priority: .userInitiated) { [notes, file] () -> ([Group], String?) in
                var found = Self.groups(of: notes), problem: String?
                if let file {
                    do {
                        let tasks = NoteTasks.plan(NoteTasks.tasks(in: try TodoFile.read(file), note: TodoFile.noteID))
                        if !tasks.isEmpty {
                            found.insert(Group(id: TodoFile.noteID, title: file.deletingPathExtension().lastPathComponent, tasks: tasks, isFile: true), at: 0)
                        }
                    } catch {
                        problem = "Couldn’t read \(file.lastPathComponent): \(error.localizedDescription)"
                    }
                }
                return (found, problem)
            }
            let result = await withTaskCancellationHandler { await work.value } onCancel: { work.cancel() }
            guard !Task.isCancelled else { return }
            if groups != result.0 { groups = result.0 }
            if let problem = result.1 { fileProblem = problem } else if fileProblem?.hasPrefix("Couldn’t read") == true { fileProblem = nil }
            loaded = true
        }
    }

    /// A change to the linked file, off the main thread; the list is read again after it.
    private func changeFile(_ change: @escaping @Sendable (URL) throws -> String?) {
        guard let file = fileURL else { return }
        Task { @MainActor in
            let problem = await Task.detached(priority: .userInitiated) { () -> String? in
                do { return try change(file) } catch { return "Couldn’t change \(file.lastPathComponent): \(error.localizedDescription)" }
            }.value
            fileProblem = problem
            read()
        }
    }

    private func toggle(_ task: NoteTask) {
        if task.note == TodoFile.noteID {
            changeFile { file in try TodoFile.toggle(task, in: file) ? nil : "That line changed in the file, so nothing was ticked." }
            return
        }
        guard let note = service.notes.first(where: { $0.id == task.note }),
              let text = NoteTasks.toggled(note.current.text, task: task) else { read(); return }
        service.save(task.note, text: text, base: note.current.id)
    }

    private func add() {
        let title = newTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return }
        if fileURL != nil {
            // With a file linked, new to-dos go to it.
            changeFile { file in try TodoFile.append(title, to: file); return nil }
            newTitle = ""
            return
        }
        if let inbox = service.active.first(where: { $0.title == Self.inboxTitle }) {
            guard service.save(inbox.id, text: NoteTasks.adding(title, to: inbox.current.text), base: inbox.current.id) else { return }
        } else {
            guard let id = service.create(), service.save(id, text: NoteTasks.adding(title, to: Self.inboxTitle)) else { return }
        }
        newTitle = ""
        // A to-do with a time: the one place that may ask for notifications, to remind you then.
        if NoteTasks.tasks(in: "- [ ] " + title, note: UUID()).first?.due != nil { TodoNudges.shared.scheduleAfterAdding() }
    }

    private func startTimer(_ task: NoteTask, minutes: Int) {
        #if DEBUG
        if Self.preview != nil { return }
        #endif
        AppServices.shared.startTimer(seconds: TimeInterval(minutes * 60), name: task.title)
    }
}
