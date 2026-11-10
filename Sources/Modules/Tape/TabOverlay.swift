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

/// A stack's tabs in the theme: each its app's icon and window title, the active one in the accent,
/// on the Nook's surface. Drag a tab to reorder; click to bring that window forward.
private struct TabStrip: View {
    let group: TapeTabGroup
    let controller: TapeController
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 9, style: .continuous)
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(group.windows) { window in
                    TabButton(window: window, active: group.active == window.id) { controller.chooseWindow(window.id) }
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
            }
            .padding(3)
        }
        .frame(height: 30)
        .background(shape.fill(theme.notch.surface.opacity(0.92)))
        .overlay(shape.strokeBorder(theme.nookForeground.opacity(0.12), lineWidth: 1))
        .shadow(color: .black.opacity(0.25), radius: 6, y: 2)
        .accessibilityLabel("Tape window tabs")
    }
}

private struct TabButton: View {
    let window: TapeWindowChoice
    let active: Bool
    let action: () -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if let icon = NSRunningApplication(processIdentifier: window.processID)?.icon {
                    Image(nsImage: icon).resizable().frame(width: 15, height: 15)
                }
                Text(title).lineLimit(1).font(.system(size: 11, weight: active ? .semibold : .regular))
            }
            .padding(.horizontal, 9)
            .frame(minWidth: 90, maxWidth: 220, minHeight: 24, alignment: .leading)
            .foregroundStyle(active ? theme.notch.surface : theme.nookForeground.opacity(hovering ? 0.95 : 0.75))
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(active ? theme.notch.accent : theme.nookForeground.opacity(hovering ? 0.1 : 0.04)))
            .contentShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .help(window.name)
        .accessibilityAddTraits(active ? .isSelected : [])
    }

    /// The window's title; the app's name is its icon. A window with no title shows the app.
    private var title: String {
        guard let range = window.name.range(of: " · ") else { return window.name }
        return String(window.name[range.upperBound...])
    }
}
