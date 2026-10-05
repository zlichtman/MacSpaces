import AppKit
import SwiftUI

struct FileBasket: Codable, Identifiable { var id = UUID(); var name: String }

@MainActor final class BasketWindowController: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = BasketWindowController()
    @Published private(set) var baskets: [FileBasket] = []
    @Published private(set) var error: String?
    private var windows: [UUID: NSPanel] = [:]
    private var stores: [UUID: ShelfStore] = [:]
    private var catalogLoaded = false
    private func load() {
        guard !catalogLoaded else { return }; catalogLoaded = true
        guard let data = UserDefaults.standard.data(forKey: "fileBaskets.v1") else { return }
        do {
            let loaded = try JSONDecoder().decode([FileBasket].self, from: data)
            guard loaded.count <= 25, Set(loaded.map(\.id)).count == loaded.count else { throw CocoaError(.fileReadCorruptFile) }
            baskets = loaded
        } catch { self.error = "The basket list could not be read. Existing basket files were preserved." }
    }
    func show(_ id: UUID? = nil) {
        load()
        guard error == nil else {
            let alert = NSAlert(); alert.messageText = "File baskets unavailable"; alert.informativeText = error!; alert.runModal(); return
        }
        guard let basket = baskets.first(where: { $0.id == id }) ?? baskets.first else { create(); return }
        if let window = windows[basket.id] { window.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let store = ShelfStore(basketID: basket.id); stores[basket.id] = store
        // A basket lives as a small circle parked where the user leaves it (by
        // default the bottom-right corner, beside the Dock) and opens into a panel.
        let panel = BasketPanel(contentRect: NSRect(origin: savedOrigin(basket.id), size: Self.bubbleSize),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = basket.name; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.level = .floating; panel.delegate = self
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: BasketRootView(manager: self, store: store, basket: basket))
        host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        panel.contentView = host
        windows[basket.id] = panel
        panel.orderFrontRegardless()
        rememberOpen()
    }
    func create() {
        load(); guard error == nil, baskets.count < 25 else { return }
        let basket = FileBasket(name: "Basket \(baskets.count + 1)")
        do {
            let next = baskets + [basket]
            let data = try JSONEncoder().encode(next)
            UserDefaults.standard.set(data, forKey: "fileBaskets.v1")
            baskets = next; show(basket.id)
        } catch { self.error = error.localizedDescription }
    }
    func rename(_ id: UUID, to name: String) {
        let name = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(70))
        guard !name.isEmpty, let index = baskets.firstIndex(where: { $0.id == id }) else { return }
        var next = baskets; next[index].name = name
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(next), forKey: "fileBaskets.v1")
            baskets = next; windows[id]?.title = name
        } catch { self.error = error.localizedDescription }
    }
    func close(_ id: UUID) { windows[id]?.close() }

    /// Takes a basket away for good: its circle, its place and its list of files.
    /// Files stay where they are; a basket only points at them.
    func remove(_ id: UUID) {
        guard let basket = baskets.first(where: { $0.id == id }) else { return }
        let store = stores[id] ?? ShelfStore(basketID: id)
        if !store.items.isEmpty {
            let alert = NSAlert()
            alert.messageText = "Remove \u{201C}\(basket.name)\u{201D}?"
            alert.informativeText = "The files in it stay where they are."
            alert.addButton(withTitle: "Remove")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            guard alert.runModal() == .alertFirstButtonReturn else { return }
        }
        let next = baskets.filter { $0.id != id }
        do {
            UserDefaults.standard.set(try JSONEncoder().encode(next), forKey: "fileBaskets.v1")
        } catch { self.error = error.localizedDescription; return }
        baskets = next
        windows[id]?.close()
        store.forgetSavedList()
        UserDefaults.standard.removeObject(forKey: "fileBaskets.origin.\(id.uuidString)")
        rememberOpen()
    }

    /// Baskets left out as circles come back where they were at launch.
    func restoreOpenBaskets() {
        let open = UserDefaults.standard.stringArray(forKey: "fileBaskets.open") ?? []
        guard !open.isEmpty else { return }
        load()
        for id in open.compactMap(UUID.init(uuidString:)) where baskets.contains(where: { $0.id == id }) { show(id) }
    }

    private func rememberOpen() {
        UserDefaults.standard.set(windows.keys.map(\.uuidString), forKey: "fileBaskets.open")
    }

    static let bubbleSize = NSSize(width: 64, height: 64)
    static let panelSize = NSSize(width: 380, height: 250)

    /// Opens the circle into the panel, or folds it back, growing away from the
    /// nearest screen corner so the circle's corner stays put.
    func setExpanded(_ expanded: Bool, _ id: UUID) {
        guard let panel = windows[id] else { return }
        let size = expanded ? Self.panelSize : Self.bubbleSize
        let old = panel.frame
        let screen = (panel.screen ?? NSScreen.main)?.visibleFrame ?? old
        let growsLeft = old.midX > screen.midX, growsDown = old.midY > screen.midY
        var frame = NSRect(x: growsLeft ? old.maxX - size.width : old.minX,
                           y: growsDown ? old.maxY - size.height : old.minY,
                           width: size.width, height: size.height)
        frame.origin.x = min(max(frame.minX, screen.minX), screen.maxX - frame.width)
        frame.origin.y = min(max(frame.minY, screen.minY), screen.maxY - frame.height)
        panel.setFrame(frame, display: true, animate: true)
        panel.invalidateShadow()
        if expanded { panel.makeKey() } else { saveOrigin(id, panel.frame.origin) }
    }

    private var dragStart: (mouse: NSPoint, origin: NSPoint)?

    /// Moves the circle with the pointer, in screen coordinates (the window moves
    /// under the gesture); the spot is remembered when the drag ends.
    func drag(_ id: UUID, ended: Bool) {
        guard let panel = windows[id] else { return }
        let mouse = NSEvent.mouseLocation
        if dragStart == nil { dragStart = (mouse, panel.frame.origin) }
        guard let start = dragStart else { return }
        panel.setFrameOrigin(NSPoint(x: start.origin.x + mouse.x - start.mouse.x, y: start.origin.y + mouse.y - start.mouse.y))
        if ended { saveOrigin(id, panel.frame.origin); dragStart = nil }
    }

    private func savedOrigin(_ id: UUID) -> NSPoint {
        if let saved = UserDefaults.standard.string(forKey: "fileBaskets.origin.\(id.uuidString)") {
            let point = NSPointFromString(saved)
            if NSScreen.screens.contains(where: { $0.visibleFrame.insetBy(dx: -10, dy: -10).contains(point) }) { return point }
        }
        // Default: the bottom-right corner, beside the Dock, staggered for each basket.
        let screen = NSScreen.main?.visibleFrame ?? .zero
        let index = CGFloat(baskets.firstIndex(where: { $0.id == id }) ?? 0)
        return NSPoint(x: screen.maxX - Self.bubbleSize.width - 18 - index * 74, y: screen.minY + 18)
    }

    private func saveOrigin(_ id: UUID, _ origin: NSPoint) {
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: "fileBaskets.origin.\(id.uuidString)")
    }

    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let id = windows.first(where: { $0.value === panel })?.key else { return }
        windows.removeValue(forKey: id); stores.removeValue(forKey: id)
        // A deliberate close takes the circle off screen until it's opened again
        // (quitting doesn't close panels, so open baskets return next launch).
        rememberOpen()
    }
}

/// Borderless panels can't take the keyboard by default; the open basket needs it for renaming.
private final class BasketPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The circle, or the open panel.
struct BasketRootView: View {
    @ObservedObject var manager: BasketWindowController
    @ObservedObject var store: ShelfStore
    let basket: FileBasket
    @State private var expanded = false

    var body: some View {
        Group {
            if expanded {
                BasketPanelView(manager: manager, store: store, basket: basket,
                                collapse: { toggle() })
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .transition(.opacity)
            } else {
                BasketBubble(manager: manager, store: store, basket: basket, open: { toggle() })
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func toggle() {
        withAnimation(.easeOut(duration: 0.18)) { expanded.toggle() }
        manager.setExpanded(expanded, basket.id)
    }
}

/// A frosted circle showing how many files it holds. Drop files on it to add
/// them, click to open it, drag to move it.
struct BasketBubble: View {
    @ObservedObject var manager: BasketWindowController
    @ObservedObject var store: ShelfStore
    let basket: FileBasket
    let open: () -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var targeted = false
    @State private var hovering = false

    var body: some View {
        ZStack {
            Circle().fill(.ultraThinMaterial)
            Circle().fill(theme.notch.surface.opacity(0.7))
            Circle().fill(RadialGradient(colors: [theme.notch.accent.opacity(targeted ? 0.45 : 0.16), .clear],
                                         center: .top, startRadius: 0, endRadius: 50))
            Circle().strokeBorder(targeted ? theme.notch.accent : Color.white.opacity(0.14), lineWidth: targeted ? 2 : 0.75)
            Image(systemName: targeted ? "tray.and.arrow.down.fill" : "tray.full.fill")
                .font(.system(size: 20, weight: .semibold))
                .foregroundStyle(targeted ? theme.notch.accent : theme.nookForeground)
        }
        .overlay(alignment: .topTrailing) {
            if !store.items.isEmpty {
                Text("\(store.items.count)")
                    .font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(.black.opacity(0.85))
                    .padding(.horizontal, 5).frame(minWidth: 18, minHeight: 18)
                    .background(theme.notch.accent, in: Capsule())
                    .offset(x: 2, y: -2)
            }
        }
        .padding(6)
        .scaleEffect(targeted ? 1.08 : hovering ? 1.03 : 1)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: targeted)
        .animation(.easeOut(duration: 0.15), value: hovering)
        .contentShape(Circle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .contextMenu {
            Button("Open") { open() }
            Divider()
            Button("Remove Basket", role: .destructive) { manager.remove(basket.id) }
        }
        .gesture(DragGesture(minimumDistance: 4)
            .onChanged { _ in manager.drag(basket.id, ended: false) }
            .onEnded { _ in manager.drag(basket.id, ended: true) })
        .onDrop(of: [.fileURL], isTargeted: $targeted) { providers in
            for provider in providers {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    guard let url else { return }
                    Task { @MainActor in store.add(url: url) }
                }
            }
            return true
        }
        .help("\(basket.name): drop files here, click to open, drag to move, right-click to remove")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(basket.name), \(store.items.count) files")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { open() }
    }
}

struct BasketPanelView: View {
    @ObservedObject var manager: BasketWindowController
    @ObservedObject var store: ShelfStore
    let basket: FileBasket
    var collapse: () -> Void = {}
    @ObservedObject private var theme = ThemeStore.shared
    @State private var targeted = false
    @State private var name = ""
    @FocusState private var editingName: Bool

    var body: some View {
        VStack(spacing: 8) {
            header
            ShelfView(store: store, isDropTargeted: $targeted)
            if let error = manager.error {
                Text(error).font(.caption).foregroundStyle(.red).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                theme.notch.surface.opacity(0.72)
                LinearGradient(colors: [theme.notch.accent.opacity(0.1), .clear], startPoint: .top, endPoint: .center)
            }
            .ignoresSafeArea()
        }
        .foregroundStyle(theme.nookForeground)
        .preferredColorScheme(theme.notch.colorScheme).tint(theme.notch.accent)
        .onAppear { name = basket.name }
        .onDisappear { manager.rename(basket.id, to: name) }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "tray.full.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(theme.notch.accent)
                .frame(width: 24, height: 24)
                .background(theme.notch.accent.opacity(0.14), in: Circle())
            VStack(alignment: .leading, spacing: 0) {
                TextField("Basket name", text: $name)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13, weight: .semibold))
                    .focused($editingName)
                    .onSubmit { manager.rename(basket.id, to: name); editingName = false }
                Text(countText).font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Menu {
                ForEach(manager.baskets) { item in
                    Button { manager.show(item.id) } label: {
                        Label(item.name, systemImage: item.id == basket.id ? "checkmark" : "tray")
                    }
                }
                Divider()
                Button("Remove Basket", role: .destructive) { manager.remove(basket.id) }
            } label: {
                headerIcon("square.stack")
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Switch or remove baskets")
            Button { manager.create() } label: { headerIcon("plus") }
                .buttonStyle(.plain).disabled(manager.baskets.count >= 25)
                .help("New basket")
            Button { manager.rename(basket.id, to: name); collapse() } label: { headerIcon("arrow.down.right.and.arrow.up.left") }
                .buttonStyle(.plain)
                .help("Fold back into a circle")
                .keyboardShortcut(.escape, modifiers: [])
            Button { manager.rename(basket.id, to: name); manager.close(basket.id) } label: { headerIcon("xmark") }
                .buttonStyle(.plain)
                .help("Close basket")
                .keyboardShortcut("w", modifiers: .command)
        }
    }

    private var countText: String {
        switch store.items.count {
        case 0: return "Empty"
        case 1: return "1 file"
        default: return "\(store.items.count) files"
        }
    }

    private func headerIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .background(Color.primary.opacity(0.07), in: Circle())
            .contentShape(Circle())
    }
}
