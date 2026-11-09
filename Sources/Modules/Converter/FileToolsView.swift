import AppKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class FileActionPreferences: ObservableObject {
    static let shared = FileActionPreferences()
    struct Preset: Identifiable, Codable {
        let id: UUID
        let title: String
        let actionID: String
        let options: FileConverter.Options
        var action: FileConverter.Action { .init(id: actionID, title: title, symbol: "slider.horizontal.3", options: options) }
    }
    @Published var presets: [Preset] = (UserDefaults.standard.data(forKey: "fileActions.presets").flatMap { try? JSONDecoder().decode([Preset].self, from: $0) }) ?? [] {
        didSet { if let data = try? JSONEncoder().encode(presets) { UserDefaults.standard.set(data, forKey: "fileActions.presets") } }
    }
    func savePreset(_ title: String, action: FileConverter.Action, options: FileConverter.Options) {
        let name = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, action.id.hasPrefix("preset.") else { return }
        presets.append(.init(id: UUID(), title: String(name.prefix(80)), actionID: action.id, options: options))
    }
    @Published var favorites: [String] = UserDefaults.standard.stringArray(forKey: "fileActions.favorites") ?? [] {
        didSet { UserDefaults.standard.set(favorites, forKey: "fileActions.favorites") }
    }
    @Published var recent: [String] = UserDefaults.standard.stringArray(forKey: "fileActions.recent") ?? [] {
        didSet { UserDefaults.standard.set(recent, forKey: "fileActions.recent") }
    }
    func toggle(_ id: String) { favorites.contains(id) ? favorites.removeAll { $0 == id } : favorites.append(id) }
    func used(_ action: FileConverter.Action) { recent.removeAll { $0 == action.id }; recent.insert(action.id, at: 0); recent = Array(recent.prefix(6)) }
    func ordered(_ actions: [FileConverter.Action]) -> [FileConverter.Action] {
        let order = favorites + recent
        return actions.sorted {
            let a = order.firstIndex(of: $0.id) ?? Int.max, b = order.firstIndex(of: $1.id) ?? Int.max
            return a == b ? $0.title.localizedStandardCompare($1.title) == .orderedAscending : a < b
        }
    }
}

/// What can be done with some files. Working it out opens each one (image frames,
/// PDF pages), so it's done off the main thread, once per selection.
struct FileActionList: Sendable {
    var urls: [URL] = []
    var actions: [FileConverter.Action] = []
    var presets: [FileConverter.Action] = []

    static func load(_ urls: [URL]) async -> FileActionList {
        guard !urls.isEmpty else { return FileActionList() }
        return await Task.detached(priority: .userInitiated) { [urls] in
            FileActionList(urls: urls, actions: FileConverter.actions(for: urls, tools: false) + FileConverter.actions(for: urls, tools: true),
                           presets: FileConverter.presets(for: urls))
        }.value
    }
}

struct FileActionMenu: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject private var preferences = FileActionPreferences.shared
    @State private var offered = FileActionList()
    private var urls: [URL] { store.selectedItems.map(\.url) }
    private var list: FileActionList { offered.urls == urls ? offered : FileActionList() }
    var body: some View {
        NookMenu {
            ForEach(preferences.ordered(list.actions)) { action in
                NookMenuRow(action.title) { preferences.used(action); store.run(action) }
            }
            NookMenuDivider()
            ForEach(list.presets) { action in
                NookMenuRow(action.title) { FileToolsModel.shared.open(urls: urls, action: action) }
            }
            ForEach(preferences.presets.filter { preset in list.presets.contains { $0.id == preset.actionID } }) { preset in
                NookMenuRow(preset.title) { store.run(preset.action) }
            }
            NookMenuRow("All File Tools") { FileToolsModel.shared.open(urls: urls) }
            if !AppServices.shared.shortcuts.names.isEmpty {
                NookMenuDivider()
                NookMenuHeading("Run Shortcut")
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(AppServices.shared.shortcuts.names, id: \.self) { name in
                            NookMenuRow(name) { AppServices.shared.shortcuts.run(name, inputs: urls) }
                        }
                    }
                }
                .frame(maxHeight: 140)
            }
        } label: {
            // The Tray's toolbar shows it as an icon beside Quick Look and Share.
            Image(systemName: "wand.and.stars")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 26, height: 24)
                .background(Color.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Convert, compress and other file actions")
        .disabled(urls.isEmpty)
        .task(id: urls) {
            let list = await FileActionList.load(urls)
            if !Task.isCancelled { offered = list }
        }
    }
}

/// File Tools: the files chosen, the tool picked and its options. They show in Folio's Tools
/// place on the Nook's Folio page; `open` brings the Nook up there from anywhere (the menu,
/// Find Action, Finder Services, Shortcuts, Settings), whether or not Folio is in the dock.
@MainActor
final class FileToolsModel: ObservableObject {
    static let shared = FileToolsModel()
    @Published var urls: [URL] = []
    @Published var selected: FileConverter.Action?
    @Published var options = FileConverter.Options()
    /// Changes each time something asks for the Tools place, so an open Folio page moves there.
    @Published private(set) var request = UUID()

    /// Opens the Nook on Folio's Tools place with these files and, when given, this tool picked.
    func open(urls: [URL] = [], action: FileConverter.Action? = nil) {
        show(urls: urls, action: action)
        NotchViewModel.pendingFolioPlace = .tools
        NookCommands.open(.tray)
    }

    /// Moves an open Folio page to Tools with these files (the file actions menu's All File Tools).
    func show(urls: [URL], action: FileConverter.Action? = nil) {
        self.urls = urls; selected = action
        options = action?.options ?? FileConverter.Options(maximumDimension: action?.id == "preset.gif" ? 480 : 1600)
        request = UUID()
    }

    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        use(panel.urls)
    }

    /// Files dropped on the Tools place or chosen; a picked tool that doesn't fit them is let go.
    func use(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        self.urls = urls
        let allowed = FileConverter.actions(for: urls, tools: false) + FileConverter.actions(for: urls, tools: true) + FileConverter.presets(for: urls)
        if let selected, !allowed.contains(where: { $0.id == selected.id }) { self.selected = nil }
    }

    func drop(_ providers: [NSItemProvider]) -> Bool {
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        guard !files.isEmpty else { return false }
        Task { @MainActor [weak self] in
            var urls: [URL] = []
            for provider in files {
                let url: URL? = await withCheckedContinuation { continuation in
                    _ = provider.loadObject(ofClass: URL.self) { url, _ in continuation.resume(returning: url) }
                }
                if let url { urls.append(url) }
            }
            self?.use(urls)
        }
        return true
    }

    func run() {
        guard var action = selected, !urls.isEmpty else { return }
        if action.id.hasPrefix("preset.") { action.options = options }
        FileActionPreferences.shared.used(action)
        ConverterJobs.shared.start(action, on: urls)
    }
}

/// Folio's Tools place, sized for the Nook: the files and the tools that fit them on the left
/// (favourites first, narrowed by Folio's search), the picked tool's options and Run on the right. Originals are
/// never edited: results are saved beside them (Downloads when that folder is read-only).
struct FileToolsView: View {
    @ObservedObject var model: FileToolsModel
    /// Folio's search, which narrows the tools here.
    var query = ""
    @ObservedObject private var preferences = FileActionPreferences.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var presetName = ""
    @State private var targeted = false
    @AppStorage(WidgetOptions.Keys.converterRevealResults) private var revealResults = false
    @State private var offered = FileActionList()
    private var list: FileActionList { offered.urls == model.urls ? offered : FileActionList() }
    private var actions: [FileConverter.Action] {
        preferences.ordered(list.actions + list.presets)
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            toolList.frame(maxWidth: .infinity)
            Rectangle().fill(Color.primary.opacity(0.08)).frame(width: 0.5)
            settings.frame(width: 210)
        }
        .font(.system(size: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(theme.notch.accent, lineWidth: 1.5).opacity(targeted ? 1 : 0)
        }
        .onDrop(of: [UTType.fileURL], isTargeted: $targeted) { model.drop($0) }
        .onAppear { AppServices.shared.shortcuts.startIfNeeded() }
        .task(id: model.urls) {
            let list = await FileActionList.load(model.urls)
            if !Task.isCancelled { offered = list }
        }
    }

    private var toolList: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(model.urls.isEmpty ? "Drop or choose files" : model.urls.count == 1 ? model.urls[0].lastPathComponent : "\(model.urls.count) files")
                    .font(.system(size: 11, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                Spacer(minLength: 4)
                Button("Choose Files") { model.chooseFiles() }.buttonStyle(WidgetChipStyle(height: 22))
            }
            if model.urls.isEmpty {
                FolioQuietEmpty(symbol: "wand.and.stars", title: "No files yet",
                                detail: "Drop files here, or select some and choose All File Tools.")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 3) {
                        ForEach(actions) { action in row(action) }
                    }
                }
            }
        }
    }

    private func row(_ action: FileConverter.Action) -> some View {
        HStack(spacing: 4) {
            Button {
                model.selected = action
                if action.id == "preset.gif" { model.options.maximumDimension = 480 }
            } label: {
                Label(action.title, systemImage: action.symbol ?? "doc").lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 8).frame(height: 22)
                    .background(model.selected?.id == action.id ? theme.notch.selected : theme.notch.control,
                                in: RoundedRectangle(cornerRadius: 7, style: .continuous))
                    .contentShape(Rectangle())
            }.buttonStyle(.plain)
            Button { preferences.toggle(action.id) } label: {
                Image(systemName: preferences.favorites.contains(action.id) ? "star.fill" : "star").font(.system(size: 10))
                    .frame(width: 18, height: 22).contentShape(Rectangle())
            }.buttonStyle(.plain).foregroundStyle(.secondary).help("Favorite this action").accessibilityLabel("Favorite " + action.title)
        }
    }

    private var settings: some View {
        VStack(alignment: .leading, spacing: 6) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 6) {
                    if let action = model.selected { options(for: action) } else {
                        Text("Pick a tool").font(.system(size: 12, weight: .semibold))
                        caption("Originals stay untouched; copies go beside them.")
                            .help("Originals stay untouched. Results are saved beside them, or in Downloads when the folder is read-only.")
                    }
                    if !preferences.presets.isEmpty {
                        NookMenu {
                            ForEach(preferences.presets.filter { preset in list.presets.contains { $0.id == preset.actionID } }) { preset in
                                NookMenuRow(preset.title) { model.selected = preset.action; model.options = preset.options }
                            }
                            NookMenuDivider()
                            NookMenuHeading("Remove preset")
                            ForEach(preferences.presets) { preset in
                                NookMenuRow(preset.title, destructive: true) { preferences.presets.removeAll { $0.id == preset.id } }
                            }
                        } label: { Text("Saved presets") }
                        .buttonStyle(WidgetChipStyle(height: 22))
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Toggle("Reveal results in Finder", isOn: $revealResults).toggleStyle(.checkbox).font(.system(size: 10))
            HStack(spacing: 6) {
                caption("Progress shows on job cards").help("Cancel, retry, reveal or drag results from the job cards.")
                Spacer(minLength: 2)
                Button("Run") { model.run() }.buttonStyle(WidgetChipStyle(prominent: true, height: 24))
                    .disabled(model.selected == nil || model.urls.isEmpty)
                    .opacity(model.selected == nil || model.urls.isEmpty ? 0.45 : 1)
            }
        }
    }

    @ViewBuilder
    private func options(for action: FileConverter.Action) -> some View {
        Text(action.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
        if action.id == "tool.compress" {
            caption("Keeps transparency; kept only if smaller")
                .help("Compression may change format or quality. Transparency is preserved; a result is kept only when it is smaller.")
        }
        if action.id == "tool.gif" || action.id == "video.gif" {
            caption("First 8 seconds, 12 fps, 480 px")
                .help("Default GIF: first 8 seconds, 12 fps, 480 px. Use GIF clip for custom timing and size.")
        }
        if action.id == "preset.size" {
            field("Maximum MB") {
                TextField("MB", value: Binding(get: { Double(model.options.maximumBytes) / 1_000_000 }, set: { model.options.maximumBytes = Int64(max(0.01, min(2000, $0.isFinite ? $0 : 5)) * 1_000_000) }), format: .number)
            }
            if model.urls.first.map({ FileConverter.family(of: $0) == .image }) == true {
                HStack(spacing: 4) { Text("Quality"); Slider(value: $model.options.quality, in: 0.1...1); Text("\(Int(model.options.quality * 100))%").monospacedDigit() }
                    .help("Transparent images stay PNG. Other images become JPEG; lower quality and resolution may be needed to fit.")
            }
            caption("Keeps only a result within the target")
                .help("Tries native presets and keeps only a result within the target. A very small target may not be reachable.")
        }
        if action.id == "preset.resize" || action.id == "preset.gif" {
            field("Longest edge, px") { TextField("Pixels", value: $model.options.maximumDimension, format: .number) }
        }
        if action.id == "preset.resize" {
            NookMenu {
                ForEach([("Keep shape", 0.0), ("Square", 1.0), ("16:9", 16.0 / 9), ("4:3", 4.0 / 3)] as [(String, Double)], id: \.1) { choice in
                    NookMenuRow(choice.0, selected: model.options.cropRatio == choice.1) { model.options.cropRatio = choice.1 }
                }
            } label: { Text("Center crop") }
            .buttonStyle(WidgetChipStyle(height: 22))
        }
        if action.id == "preset.gif" {
            field("Start, seconds") { TextField("Start", value: $model.options.gifStart, format: .number) }
            field("Duration, seconds") { TextField("Seconds", value: $model.options.gifDuration, format: .number) }
            field("Frames per second") { TextField("FPS", value: $model.options.gifFPS, format: .number) }
            caption("Up to 30 seconds and 960 px")
                .help("Up to 30 seconds and 960 px; shorter and smaller clips make lighter GIFs.")
        }
        if action.id.hasPrefix("preset.") {
            HStack(spacing: 4) {
                NookTextField("Name this preset", text: $presetName, height: 22)
                Button("Save") { preferences.savePreset(presetName, action: action, options: model.options); presetName = "" }
                    .disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).buttonStyle(WidgetChipStyle(height: 22))
            }
        }
    }

    private func field<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        HStack(spacing: 6) {
            Text(title).lineLimit(1)
            Spacer(minLength: 4)
            content().textFieldStyle(.roundedBorder).frame(width: 64)
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
    }
}
