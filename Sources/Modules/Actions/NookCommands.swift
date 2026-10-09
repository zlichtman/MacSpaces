import AppKit
import Carbon.HIToolbox
import SwiftUI

@MainActor
enum NookCommands {
    struct Command: Identifiable {
        let id: String
        let title: String
        let detail: String
        let symbol: String
        let run: () -> Void
    }
    static func open(_ page: NotchTab, target: NSRunningApplication? = nil) {
        if page == .dictation { DictationModel.shared.captureTarget(target) }
        AppSettings.shared.notchEnabled = true
        DispatchQueue.main.async { NotchManager.active?.openForKeyboard(page) }
    }
    static var all: [Command] {
        var commands = ([NotchTab.nook] + NotchTab.appPages).map { tab in
            Command(id: "page." + tab.rawValue, title: "Open " + tab.title, detail: "Nook page", symbol: tab.systemImage) {
                open(tab, target: tab == .dictation ? ActionSearchWindow.shared.previousApp : nil)
            }
        }
        commands += [
            Command(id: "clipboard.popup", title: "Clipboard History", detail: "Search and paste copied items", symbol: "doc.on.clipboard") { ClipboardPopup.shared.show() },
            Command(id: "files.tools", title: "File Tools", detail: "Convert, resize, crop, compress, extract text", symbol: "wand.and.stars") { FileToolsWindow.shared.show() },
            Command(id: "files.baskets", title: "File Baskets", detail: "Stage files anywhere on the desktop", symbol: "tray.full") { BasketWindowController.shared.show() },
            Command(id: "files.paste", title: "Paste into Tray", detail: "Stage copied files, text, links or images", symbol: "tray.and.arrow.down") { ShelfStore.shared.paste(); open(.tray) },
            Command(id: "voice.dictation", title: "Dictation", detail: "On-device speech to text", symbol: "mic") { open(.dictation, target: ActionSearchWindow.shared.previousApp) },
            Command(id: "meetings.controls", title: "Meeting Controls", detail: "Join, microphone and camera controls", symbol: "video") { open(.meetings) },
            Command(id: "settings.general", title: "General Settings", detail: "Behavior, displays and updates", symbol: "gearshape") { SettingsWindowController.shared.show(.general) },
            Command(id: "settings.themes", title: "Themes", detail: "Appearance and accessibility", symbol: "paintpalette") { SettingsWindowController.shared.show(.appearance) },
            Command(id: "settings.widgets", title: "Widgets and Profiles", detail: "Customize Home and dock", symbol: "square.grid.2x2") { SettingsWindowController.shared.show(.widgets) },
        ]
        let exampleFiles = ["photo.png", "document.pdf", "movie.mov", "audio.wav", "archive.zip", "notes.txt"].map { URL(fileURLWithPath: "/" + $0) }
        var seenActions = Set<String>()
        for url in exampleFiles {
            for action in FileConverter.actions(for: [url], tools: false) + FileConverter.actions(for: [url], tools: true) + FileConverter.presets(for: [url]) where seenActions.insert(action.id).inserted {
                commands.append(Command(id: "file." + action.id, title: action.title, detail: "File tool · choose files to process", symbol: action.symbol ?? "doc") { FileToolsWindow.shared.show(action: action) })
            }
        }
        commands += AppServices.shared.shortcuts.names.map { name in
            Command(id: "shortcut." + name, title: name, detail: "Apple Shortcut", symbol: "bolt") { AppServices.shared.shortcuts.run(name) }
        }
        return commands
    }
}

@MainActor
final class ActionSearchWindow: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ActionSearchWindow()
    @Published var query = ""
    @Published var selectedIndex = 0
    @Published private(set) var commands: [NookCommands.Command] = []
    private var panel: ActionPanel?
    private var monitor: Any?
    private(set) var previousApp: NSRunningApplication?
    var matches: [NookCommands.Command] {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace)
        return commands.filter { command in terms.allSatisfy { (command.title + " " + command.detail).lowercased().contains($0) } }
    }
#if DEBUG
    func setPreview() { commands = NookCommands.all; query = ""; selectedIndex = 0 }
#endif
    func show() {
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previousApp = front }
        query = ""; selectedIndex = 0; commands = NookCommands.all
        AppServices.shared.shortcuts.startIfNeeded()
        if panel == nil {
            let panel = ActionPanel(contentRect: NSRect(x: 0, y: 0, width: 580, height: 430), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .popUpMenu; panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true; panel.delegate = self
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: ActionSearchView(model: self))
            self.panel = panel
        }
        if let frame = NSScreen.screens.first(where: { $0.frame.contains(NSEvent.mouseLocation) })?.visibleFrame {
            panel?.setFrameOrigin(NSPoint(x: frame.midX - 290, y: frame.midY - 120))
        }
        panel?.makeKeyAndOrderFront(nil)
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            switch event.keyCode {
            case 53: self.hide(); return nil
            case 125: self.selectedIndex = min(max(0, self.matches.count - 1), self.selectedIndex + 1); return nil
            case 126: self.selectedIndex = max(0, self.selectedIndex - 1); return nil
            case 36: self.execute(); return nil
            default: return event
            }
        }
    }
    func windowDidResignKey(_ notification: Notification) { hide() }
    func hide() { panel?.orderOut(nil); if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil } }
    func execute() {
        guard matches.indices.contains(selectedIndex) else { return }
        let command = matches[selectedIndex]; hide(); command.run()
    }
    private final class ActionPanel: NSPanel { override var canBecomeKey: Bool { true } }
}

struct ActionSearchView: View {
    @ObservedObject var model: ActionSearchWindow
    @ObservedObject private var shortcuts = AppServices.shared.shortcuts
    @ObservedObject private var theme = ThemeStore.shared
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 10) {
            HStack { Image(systemName: "magnifyingglass"); TextField("Find a MacSpaces action", text: $model.query).textFieldStyle(.plain).focused($focused); Text("esc").font(.caption).foregroundStyle(.secondary) }.padding(16)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 3) {
                        ForEach(Array(model.matches.enumerated()), id: \.element.id) { index, command in
                            Button { model.selectedIndex = index; model.execute() } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: command.symbol).frame(width: 24).foregroundStyle(theme.notch.accent)
                                    VStack(alignment: .leading, spacing: 1) { Text(command.title).font(.system(size: 14, weight: .medium)); Text(command.detail).font(.caption).foregroundStyle(.secondary) }
                                    Spacer()
                                    if index == model.selectedIndex { Image(systemName: "return").foregroundStyle(.secondary) }
                                }.padding(10).background(index == model.selectedIndex ? theme.notch.selected : .clear, in: RoundedRectangle(cornerRadius: 8))
                            }.buttonStyle(.plain).id(command.id)
                        }
                        if model.matches.isEmpty { Text("No matching actions").foregroundStyle(.secondary).padding(20) }
                    }.padding(.horizontal, 8)
                }
                .onChange(of: model.selectedIndex) { _, value in if model.matches.indices.contains(value) { proxy.scrollTo(model.matches[value].id) } }
            }
            Text("↑ ↓ to choose · Return to run · Escape to close").font(.caption).foregroundStyle(.secondary).padding(.bottom, 12)
        }.frame(width: 580, height: 430).background(theme.notch.surface, in: RoundedRectangle(cornerRadius: 18))
        .foregroundStyle(theme.nookForeground).tint(theme.notch.accent).preferredColorScheme(theme.notch.colorScheme)
        .onAppear { focused = true }
        .onChange(of: model.query) { _, _ in model.selectedIndex = 0 }
        .onChange(of: shortcuts.names) { _, _ in model.showUpdatedCommands() }
    }
}

extension ActionSearchWindow {
    fileprivate func showUpdatedCommands() { commands = NookCommands.all; selectedIndex = min(selectedIndex, max(0, matches.count - 1)) }
}

@MainActor
final class NookHotKeys: ObservableObject {
    static let shared = NookHotKeys()
    enum Shortcut: String, CaseIterable, Identifiable {
        case off, controlOptionSpace, controlOptionCommandSpace
        var id: String { rawValue }
        var title: String { switch self { case .off: return "Off"; case .controlOptionSpace: return "⌃⌥ Space"; case .controlOptionCommandSpace: return "⌃⌥⌘ Space" } }
    }
    @Published var shortcut = Shortcut(rawValue: UserDefaults.standard.string(forKey: "nook.actionShortcut") ?? "") ?? .controlOptionSpace {
        didSet { UserDefaults.standard.set(shortcut.rawValue, forKey: "nook.actionShortcut"); register() }
    }
    @Published var directPages = UserDefaults.standard.bool(forKey: "nook.directShortcuts") {
        didSet { UserDefaults.standard.set(directPages, forKey: "nook.directShortcuts"); register() }
    }
    @Published private(set) var problem: String?
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    func register() {
        references.forEach { UnregisterEventHotKey($0) }; references = []; problem = nil
        if handler == nil {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, event, _ in
                var id = EventHotKeyID()
                guard GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &id) == noErr, id.signature == 0x4D534E4B else { return OSStatus(eventNotHandledErr) }
                let key = id.id
                DispatchQueue.main.async { MainActor.assumeIsolated {
                    switch key {
                    case 1: ActionSearchWindow.shared.show()
                    case 2: NookCommands.open(.nook)
                    case 3: NookCommands.open(.tray)
                    case 4: NookCommands.open(.music)
                    case 5: NookCommands.open(.terminal)
                    case 6: NookCommands.open(.dictation)
                    default: break
                    }
                } }
                return noErr
            }, 1, &type, nil, &handler)
        }
        if shortcut != .off {
            add(kVK_Space, modifiers: controlKey | optionKey | (shortcut == .controlOptionCommandSpace ? cmdKey : 0), id: 1, label: shortcut.title)
        }
        if directPages {
            for (key, id, title) in [(kVK_ANSI_N, 2, "Home"), (kVK_ANSI_T, 3, "Tray"), (kVK_ANSI_M, 4, "Music"), (kVK_ANSI_K, 5, "Terminal"), (kVK_ANSI_D, 6, "Dictation")] {
                add(key, modifiers: controlKey | optionKey, id: UInt32(id), label: "⌃⌥ " + title)
            }
        }
    }
    private func add(_ key: Int, modifiers: Int, id: UInt32, label: String) {
        var reference: EventHotKeyRef?
        let result = RegisterEventHotKey(UInt32(key), UInt32(modifiers), EventHotKeyID(signature: 0x4D534E4B, id: id), GetApplicationEventTarget(), 0, &reference)
        if result == noErr, let reference { references.append(reference) } else { problem = (problem.map { $0 + "\n" } ?? "") + label + " is already used. Choose another shortcut or turn direct shortcuts off." }
    }
}
