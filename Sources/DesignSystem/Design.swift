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
        ThemeStore.shared.reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.24, dampingFraction: 0.8)
    }

    /// Opening settles without overshoot so the large surface never appears
    /// to keep rolling once its content is interactive.
    @MainActor
    static var openAnimation: Animation {
        ThemeStore.shared.reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.34, dampingFraction: 0.9)
    }

    /// Closing is quicker and critically damped: the surface tucks back into
    /// the camera housing without bouncing past it.
    @MainActor
    static var closeAnimation: Animation {
        ThemeStore.shared.reduceMotion
            ? .easeOut(duration: 0.14)
            : .spring(response: 0.28, dampingFraction: 0.97)
    }
}

/// Blur, scale and fade together read as depth rather than a flat crossfade.
private struct DepthTransitionEffect: ViewModifier {
    let blur: CGFloat
    let scale: CGFloat
    let opacity: Double
    let anchor: UnitPoint

    func body(content: Content) -> some View {
        content
            .scaleEffect(scale, anchor: anchor)
            .blur(radius: blur)
            .opacity(opacity)
    }
}

extension AnyTransition {
    /// Content entering or leaving the Nook. Reduce Motion keeps a plain fade.
    @MainActor
    static func nookDepth(
        blur: CGFloat = 6,
        scale: CGFloat = 0.94,
        anchor: UnitPoint = .top
    ) -> AnyTransition {
        guard !ThemeStore.shared.reduceMotion else { return .opacity }
        return .modifier(
            active: DepthTransitionEffect(blur: blur, scale: scale, opacity: 0, anchor: anchor),
            identity: DepthTransitionEffect(blur: 0, scale: 1, opacity: 1, anchor: anchor)
        )
    }
}

/// Light trackpad feedback for direct manipulation. Force Touch trackpads
/// only play it while a finger rests on them, so it never fires unexpectedly.
@MainActor
enum Haptics {
    private static var lastPerformedAt = Date.distantPast

    /// Selection, opening and small confirmations.
    static func tap() { perform(.levelChange) }

    /// Files landing in the Tray and removals.
    static func drop() { perform(.generic) }

    private static func perform(_ pattern: NSHapticFeedbackManager.FeedbackPattern) {
        guard ThemeStore.shared.hapticsEnabled else { return }
        // Hover and drag callbacks can fire in bursts; one pulse is enough.
        let now = Date()
        guard now.timeIntervalSince(lastPerformedAt) > 0.12 else { return }
        lastPerformedAt = now
        NSHapticFeedbackManager.defaultPerformer.perform(pattern, performanceTime: .now)
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
        shape
            .fill(tokens.tile.opacity(0.55))
            .overlay {
                shape.strokeBorder(
                    isActive ? tokens.accent.opacity(0.45) : Color.primary.opacity(0.07),
                    lineWidth: 1
                )
            }
            .clipShape(shape)
    }
}

struct PremiumPressButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .opacity(configuration.isPressed ? 0.78 : 1)
            // A quick snap down and a softer settle back feel physical.
            .animation(
                configuration.isPressed
                    ? .spring(response: 0.14, dampingFraction: 0.82)
                    : .spring(response: 0.24, dampingFraction: 0.74),
                value: configuration.isPressed
            )
    }
}

/// Icon controls in the Nook header: a soft capsule appears on hover and the
/// glyph brightens, then presses in with the shared spring.
struct NookIconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        NookIconButtonBody(configuration: configuration)
    }
}

private struct NookIconButtonBody: View {
    let configuration: ButtonStyleConfiguration
    @State private var isHovering = false

    var body: some View {
        configuration.label
            .foregroundStyle(isHovering ? Color.primary : Color.secondary)
            .background {
                Capsule()
                    .fill(Color.white.opacity(isHovering ? 0.1 : 0))
                    .padding(.vertical, 1)
            }
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .animation(
                configuration.isPressed
                    ? .spring(response: 0.14, dampingFraction: 0.82)
                    : .spring(response: 0.24, dampingFraction: 0.74),
                value: configuration.isPressed
            )
            .animation(.spring(response: 0.24, dampingFraction: 0.8), value: isHovering)
            .onHover { isHovering = $0 }
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
