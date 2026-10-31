import AppKit
import SwiftUI

@MainActor
final class CompletedDownloads: ObservableObject {
    static let shared = CompletedDownloads()
    @Published private(set) var enabled = UserDefaults.standard.bool(forKey: "downloads.watchEnabled")
    @Published private(set) var folders: [URL] = []
    @Published private(set) var problem: String?
    private var timer: Timer?
    private var scoped: [URL] = []
    private var trackers: [URL: CompletedFileTracker] = [:]
    private var scanning = false
    private var generation = UUID()
    init() {
        let saved = UserDefaults.standard.array(forKey: "downloads.watchFolders") as? [Data] ?? []
        for bookmark in saved {
            var stale = false
            if let url = try? URL(resolvingBookmarkData: bookmark, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale) { folders.append(url) }
            else { problem = "A watched folder is unavailable. Choose it again." }
        }
    }
    func restore() { if enabled { start() } }
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
    func remove(_ url: URL) { folders.removeAll { $0 == url }; saveFolders(); if enabled { start() } }
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
    private func saveFolders() {
        do {
            let bookmarks = try folders.map { try $0.bookmarkData(options: [.withSecurityScope], includingResourceValuesForKeys: nil, relativeTo: nil) }
            UserDefaults.standard.set(bookmarks, forKey: "downloads.watchFolders")
        } catch { problem = "Couldn't save watched folders: " + error.localizedDescription }
    }
    private func start() {
        stop(); guard enabled, !folders.isEmpty else { return }
        generation = UUID()
        scoped = folders.filter { $0.startAccessingSecurityScopedResource() }
        trackers = [:]; problem = nil; scan()
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
            var problem: String?
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
        Toggle("Stage completed downloads and new files", isOn: Binding(get: { watcher.enabled }, set: { watcher.setEnabled($0) }))
        ForEach(watcher.folders, id: \.self) { folder in
            HStack { Text(folder.path).lineLimit(1).truncationMode(.middle); Spacer(); SettingsRemoveButton(label: "Stop watching this folder") { watcher.remove(folder) } }
        }
        Button("Choose Folder") { watcher.chooseFolder() }.buttonStyle(.settings())
        Text("Only your chosen folders are watched, without subfolders. Existing files are ignored. Browser partial files are excluded; other new files wait until their size and modified date stay unchanged for 6 seconds.").font(.caption).foregroundStyle(.secondary)
        if let problem = watcher.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
    }
}
