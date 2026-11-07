import AppKit
import AppIntents
import UniformTypeIdentifiers

extension NotchTab: AppEnum {
    static var typeDisplayRepresentation: TypeDisplayRepresentation { "Nook page" }
    static var caseDisplayRepresentations: [NotchTab: DisplayRepresentation] {
        [.nook: "Home", .music: "Music", .calendar: "Calendar", .notes: "Notes", .weather: "Weather", .tray: "Tray",
         .reminders: "Reminders", .timers: "Timers", .clipboard: "Clipboard", .system: "System", .terminal: "Terminal",
         .shortcuts: "Shortcuts", .mirror: "Mirror", .prompter: "Teleprompter",
         .meetings: "Meetings", .dictation: "Dictation", .clock: "Clock", .wisp: "Wisp"]
    }
}
struct OpenNookIntent: AppIntent {
    static var title: LocalizedStringResource = "Open Nook Page"
    static var description = IntentDescription("Opens and pins a MacSpaces page for keyboard use.")
    static var openAppWhenRun = true
    @Parameter(title: "Page") var page: NotchTab
    init() { page = .nook }
    @MainActor func perform() async throws -> some IntentResult {
        NookCommands.open(page)
        return .result()
    }
}
struct StageFilesIntent: AppIntent {
    static var title: LocalizedStringResource = "Add Files to MacSpaces Tray"
    static var description = IntentDescription("Keeps a local copy of Shortcut input files in the Tray.")
    @Parameter(title: "Files") var files: [IntentFile]
    @MainActor func perform() async throws -> some IntentResult {
        for file in files {
            let staged = try await Task.detached { try IntentFiles.stage(file) }.value
            ShelfStore.shared.add(url: staged)
        }
        return .result()
    }
}
struct ConvertFilesIntent: AppIntent {
    enum Format: String, AppEnum {
        case png, jpg, under1mb, zip
        static var typeDisplayRepresentation: TypeDisplayRepresentation { "File action" }
        static var caseDisplayRepresentations: [Format: DisplayRepresentation] { [.png: "PNG", .jpg: "JPEG", .under1mb: "Image under 1 MB", .zip: "ZIP"] }
        var action: FileConverter.Action {
            switch self {
            case .png: return .init(id: "image.png", title: "PNG", symbol: nil)
            case .jpg: return .init(id: "image.jpg", title: "JPEG", symbol: nil)
            case .under1mb: return .init(id: "tool.under1mb", title: "Under 1 MB", symbol: nil)
            case .zip: return .init(id: "zip", title: "ZIP", symbol: nil)
            }
        }
    }
    static var title: LocalizedStringResource = "Process Files with MacSpaces"
    @Parameter(title: "Files") var files: [IntentFile]
    @Parameter(title: "Action") var format: Format
    @MainActor func perform() async throws -> some IntentResult & ReturnsValue<[IntentFile]> & ProvidesDialog {
        let selectedFiles = files
        // This run's working copies go in their own temporary folder: only the outputs outlive the run.
        let folder = IntentFiles.runFolder()
        var delivered: [URL] = []
        defer {
            let keep = delivered
            Task.detached { IntentFiles.finishRun(folder, keeping: keep) }
        }
        let inputs = try await Task.detached { () throws -> [URL] in
            IntentFiles.removeOldRuns()
            return try selectedFiles.map { try IntentFiles.stage($0, in: folder) }
        }.value
        let action = format.action
        let worker = Task.detached { await FileConverter.runBatch(action, on: inputs) { _ in } }
        let result = await withTaskCancellationHandler { await worker.value } onCancel: { worker.cancel() }
        if result.cancelled { throw CancellationError() }
        if result.outputs.isEmpty, let issue = result.issues.first { throw FileConverter.Failure(message: issue.message) }
        delivered = result.outputs
        let output = result.outputs.map { url in
            var file = IntentFile(fileURL: url); file.removedOnCompletion = false; return file
        }
        return .result(value: output, dialog: "Created \(output.count) files. \(result.issues.count) inputs failed; originals are unchanged.")
    }
}
private enum IntentFiles {
    private static var runs: URL { FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesIntent", isDirectory: true) }
    static func runFolder() -> URL { runs.appendingPathComponent(UUID().uuidString, isDirectory: true) }
    /// Deletes the run's working copies, or the whole folder if nothing came of it.
    static func finishRun(_ folder: URL, keeping outputs: [URL]) {
        let manager = FileManager.default
        let kept = Set(outputs.map(\.lastPathComponent))
        guard !kept.isEmpty, let items = try? manager.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil) else {
            try? manager.removeItem(at: folder); return
        }
        for item in items where !kept.contains(item.lastPathComponent) { try? manager.removeItem(at: item) }
    }
    /// Shortcuts may still read an output after the run, so outputs stay a day, then go.
    static func removeOldRuns() {
        let manager = FileManager.default
        let cutoff = Date().addingTimeInterval(-24 * 60 * 60)
        let old = (try? manager.contentsOfDirectory(at: runs, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for run in old where ((try? run.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantFuture) < cutoff {
            try? manager.removeItem(at: run)
        }
    }
    /// Copies a Shortcut's input into the run's folder; without one, the Tray's kept Staged folder.
    static func stage(_ file: IntentFile, in runFolder: URL? = nil) throws -> URL {
        let root = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"
            ? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            : FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesIntentFixtures")
        let folder = runFolder ?? root.appendingPathComponent("MacSpaces/Staged", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = (file.filename as NSString).lastPathComponent
        let url = folder.appendingPathComponent(UUID().uuidString + "-" + (name.isEmpty ? "File" : name))
        if let source = file.fileURL {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try FileManager.default.copyItem(at: source, to: url)
        } else { try file.data.write(to: url, options: .atomic) }
        return url
    }
}
struct MacSpacesShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: OpenNookIntent(), phrases: ["Open \(.applicationName)"], shortTitle: "Open Nook", systemImageName: "rectangle.topthird.inset.filled")
    }
}

@MainActor
final class MacSpacesFileServices: NSObject {
    static let shared = MacSpacesFileServices()
    @objc func addToTray(_ board: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else {
            error.pointee = "Select one or more files first."; return
        }
        urls.forEach { ShelfStore.shared.add(url: $0) }
        NookCommands.open(.tray)
    }
    @objc func fileTools(_ board: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>) {
        guard let urls = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty else {
            error.pointee = "Select one or more files first."; return
        }
        FileToolsWindow.shared.show(urls: urls)
    }
}
