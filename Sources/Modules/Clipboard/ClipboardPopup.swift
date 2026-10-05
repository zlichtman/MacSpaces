import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Clipboard history anywhere: a global shortcut (⇧⌘C by default, set in
/// Settings → Clipboard) opens a small searchable list at the pointer that works
/// entirely from the keyboard. Registering the shortcut needs no permission;
/// pasting into another app uses Accessibility, the same access the paste queue asks for.
@MainActor
final class ClipboardPopup: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = ClipboardPopup()

    /// Why the shortcut couldn't be registered (another app holds it), for Settings.
    @Published private(set) var shortcutProblem: String?
    let model = ClipboardPopupModel()

    private var hotKey: EventHotKeyRef?
    private var handlerInstalled = false
    private var panel: ClipboardPanel?
    private var keyMonitor: Any?
    private var previousApp: NSRunningApplication?

    // MARK: Shortcut

    func registerShortcut() {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        shortcutProblem = nil
        AppServices.shared.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
        let (key, modifiers): (Int, Int)
        switch ClipboardPreferences.shared.shortcut {
        case .off: return
        case .shiftCommandC: (key, modifiers) = (kVK_ANSI_C, shiftKey | cmdKey)
        case .optionCommandC: (key, modifiers) = (kVK_ANSI_C, optionKey | cmdKey)
        case .controlCommandV: (key, modifiers) = (kVK_ANSI_V, controlKey | cmdKey)
        case .shiftOptionCommandV: (key, modifiers) = (kVK_ANSI_V, shiftKey | optionKey | cmdKey)
        }
        if !handlerInstalled {
            var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
                DispatchQueue.main.async { MainActor.assumeIsolated { ClipboardPopup.shared.toggle() } }
                return noErr
            }, 1, &type, nil, nil)
            handlerInstalled = true
        }
        let id = EventHotKeyID(signature: OSType(0x4D53_4342), id: 1) // "MSCB"
        let status = RegisterEventHotKey(UInt32(key), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr {
            hotKey = nil
            shortcutProblem = "\(ClipboardPreferences.shared.shortcut.title) is already used by another app. Choose another shortcut."
        }
    }

    // MARK: Showing

    var isShown: Bool { panel?.isVisible == true }

    func toggle() { isShown ? hide() : show() }

    func show() {
        let monitor = AppServices.shared.clipboard
        if let front = NSWorkspace.shared.frontmostApplication, front != .current { previousApp = front }
        model.open(monitor: monitor)
        let preferences = ClipboardPreferences.shared
        let size = NSSize(width: preferences.showsPreview ? 660 : 420, height: 440)
        let panel = self.panel ?? makePanel()
        panel.setContentSize(size)
        panel.setFrameOrigin(origin(for: size))
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installKeys()
    }

    func hide() {
        panel?.orderOut(nil)
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor); self.keyMonitor = nil }
    }

    private func makePanel() -> ClipboardPanel {
        let panel = ClipboardPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 440),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.delegate = self
        let host = NSHostingView(rootView: ClipboardPopupView(model: model))
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        panel.contentView = host
        return panel
    }

    /// Clicking anywhere else puts the list away.
    func windowDidResignKey(_ notification: Notification) { hide() }

    private func origin(for size: NSSize) -> NSPoint {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(pointer, $0.frame, false) } ?? NSScreen.main
        let usable = screen?.visibleFrame ?? NSRect(origin: .zero, size: size)
        var origin: NSPoint
        switch ClipboardPreferences.shared.popupPosition {
        case .pointer: origin = NSPoint(x: pointer.x - 24, y: pointer.y - size.height + 12)
        case .center: origin = NSPoint(x: usable.midX - size.width / 2, y: usable.midY - size.height / 2 + usable.height * 0.08)
        case .notch: origin = NSPoint(x: usable.midX - size.width / 2, y: usable.maxY - size.height - 8)
        }
        origin.x = min(max(origin.x, usable.minX + 8), usable.maxX - size.width - 8)
        origin.y = min(max(origin.y, usable.minY + 8), usable.maxY - size.height - 8)
        return origin
    }

    // MARK: Keys

    private func installKeys() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel else { return event }
            return self.handle(event) ? nil : event
        }
    }

    /// Navigation and actions; anything else types into the search field.
    private func handle(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection([.command, .option, .shift, .control])
        let key = Int(event.keyCode)
        let preferences = ClipboardPreferences.shared
        switch (key, flags) {
        case (kVK_Escape, _): hide()
        case (kVK_DownArrow, []), (kVK_ANSI_N, [.control]): model.move(1)
        case (kVK_UpArrow, []), (kVK_ANSI_P, [.control]): model.move(-1)
        case (kVK_DownArrow, [.shift]): model.move(1, extend: true)
        case (kVK_UpArrow, [.shift]): model.move(-1, extend: true)
        case (kVK_DownArrow, [.command]): model.moveToEnd(last: true)
        case (kVK_UpArrow, [.command]): model.moveToEnd(last: false)
        case (kVK_DownArrow, [.command, .shift]): model.moveToEnd(last: true, extend: true)
        case (kVK_UpArrow, [.command, .shift]): model.moveToEnd(last: false, extend: true)
        case (kVK_Return, []), (kVK_ANSI_KeypadEnter, []):
            preferences.pasteOnSelect ? paste(plain: preferences.plainTextByDefault) : copySelection()
        case (kVK_Return, [.shift]):
            preferences.pasteOnSelect ? paste(plain: !preferences.plainTextByDefault) : copySelection()
        case (kVK_Return, [.option]): preferences.pasteOnSelect ? copySelection() : paste(plain: preferences.plainTextByDefault)
        case (kVK_Return, [.option, .shift]): paste(plain: !preferences.plainTextByDefault)
        case (kVK_ANSI_P, [.option]): model.togglePin()
        case (kVK_Delete, [.option]), (kVK_ForwardDelete, [.option]): model.deleteSelection()
        case (kVK_Delete, [.option, .command]): model.monitor?.clear(keepingFavorites: true); model.refresh()
        case (kVK_Delete, [.option, .command, .shift]): model.monitor?.clear(); model.refresh()
        case (kVK_ANSI_U, [.control]): model.query = ""
        case (kVK_ANSI_Comma, [.command]):
            hide()
            SettingsWindowController.shared.show(.clipboard)
        default:
            // ⌘1–9 copies (or pastes) that clip; ⌥1–9 does the other.
            if let number = Int(event.charactersIgnoringModifiers ?? ""), (1...9).contains(number),
               flags == [.command] || flags == [.option] {
                guard model.select(number: number) else { return true }
                let pastes = (flags == [.option]) != preferences.pasteOnSelect
                pastes ? paste(plain: preferences.plainTextByDefault) : copySelection()
                return true
            }
            return false
        }
        return true
    }

    // MARK: Actions

    func copySelection() {
        guard let monitor = model.monitor, let clip = model.selectedClips.first else { return }
        if model.selectedClips.count > 1 {
            let text = model.selectedClips.map(\.text).joined(separator: "\n")
            monitor.copyToPasteboard(ClipboardEntry(text: text))
        } else {
            monitor.copyToPasteboard(clip)
        }
        hide()
    }

    func paste(plain: Bool) {
        guard let monitor = model.monitor else { return }
        let clips = model.selectedClips
        guard !clips.isEmpty else { return }
        hide()
        monitor.paste(clips, plainText: plain, into: previousApp)
    }
}

private final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The popup's list, selection and query.
@MainActor
final class ClipboardPopupModel: ObservableObject {
    @Published var query = "" { didSet { refresh(); cursor = items.isEmpty ? nil : 0; anchor = cursor; selection = items.first.map { [$0.id] } ?? [] } }
    @Published private(set) var items: [ClipboardEntry] = []
    @Published private(set) var selection: Set<UUID> = []
    @Published private(set) var cursor: Int?
    @Published var focusToken = UUID()
    private(set) weak var monitor: ClipboardMonitor?
    private var anchor: Int?

    func open(monitor: ClipboardMonitor) {
        self.monitor = monitor
        query = ""
        focusToken = UUID()
    }

    func refresh() {
        items = monitor?.matching(query, favoritesOnly: false) ?? []
        selection = selection.filter { id in items.contains { $0.id == id } }
        if let cursor, cursor >= items.count { self.cursor = items.isEmpty ? nil : items.count - 1 }
    }

    var selectedClips: [ClipboardEntry] { items.filter { selection.contains($0.id) } }
    var current: ClipboardEntry? { cursor.flatMap { items.indices.contains($0) ? items[$0] : nil } }

    func move(_ step: Int, extend: Bool = false) {
        guard !items.isEmpty else { return }
        let next = min(max((cursor ?? -1) + step, 0), items.count - 1)
        setCursor(next, extend: extend)
    }

    func moveToEnd(last: Bool, extend: Bool = false) {
        guard !items.isEmpty else { return }
        setCursor(last ? items.count - 1 : 0, extend: extend)
    }

    func setCursor(_ index: Int, extend: Bool = false) {
        cursor = index
        if extend, let anchor {
            selection = Set(items[min(anchor, index)...max(anchor, index)].map(\.id))
        } else {
            anchor = index
            selection = [items[index].id]
        }
    }

    @discardableResult
    func select(number: Int) -> Bool {
        guard items.indices.contains(number - 1) else { return false }
        setCursor(number - 1)
        return true
    }

    func togglePin() {
        guard let monitor, let clip = current else { return }
        _ = monitor.toggleFavorite(clip)
        refresh()
        if let index = items.firstIndex(where: { $0.id == clip.id }) { setCursor(index) }
    }

    func deleteSelection() {
        guard let monitor else { return }
        let index = cursor ?? 0
        for clip in selectedClips { monitor.remove(clip) }
        refresh()
        if !items.isEmpty { setCursor(min(index, items.count - 1)) } else { cursor = nil; selection = [] }
    }
}
