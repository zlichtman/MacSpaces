import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// Temporary file staging area in the dock: drop files in, drag them out.
/// Paths persist across launches (stale entries are pruned).
struct FileShelfWidget: View {
    @StateObject private var model = DockShelfModel()
    @State private var isTargeted = false

    var body: some View {
        Group {
            if model.items.isEmpty {
                VStack(spacing: 4) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 16))
                    Text("Drop files to stage them")
                        .font(.system(size: 9))
                }
                .foregroundStyle(isTargeted ? Color.accentColor : .secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(model.items, id: \.self) { url in
                            VStack(spacing: 2) {
                                Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                                    .resizable()
                                    .frame(width: 30, height: 30)
                                Text(url.lastPathComponent)
                                    .font(.system(size: 8))
                                    .lineLimit(1)
                                    .frame(width: 52)
                            }
                            .onDrag { NSItemProvider(object: url as NSURL) }
                            .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
                            .contextMenu {
                                Button("Open") { NSWorkspace.shared.open(url) }
                                Button("Reveal in Finder") {
                                    NSWorkspace.shared.activateFileViewerSelecting([url])
                                }
                                Button("Share via AirDrop") {
                                    NSSharingService(named: .sendViaAirDrop)?.perform(withItems: [url])
                                }
                                Divider()
                                Button("Remove", role: .destructive) { model.remove(url) }
                            }
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDrop(of: [UTType.fileURL], isTargeted: $isTargeted) { providers in
            model.handleDrop(providers: providers)
        }
    }
}

@MainActor
private final class DockShelfModel: ObservableObject {
    @Published private(set) var items: [URL] = []

    private let defaultsKey = "dockShelfPaths"

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
        items.insert(url, at: 0)
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
