import AppKit
import SwiftUI
import Combine
import UniformTypeIdentifiers

/// A nonactivating tab strip. It never becomes the user's focused app.
@MainActor
final class TabOverlayManager {
    private var panels: [WindowID: NSPanel] = [:]
    private var contentKeys: [WindowID: String] = [:]
    private var frames: [WindowID: CGRect] = [:]
    private var subscription: AnyCancellable?
    init(controller: TapeController) {
        subscription = controller.$tabGroups.sink { [weak self, weak controller] groups in
            guard let self, let controller else { return }
            self.update(groups, controller: controller)
        }
    }
    private func update(_ groups: [TapeTabGroup], controller: TapeController) {
        let ids = Set(groups.map(\.id))
        for id in Array(panels.keys) where !ids.contains(id) {
            panels.removeValue(forKey: id)?.close(); contentKeys.removeValue(forKey: id); frames.removeValue(forKey: id)
        }
        let top = NSScreen.screens.first?.frame.maxY ?? 0
        for group in groups {
            let panel = panels[group.id] ?? NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            if panels[group.id] == nil {
                panel.level = .floating
                panel.isFloatingPanel = true
                panel.hidesOnDeactivate = false
                panel.hasShadow = false
                panel.isOpaque = false
                panel.backgroundColor = .clear
                panel.collectionBehavior = [.transient, .ignoresCycle]
                panel.isReleasedWhenClosed = false
                panels[group.id] = panel
            }
            let key = group.windows.map { $0.id.rawValue.uuidString + $0.name }.joined(separator: "\n") + (group.active?.rawValue.uuidString ?? "")
            if contentKeys[group.id] != key {
                panel.contentView = NSHostingView(rootView: TabStrip(group: group, controller: controller))
                contentKeys[group.id] = key
            }
            // Skip window-server work for strips that did not move.
            let frame = CGRect(x: group.frame.minX, y: top - group.frame.maxY, width: group.frame.width, height: group.frame.height)
            guard frames[group.id] != frame || !panel.isVisible else { continue }
            frames[group.id] = frame
            panel.setFrame(frame, display: true)
            panel.orderFrontRegardless()
        }
    }
    deinit { for panel in panels.values { panel.close() } }
}

private struct TabStrip: View {
    let group: TapeTabGroup
    let controller: TapeController
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 3) {
                ForEach(group.windows) { window in
                    Button { controller.chooseWindow(window.id) } label: {
                        Text(window.name).lineLimit(1).font(.system(size: 11))
                            .padding(.horizontal, 10).frame(minWidth: 90, maxWidth: 220, minHeight: 24)
                            .background(group.active == window.id ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 5))
                    }
                    .buttonStyle(.plain).help(window.name)
                    .onDrag { NSItemProvider(object: window.id.rawValue.uuidString as NSString) }
                    .onDrop(of: [UTType.text], isTargeted: nil) { providers in
                        guard let provider = providers.first else { return false }
                        _ = provider.loadObject(ofClass: NSString.self) { value, _ in
                            guard let text = value as? String, let uuid = UUID(uuidString: text),
                                  let source = group.windows.first(where: { $0.id.rawValue == uuid }) else { return }
                            guard let target = group.windows.firstIndex(where: { $0.id == window.id }) else { return }
                            Task { @MainActor in controller.moveTab(source.id, to: target) }
                        }
                        return true
                    }
                }
            }.padding(.horizontal, 4)
        }
        .frame(height: 30).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 6))
        .accessibilityLabel("Tape window tabs")
    }
}
