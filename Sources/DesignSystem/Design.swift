import SwiftUI
import AppKit

enum Design {
    static let tileRadius: CGFloat = 16
    static let surfaceRadius: CGFloat = 24
    static let controlRadius: CGFloat = 10
    static let smallRadius: CGFloat = 8

    static let tileSpacing: CGFloat = 8
    static let surfacePadding: CGFloat = 10

    static let hairline = Color.white.opacity(0.12)
    static let subtleShadow = Color.black.opacity(0.24)

    @MainActor
    static func spring() -> Animation {
        ThemeStore.shared.reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.30, dampingFraction: 0.88)
    }

    @MainActor
    static var hoverAnimation: Animation {
        ThemeStore.shared.reduceMotion ? .linear(duration: 0.01) : .easeOut(duration: 0.16)
    }
}

/// Shared material and edge treatment; content remains specific to the widget.
struct PremiumWidgetChrome: View {
    let tokens: ThemeTokens
    let style: WidgetVisualStyle
    let isActive: Bool

    var radius: CGFloat { style.chromeRadius }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            switch style {
            case .studio:
                shape.fill(tokens.tileGradient)
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.055), .clear], startPoint: .top, endPoint: .center))
            case .glass:
                shape.fill(tokens.surface.opacity(0.54))
                shape.fill(LinearGradient(colors: [Color.white.opacity(0.13), tokens.tile.opacity(0.72)], startPoint: .topLeading, endPoint: .bottomTrailing))
            case .terminal:
                shape.fill(tokens.surfaceSecondary.opacity(0.70))
                shape.fill(tokens.tile.opacity(0.34))
            case .soft:
                shape.fill(tokens.tileGradient)
                Circle()
                    .fill(tokens.accent.opacity(0.12))
                    .frame(width: 100, height: 100)
                    .blur(radius: 24)
                    .offset(x: 44, y: -34)
            case .signal:
                shape.fill(tokens.surface.opacity(0.92))
                shape.fill(
                    LinearGradient(
                        colors: [tokens.accent.opacity(0.18), tokens.tile.opacity(0.45), .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
            case .orbit:
                shape.fill(tokens.tileGradient)
                shape.fill(
                    RadialGradient(
                        colors: [tokens.accent.opacity(0.13), .clear],
                        center: .center,
                        startRadius: 2,
                        endRadius: 86
                    )
                )
            case .mono:
                shape.fill(
                    tokens.colorScheme == .dark
                        ? Color.black.opacity(0.78)
                        : Color.white.opacity(0.92)
                )
                Rectangle()
                    .fill(tokens.accent)
                    .frame(width: 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipShape(shape)
            case .frame:
                shape.fill(tokens.surface.opacity(0.34))
                shape.strokeBorder(tokens.accent.opacity(0.22), lineWidth: 4)
                    .padding(5)
            }
        }
        .overlay {
            shape.strokeBorder(
                style == .terminal || style == .signal || style == .mono || style == .frame
                    ? tokens.accent.opacity(isActive ? 0.64 : 0.34)
                    : tokens.border.opacity(isActive ? 1 : 0.72),
                lineWidth: (style == .terminal || style == .signal || style == .mono) ? 1 : 0.8
            )
        }
    }
}

struct PremiumPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            .animation(.easeOut(duration: 0.14), value: configuration.isPressed)
    }
}

struct ThemedSurfaceModifier: ViewModifier {
    let tokens: ThemeTokens
    let radius: CGFloat
    let shadow: Bool

    func body(content: Content) -> some View {
        content
            .background(tokens.surfaceGradient, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(tokens.border, lineWidth: 1)
            }
            .shadow(color: shadow ? tokens.shadow : .clear, radius: 18, y: 8)
            .shadow(color: shadow ? tokens.glow : .clear, radius: 26)
            .environment(\.colorScheme, tokens.colorScheme)
            .tint(tokens.accent)
    }
}

extension View {
    func themedSurface(_ tokens: ThemeTokens, radius: CGFloat, shadow: Bool = true) -> some View {
        modifier(ThemedSurfaceModifier(tokens: tokens, radius: radius, shadow: shadow))
    }

    func themedTile(_ tokens: ThemeTokens, radius: CGFloat = Design.tileRadius) -> some View {
        background(tokens.tileGradient, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
    }
}

/// Ends a SwiftUI drag even when the pointer is released outside the source
/// window. That keeps Nook hover state and deferred persistence from getting
/// stranded after a cancelled widget move.
@MainActor
final class WidgetDragSession {
    static let shared = WidgetDragSession()

    private var localMouseUpMonitor: Any?
    private var globalMouseUpMonitor: Any?
    private var endHandler: (() -> Void)?

    private init() {}

    func begin(onEnd: @escaping () -> Void) {
        finish()
        endHandler = onEnd

        localMouseUpMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .leftMouseUp
        ) { [weak self] event in
            Task { @MainActor [weak self] in self?.finish() }
            return event
        }

        globalMouseUpMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .leftMouseUp
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.finish() }
        }
    }

    func finish() {
        if let localMouseUpMonitor {
            NSEvent.removeMonitor(localMouseUpMonitor)
            self.localMouseUpMonitor = nil
        }
        if let globalMouseUpMonitor {
            NSEvent.removeMonitor(globalMouseUpMonitor)
            self.globalMouseUpMonitor = nil
        }

        let handler = endHandler
        endHandler = nil
        handler?()
    }
}

/// A menu description used by `WidgetContextMenuOverlay`. The overlay is an
/// AppKit right-click-only view, so it wins over context menus buried inside a
/// widget without intercepting the widget's normal clicks, scrolling, or drag.
struct WidgetContextMenuItem {
    let title: String?
    var systemImage: String? = nil
    var isEnabled = true
    var isSelected = false
    var children: [WidgetContextMenuItem] = []
    var action: () -> Void = {}

    static var separator: WidgetContextMenuItem {
        WidgetContextMenuItem(title: nil)
    }
}

struct WidgetContextMenuOverlay: NSViewRepresentable {
    let items: [WidgetContextMenuItem]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> RightClickMenuView {
        let view = RightClickMenuView()
        updateNSView(view, context: context)
        return view
    }

    func updateNSView(_ nsView: RightClickMenuView, context: Context) {
        nsView.menuProvider = { [items, weak coordinator = context.coordinator] in
            coordinator?.makeMenu(from: items) ?? NSMenu()
        }
    }

    final class Coordinator: NSObject {
        func makeMenu(from descriptions: [WidgetContextMenuItem]) -> NSMenu {
            let menu = NSMenu()
            for description in descriptions {
                guard let title = description.title else {
                    menu.addItem(.separator())
                    continue
                }

                let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
                item.isEnabled = description.isEnabled
                item.state = description.isSelected ? .on : .off
                if let systemImage = description.systemImage {
                    item.image = NSImage(
                        systemSymbolName: systemImage,
                        accessibilityDescription: title
                    )
                }

                if description.children.isEmpty {
                    item.target = self
                    item.action = #selector(performAction(_:))
                    item.representedObject = ContextMenuActionBox(
                        description.action
                    )
                } else {
                    item.submenu = makeMenu(from: description.children)
                }
                menu.addItem(item)
            }
            return menu
        }

        @objc private func performAction(_ sender: NSMenuItem) {
            (sender.representedObject as? ContextMenuActionBox)?.action()
        }
    }
}

private final class ContextMenuActionBox: NSObject {
    let action: () -> Void

    init(_ action: @escaping () -> Void) {
        self.action = action
    }
}

final class RightClickMenuView: NSView {
    var menuProvider: () -> NSMenu = { NSMenu() }

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = window?.currentEvent else { return nil }
        if event.type == .rightMouseDown ||
            (event.type == .leftMouseDown && event.modifierFlags.contains(.control)) {
            return self
        }
        return nil
    }

    override func rightMouseDown(with event: NSEvent) {
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
    }

    override func mouseDown(with event: NSEvent) {
        guard event.modifierFlags.contains(.control) else { return }
        NSMenu.popUpContextMenu(menuProvider(), with: event, for: self)
    }
}
