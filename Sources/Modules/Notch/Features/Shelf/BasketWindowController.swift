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
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 500, height: 280), styleMask: [.titled, .closable, .utilityWindow], backing: .buffered, defer: false)
        panel.title = basket.name; panel.isReleasedWhenClosed = false; panel.hidesOnDeactivate = false
        panel.level = .floating; panel.delegate = self
        let host = NSHostingView(rootView: BasketPanelView(manager: self, store: store, basket: basket))
        host.sizingOptions = []; host.autoresizingMask = [.width, .height]
        panel.contentView = host; panel.center()
        windows[basket.id] = panel
        panel.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true)
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
    func windowWillClose(_ notification: Notification) {
        guard let panel = notification.object as? NSPanel,
              let id = windows.first(where: { $0.value === panel })?.key else { return }
        windows.removeValue(forKey: id); stores.removeValue(forKey: id)
    }
}

private struct BasketPanelView: View {
    @ObservedObject var manager: BasketWindowController
    @ObservedObject var store: ShelfStore
    let basket: FileBasket
    @ObservedObject private var theme = ThemeStore.shared
    @State private var targeted = false
    @State private var name = ""
    var body: some View {
        VStack(spacing: 10) {
            HStack {
                TextField("Basket name", text: $name).onSubmit { manager.rename(basket.id, to: name) }
                Menu("Baskets") {
                    ForEach(manager.baskets) { item in Button(item.name) { manager.show(item.id) } }
                    Divider()
                    Button("New basket") { manager.create() }.disabled(manager.baskets.count >= 25)
                }.fixedSize()
            }
            ShelfView(store: store, isDropTargeted: $targeted)
            if let error = manager.error { Text(error).font(.caption).foregroundStyle(.red) }
        }.padding(12)
            .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
            .preferredColorScheme(theme.notch.colorScheme).tint(theme.notch.accent)
            .onAppear { name = basket.name }
            .onDisappear { manager.rename(basket.id, to: name) }
    }
}
