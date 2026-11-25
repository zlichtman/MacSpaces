import AppKit
import SwiftUI

@MainActor
final class CompletedDownloads: ObservableObject {
    static let shared = CompletedDownloads()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "downloads.watchEnabled")
    @Published private(set) var folders: [URL] = []
    /// Saved bookmarks that don't resolve now (a drive that isn't mounted). They stay saved and
    /// are tried again on every start, so a folder is never lost because its drive was away.
    @Published private(set) var unavailable: [Data] = []
    @Published private(set) var problem: String?
    private var timer: Timer?
    private var scoped: [URL] = []
    private var trackers: [URL: CompletedFileTracker] = [:]
    private var scanning = false
    private var generation = UUID()
    /// Each resolved folder's saved bookmark, written back as is rather than rebuilt on every save.
    private var bookmarks: [URL: Data] = [:]
    private static let unavailableText = "A watched folder is unavailable. Connect its drive or remove it."
    init() {
        let saved = UserDefaults.standard.array(forKey: "downloads.watchFolders") as? [Data] ?? []
        var refreshed = false
        for bookmark in saved {
            switch resolve(bookmark) {
            case .none: unavailable.append(bookmark)
            case .some(let stale): refreshed = refreshed || stale
            }
        }
        if !unavailable.isEmpty { problem = Self.unavailableText }
        if refreshed { saveFolders() }
    }
    func restore() { if enabled { start() } }
    /// Adds the bookmark's folder; nil when it doesn't resolve, otherwise whether it was stale and
    /// got a fresh bookmark. Resolution keeps the options that never mount a volume.
    private func resolve(_ bookmark: Data) -> Bool? {
        var stale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) else { return nil }
        var data = bookmark
        if stale {
            // A stale bookmark still resolves now but may not next time, so it's remade while it works.
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let fresh = try? url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) { data = fresh }
        }
        if !folders.contains(url) { folders.append(url) }
        bookmarks[url] = data
        return stale
    }
    /// The path an unavailable bookmark points at, read without resolving (or mounting) it.
    nonisolated static func path(of bookmark: Data) -> String {
        URL.resourceValues(forKeys: [.pathKey], fromBookmarkData: bookmark)?.path ?? "Unavailable folder"
    }
    /// Calls back once the panel closes (a sheet on Settings while it's open).
    func chooseFolder(then done: @escaping () -> Void = {}) {
        let panel = NSOpenPanel(); panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.message = "Only newly arriving files in this folder will be staged. Subfolders are not watched."
        SettingsWindowController.shared.runPanel(panel) { [weak self] chosen in
            guard let self else { return }
            if chosen, let url = panel.url {
                if !self.folders.contains(url) { self.folders.append(url) }
                self.saveFolders(); if self.enabled { self.start() }
            }
            done()
        }
    }
    func remove(_ url: URL) { folders.removeAll { $0 == url }; bookmarks[url] = nil; removed() }
    func removeUnavailable(_ bookmark: Data) { unavailable.removeAll { $0 == bookmark }; removed() }
    /// Removing the last folder turns watching off, so it isn't left on with nothing to watch.
    private func removed() {
        saveFolders()
        if folders.isEmpty && unavailable.isEmpty && enabled { setEnabled(false) }
        else if enabled { start() }
        else if unavailable.isEmpty { problem = nil }
    }
    func setEnabled(_ value: Bool) {
        if value && folders.isEmpty {
            chooseFolder { [weak self] in
                guard let self, !self.folders.isEmpty else { return }
                self.setEnabled(true)
            }
            return
        }
        enabled = value; UserDefaults.standard.set(value, forKey: "downloads.watchEnabled")
        value ? start() : stop()
    }
    /// Unavailable bookmarks are saved too, so a save never drops a folder whose drive is away.
    private func saveFolders() {
        var saved: [Data] = []
        for url in folders {
            if let data = bookmarks[url] { saved.append(data); continue }
            do {
                let data = try url.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil)
                bookmarks[url] = data; saved.append(data)
            } catch { problem = "Couldn't save watched folders: " + error.localizedDescription; return }
        }
        UserDefaults.standard.set(saved + unavailable, forKey: "downloads.watchFolders")
    }
    private func start() {
        stop()
        // A drive connected since the last start brings its folder back.
        if !unavailable.isEmpty {
            let waiting = unavailable
            var refreshed = false
            unavailable = waiting.filter { bookmark in
                guard let stale = resolve(bookmark) else { return true }
                refreshed = refreshed || stale
                return false
            }
            if unavailable.count != waiting.count || refreshed { saveFolders() }
        }
        problem = unavailable.isEmpty ? nil : Self.unavailableText
        guard enabled, !folders.isEmpty else { return }
        generation = UUID()
        scoped = folders.filter { $0.startAccessingSecurityScopedResource() }
        trackers = [:]; scan()
        timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in Task { @MainActor in self?.scan() } }
        // Common modes keep it firing while a menu is open or a drag is tracking.
        RunLoop.main.add(timer!, forMode: .common)
    }
    private func stop() {
        generation = UUID(); timer?.invalidate(); timer = nil; scanning = false
        scoped.forEach { $0.stopAccessingSecurityScopedResource() }; scoped = []; trackers = [:]
    }
    private func scan() {
        guard enabled, !scanning else { return }
        scanning = true
        let folders = folders, token = generation
        Task { [weak self] in
            let snapshots = await Task.detached(priority: .utility) {
                folders.map { folder -> (URL, [URL: CompletedFileTracker.Fingerprint]?, String?) in
                    do {
                        let urls = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey], options: [.skipsHiddenFiles])
                        guard urls.count <= 10_000 else { return (folder, nil, "Choose a smaller folder (under 10,000 items).") }
                        var files: [URL: CompletedFileTracker.Fingerprint] = [:]
                        for url in urls {
                            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]), values.isRegularFile == true {
                                files[url] = .init(bytes: values.fileSize ?? 0, modified: values.contentModificationDate ?? .distantPast)
                            }
                        }
                        return (folder, files, nil)
                    } catch { return (folder, nil, error.localizedDescription) }
                }
            }.value
            guard let self, self.generation == token else { return }
            self.scanning = false
            // Set once per scan, so a scan that changes nothing publishes nothing.
            var problem: String? = self.unavailable.isEmpty ? nil : Self.unavailableText
            defer { if self.problem != problem { self.problem = problem } }
            for (folder, files, error) in snapshots {
                guard let files else { problem = folder.lastPathComponent + ": " + (error ?? "Unavailable"); continue }
                if self.trackers[folder] == nil { self.trackers[folder] = CompletedFileTracker(existing: Set(files.keys)); continue }
                let completed = self.trackers[folder]?.poll(files, at: Date()) ?? []
                completed.forEach { ShelfStore.shared.add(url: $0) }
            }
        }
    }
}

struct CompletedDownloadsSettings: View {
    @ObservedObject private var watcher = CompletedDownloads.shared
    var body: some View {
        Toggle("Add new files from these folders to the Tray", isOn: Binding(get: { watcher.enabled }, set: { watcher.setEnabled($0) }))
        ForEach(watcher.folders, id: \.self) { folder in
            HStack { Text(folder.path).lineLimit(1).truncationMode(.middle); Spacer(); SettingsRemoveButton(label: "Stop watching this folder") { watcher.remove(folder) } }
        }
        ForEach(watcher.unavailable, id: \.self) { bookmark in
            HStack {
                Text(CompletedDownloads.path(of: bookmark)).lineLimit(1).truncationMode(.middle).foregroundStyle(.secondary)
                Text("Unavailable").font(.caption).foregroundStyle(.orange)
                Spacer(); SettingsRemoveButton(label: "Stop watching this folder") { watcher.removeUnavailable(bookmark) }
            }
        }
        Button("Choose Folder") { watcher.chooseFolder() }.buttonStyle(.settings())
        SettingsCaption("New files in these folders wait in the Tray. Existing files are ignored.",
                        help: "Only your chosen folders are watched, without subfolders. Existing files are ignored. Browser partial files are excluded; other new files wait until their size and modified date stay unchanged for 6 seconds.")
        if let problem = watcher.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
    }
}
