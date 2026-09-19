import SwiftUI
import UniformTypeIdentifiers

/// Pinned app/folder launcher. Drag apps or folders onto the tile to pin
/// them; click to open; right-click to unpin. Paths persist in UserDefaults.
struct AppsWidget: View {
    @StateObject private var model = PinnedItemsModel()
    @State private var isTargeted = false

    private let columns = [GridItem(.adaptive(minimum: 34), spacing: 6)]

    var body: some View {
        Group {
            if model.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "plus.square.dashed")
                        .font(.system(size: 16))
                    Text("Drop apps or folders here")
                        .font(.system(size: 9))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            } else {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(model.items, id: \.self) { url in
                        PinnedItemButton(url: url) {
                            model.remove(url)
                        }
                    }
                }
                .padding(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            model.handleDrop(providers: providers)
        }
    }
}

private struct PinnedItemButton: View {
    let url: URL
    let remove: () -> Void
    @State private var hoveredProcessIdentifier: pid_t?

    var body: some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 32, height: 32)
        }
        .buttonStyle(.plain)
        .help(url.deletingPathExtension().lastPathComponent)
        .onHover { hovering in
            if hovering, let application = runningApplication {
                hoveredProcessIdentifier = application.processIdentifier
                DockWindowPreviewController.shared.hoverWindows(
                    for: application,
                    anchor: NSEvent.mouseLocation
                )
            } else if let hoveredProcessIdentifier {
                DockWindowPreviewController.shared.endMacSpacesAppHover(
                    processIdentifier: hoveredProcessIdentifier
                )
                self.hoveredProcessIdentifier = nil
            }
        }
        .contextMenu {
            Button("Unpin", role: .destructive, action: remove)
        }
    }

    private var runningApplication: NSRunningApplication? {
        guard let bundleIdentifier = Bundle(url: url)?.bundleIdentifier else {
            return nil
        }
        return NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
        ).first
    }
}

@MainActor
private final class PinnedItemsModel: ObservableObject {
    @Published private(set) var items: [URL] = []

    private let defaultsKey = "pinnedAppPaths"

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func handleDrop(providers: [NSItemProvider]) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    self.add(url)
                }
            }
        }
        return accepted
    }

    private func add(_ url: URL) {
        guard !items.contains(url) else { return }
        items.append(url)
        persist()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        persist()
    }

    private func persist() {
        UserDefaults.standard.set(items.map(\.path), forKey: defaultsKey)
    }
}
