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
                NookMenuRow(action.title) { FileToolsWindow.shared.show(urls: urls, action: action) }
            }
            ForEach(preferences.presets.filter { preset in list.presets.contains { $0.id == preset.actionID } }) { preset in
                NookMenuRow(preset.title) { store.run(preset.action) }
            }
            NookMenuRow("All File Tools") { FileToolsWindow.shared.show(urls: urls) }
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

@MainActor
final class FileToolsWindow: NSObject, ObservableObject {
    static let shared = FileToolsWindow()
    @Published var urls: [URL] = []
    @Published var selected: FileConverter.Action?
    @Published var options = FileConverter.Options()
    private var window: NSWindow?
    func show(urls: [URL] = [], action: FileConverter.Action? = nil) {
        self.urls = urls; selected = action
        options = action?.options ?? FileConverter.Options(maximumDimension: action?.id == "preset.gif" ? 480 : 1600)
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 580, height: 620), styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.title = "MacSpaces File Tools"
            window.isReleasedWhenClosed = false
            window.minSize = NSSize(width: 500, height: 500)
            window.contentView = NSHostingView(rootView: FileToolsView(model: self))
            window.center(); self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
    func chooseFiles() {
        let panel = NSOpenPanel(); panel.allowsMultipleSelection = true; panel.canChooseDirectories = true
        guard panel.runModal() == .OK else { return }
        urls = panel.urls
        let allowed = FileConverter.actions(for: urls, tools: false) + FileConverter.actions(for: urls, tools: true) + FileConverter.presets(for: urls)
        if let selected, !allowed.contains(where: { $0.id == selected.id }) { self.selected = nil }
    }
    func run() {
        guard var action = selected, !urls.isEmpty else { return }
        if action.id.hasPrefix("preset.") { action.options = options }
        FileActionPreferences.shared.used(action)
        ConverterJobs.shared.start(action, on: urls)
    }
}

struct FileToolsView: View {
    @ObservedObject var model: FileToolsWindow
    @ObservedObject private var preferences = FileActionPreferences.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var query = ""
    @State private var presetName = ""
    @AppStorage(WidgetOptions.Keys.converterRevealResults) private var revealResults = false
    @State private var offered = FileActionList()
    private var list: FileActionList { offered.urls == model.urls ? offered : FileActionList() }
    private var actions: [FileConverter.Action] {
        preferences.ordered(list.actions + list.presets)
            .filter { query.isEmpty || $0.title.localizedCaseInsensitiveContains(query) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(model.urls.isEmpty ? "Choose files to see their tools" : model.urls.count == 1 ? model.urls[0].lastPathComponent : "\(model.urls.count) files selected")
                    .font(.headline).lineLimit(2).truncationMode(.middle)
                Spacer()
                Button("Choose Files") { model.chooseFiles() }.buttonStyle(WidgetChipStyle(height: 26))
            }
            Text("Originals stay untouched. Results are saved beside them, or in Downloads when the folder is read-only.")
                .font(.caption).foregroundStyle(.secondary)
            NookTextField("Find a format or tool", text: $query)
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
                .buttonStyle(WidgetChipStyle(height: 26))
            }
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(actions) { action in
                        HStack {
                            Button {
                                model.selected = action
                                if action.id == "preset.gif" { model.options.maximumDimension = 480 }
                            } label: {
                                Label(action.title, systemImage: action.symbol ?? "doc")
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(9)
                                    .background(model.selected?.id == action.id ? theme.notch.selected : theme.notch.control, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain)
                            Button { preferences.toggle(action.id) } label: {
                                Image(systemName: preferences.favorites.contains(action.id) ? "star.fill" : "star")
                            }.buttonStyle(.plain).help("Favorite this action").accessibilityLabel("Favorite " + action.title)
                        }
                    }
                }
            }
            if let action = model.selected {
                Text(action.title).font(.headline)
                if action.id == "tool.compress" {
                    Text("Compression may change format or quality. Transparency is preserved; a result is kept only when it is smaller.").font(.caption).foregroundStyle(.secondary)
                }
                if action.id == "tool.gif" || action.id == "video.gif" {
                    Text("Default GIF: first 8 seconds, 12 fps, 480 px. Use GIF clip for custom timing and size.").font(.caption).foregroundStyle(.secondary)
                }
                if action.id == "preset.size" {
                    HStack { Text("Maximum MB"); TextField("MB", value: Binding(get: { Double(model.options.maximumBytes) / 1_000_000 }, set: { model.options.maximumBytes = Int64(max(0.01, min(2000, $0.isFinite ? $0 : 5)) * 1_000_000) }), format: .number).frame(width: 100) }
                    if model.urls.first.map({ FileConverter.family(of: $0) == .image }) == true {
                        HStack { Text("JPEG quality"); Slider(value: $model.options.quality, in: 0.1...1); Text("\(Int(model.options.quality * 100))%") }
                        Text("Transparent images stay PNG. Other images become JPEG; lower quality and resolution may be needed to fit.").font(.caption).foregroundStyle(.secondary)
                    }
                    Text("Tries native presets and keeps only a result within the target. A very small target may not be reachable.").font(.caption).foregroundStyle(.secondary)
                }
                if action.id == "preset.resize" || action.id == "preset.gif" {
                    HStack { Text("Longest edge"); TextField("Pixels", value: $model.options.maximumDimension, format: .number).frame(width: 100); Text("px").foregroundStyle(.secondary) }
                }
                if action.id == "preset.resize" {
                    NookMenu {
                        ForEach([("Keep shape", 0.0), ("Square", 1.0), ("16:9", 16.0 / 9), ("4:3", 4.0 / 3)] as [(String, Double)], id: \.1) { choice in
                            NookMenuRow(choice.0, selected: model.options.cropRatio == choice.1) { model.options.cropRatio = choice.1 }
                        }
                    } label: { Text("Center crop") }
                    .buttonStyle(WidgetChipStyle(height: 26))
                }
                if action.id == "preset.gif" {
                    HStack { Text("Start seconds"); TextField("Start", value: $model.options.gifStart, format: .number); Text("Duration"); TextField("Seconds", value: $model.options.gifDuration, format: .number); Text("FPS"); TextField("FPS", value: $model.options.gifFPS, format: .number) }
                    Text("Up to 30 seconds and 960 px; shorter and smaller clips make lighter GIFs.").font(.caption).foregroundStyle(.secondary)
                }
            }
            if let action = model.selected, action.id.hasPrefix("preset.") {
                HStack { NookTextField("Name this preset", text: $presetName)
                    Button("Save Preset") { preferences.savePreset(presetName, action: action, options: model.options); presetName = "" }.disabled(presetName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).buttonStyle(WidgetChipStyle(height: 26))
                }
            }
            Toggle("Reveal results in Finder automatically", isOn: $revealResults).font(.caption)
            HStack {
                Text("Cancel, retry, reveal or drag results from the job cards.").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Run") { model.run() }.buttonStyle(WidgetChipStyle(prominent: true, height: 26))
                    .disabled(model.selected == nil || model.urls.isEmpty)
                    .opacity(model.selected == nil || model.urls.isEmpty ? 0.45 : 1)
            }
        }.padding(22).frame(minWidth: 480, minHeight: 460)
        .background(theme.notch.surface).foregroundStyle(theme.nookForeground).tint(theme.notch.accent).preferredColorScheme(theme.notch.colorScheme)
        .onAppear { AppServices.shared.shortcuts.startIfNeeded() }
        .task(id: model.urls) {
            let list = await FileActionList.load(model.urls)
            if !Task.isCancelled { offered = list }
        }
    }
}
