import SwiftUI
import AppKit

enum Design {
    static let nookRadius: CGFloat = 22
    static let nookMaximumWidth: CGFloat = 860
    static let nookHeight: CGFloat = 250
    static let tileRadius: CGFloat = 16
    static let surfaceRadius: CGFloat = 24
    static let controlRadius: CGFloat = 10
    static let smallRadius: CGFloat = 8

    static let tileSpacing: CGFloat = 8
    static let surfacePadding: CGFloat = 10

    static let hairline = Color.white.opacity(0.12)
    static let subtleShadow = Color.black.opacity(0.24)

    /// Slows every motion token for frame-by-frame demo capture. Always 1 in
    /// the app; the website demo helper raises it so each 60 fps frame can
    /// be rendered before the animation moves on.
    @MainActor static var demoTimeScale: Double = 1

    /// The time the clocks show: now in the app. The website tour pins it, since its slowed
    /// capture takes many real minutes and the clocks would tick through them.
    @MainActor static var demoClockDate: Date?
    @MainActor static func clockDate(_ date: Date) -> Date { demoClockDate ?? date }

    @MainActor
    static func timed(_ animation: Animation) -> Animation {
        demoTimeScale == 1 ? animation : animation.speed(1 / demoTimeScale)
    }

    @MainActor
    static func spring() -> Animation {
        timed(ThemeStore.shared.reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.30, dampingFraction: 0.88))
    }

    @MainActor
    static var hoverAnimation: Animation {
        timed(ThemeStore.shared.reduceMotion ? .linear(duration: 0.01) : .spring(response: 0.24, dampingFraction: 0.8))
    }

    /// Opening settles without overshoot so the large surface never appears
    /// to keep rolling once its content is interactive.
    @MainActor
    static var openAnimation: Animation {
        timed(ThemeStore.shared.reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.34, dampingFraction: 0.9))
    }

    /// Tiles and the dock settle with a little give as they fall out of the
    /// notch, which is what makes the open read as a drop.
    @MainActor
    static var dropAnimation: Animation {
        timed(ThemeStore.shared.reduceMotion
            ? .easeOut(duration: 0.16)
            : .spring(response: 0.42, dampingFraction: 0.72))
    }

    /// Closing is quicker and critically damped: the surface tucks back into
    /// the camera housing without bouncing past it.
    @MainActor
    static var closeAnimation: Animation {
        timed(ThemeStore.shared.reduceMotion
            ? .easeOut(duration: 0.14)
            : .spring(response: 0.28, dampingFraction: 0.97))
    }

    // The open surface's two directions, staged so it drops from the camera first and
    // then widens (and on closing draws in, then rises): it never sweeps sideways over
    // the bubbles and lanes beside the camera while they're still leaving or arriving.
    // Under Reduce Motion both are the plain fade-quick ease, together.

    /// Opening, downward: a touch quicker than `openAnimation`.
    @MainActor
    static var openDownAnimation: Animation {
        timed(ThemeStore.shared.reduceMotion ? .easeOut(duration: 0.16) : .spring(response: 0.3, dampingFraction: 0.9))
    }

    /// Opening, outward: starts once the drop is under way and the side activities have
    /// gone (the bubbles tuck under the camera first, `bubbleTuckDuration`).
    @MainActor
    static func openOutAnimation(afterBubbles: Bool = false) -> Animation {
        timed(ThemeStore.shared.reduceMotion ? .easeOut(duration: 0.16)
              : .spring(response: 0.36, dampingFraction: 0.9).delay(afterBubbles ? bubbleTuckDuration : openOutDelay))
    }
    static let openOutDelay = 0.07

    /// The bubbles tucking under the camera as the Nook opens: quicker than
    /// an activity leaving (`laneAnimation`), so the panel can widen soon after.
    static let bubbleTuckDuration: TimeInterval = 0.16
    @MainActor
    static var bubbleTuckAnimation: Animation {
        timed(ThemeStore.shared.reduceMotion ? .easeOut(duration: 0.16)
              : .timingCurve(0.4, 0, 0.7, 1, duration: bubbleTuckDuration))
    }

    /// Closing, inward first.
    @MainActor
    static var closeInAnimation: Animation { closeAnimation }

    /// Closing, upward: once the panel has narrowed toward the camera.
    @MainActor
    static var closeUpAnimation: Animation {
        timed(ThemeStore.shared.reduceMotion ? .easeOut(duration: 0.14)
              : .spring(response: 0.28, dampingFraction: 0.97).delay(0.06))
    }

    // A closed activity arriving beside the camera, or leaving: the bubbles and the agent
    // bubble all move on this one curve, so the row
    // moves as one. Leaving is arriving run backwards (the mirrored curve): out quickly
    // from under the camera and settling; back in gathering speed and tucking under it.
    // The agent bubble's panel uses the same duration and control points in Core Animation.
    static let laneDuration: TimeInterval = 0.34
    static let laneArriveCurve: (Double, Double, Double, Double) = (0.2, 0.8, 0.3, 1)
    static var laneLeaveCurve: (Double, Double, Double, Double) {
        let (x1, y1, x2, y2) = laneArriveCurve
        return (1 - x2, 1 - y2, 1 - x1, 1 - y1)
    }

    /// The closed row's motion: an activity arriving (or the row growing) or leaving.
    /// Under Reduce Motion the bubbles fade instead (see `CollapsedNotchContent`).
    @MainActor
    static func laneAnimation(arriving: Bool) -> Animation {
        let (x1, y1, x2, y2) = arriving ? laneArriveCurve : laneLeaveCurve
        return timed(ThemeStore.shared.reduceMotion ? .easeOut(duration: 0.16)
                     : .timingCurve(x1, y1, x2, y2, duration: laneDuration))
    }

    /// The same curve for the agent bubble's panel.
    static func laneTimingFunction(arriving: Bool) -> CAMediaTimingFunction {
        let (x1, y1, x2, y2) = arriving ? laneArriveCurve : laneLeaveCurve
        return CAMediaTimingFunction(controlPoints: Float(x1), Float(y1), Float(x2), Float(y2))
    }

    /// How long after closing the side activities and the agent bubble come back out,
    /// so they arrive beside a settled notch: as an animation delay (inside `timed`)…
    @MainActor
    static var closeSettleDelay: TimeInterval { ThemeStore.shared.reduceMotion ? 0 : 0.26 }
    /// …and in clock time, for timers.
    @MainActor
    static var closeSettle: TimeInterval { closeSettleDelay * demoTimeScale }
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

/// A widget's edge. Widgets sit straight on the Nook (owner, 2.100: no blocks), so it's
/// invisible except while the tile is being moved, when an accent outline shows.
struct PremiumWidgetChrome: View {
    static let radius: CGFloat = 16
    let tokens: ThemeTokens
    let isActive: Bool

    var radius: CGFloat { Self.radius }

    var body: some View {
        RoundedRectangle(cornerRadius: radius, style: .continuous)
            .strokeBorder(tokens.accent.opacity(isActive ? 0.45 : 0), lineWidth: 1)
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

/// Hover feedback for buttons: a soft circle behind a plain glyph, or a slight
/// lift for a filled button, so the pointer always shows what it will press.
struct HoverHighlight: ViewModifier {
    var filled = false
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .background(Circle().fill(Color.primary.opacity(!filled && hovering ? 0.1 : 0)).padding(-4))
            .brightness(filled && hovering ? 0.06 : 0)
            .onHover { hovering = $0 }
            .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

extension View {
    func hoverHighlight(filled: Bool = false) -> some View { modifier(HoverHighlight(filled: filled)) }
}

/// A popover from the Nook, in the theme: its surface, ink and accent, never the system's grey.
/// The fill runs past the content so it covers the arrow and the corners too.
extension View {
    func nookPopover<Content: View>(isPresented: Binding<Bool>, arrowEdge: Edge = .top,
                                    @ViewBuilder content: @escaping () -> Content) -> some View {
        popover(isPresented: isPresented, arrowEdge: arrowEdge) { NookPopoverContent(content: content) }
    }
}

/// A text field in the Nook's theme: the chips' fill and corners, the accent edge while it has focus.
struct NookTextField: View {
    let placeholder: String
    @Binding var text: String
    var height: CGFloat = 26
    var focusOnAppear = false
    @ObservedObject private var theme = ThemeStore.shared
    @FocusState private var focused: Bool

    init(_ placeholder: String, text: Binding<String>, height: CGFloat = 26, focusOnAppear: Bool = false) {
        self.placeholder = placeholder
        self._text = text
        self.height = height
        self.focusOnAppear = focusOnAppear
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
        TextField(placeholder, text: $text)
            .textFieldStyle(.plain)
            .font(.system(size: 12))
            .focused($focused)
            .padding(.horizontal, 8)
            .frame(height: height)
            .background(Color.primary.opacity(0.09), in: shape)
            .overlay { shape.strokeBorder(theme.notch.accent, lineWidth: 1.5).opacity(focused ? 1 : 0) }
            .onAppear { if focusOnAppear { focused = true } }
    }
}

/// A click menu in the Nook's language, never the system's: a popover in the theme with rows
/// that highlight as the chips do. It's a `Button` underneath, so give it a `.buttonStyle` as you
/// would one. Right-click menus stay the system's.
struct NookMenu<Content: View, MenuLabel: View>: View {
    var arrowEdge: Edge = .bottom
    @ViewBuilder let content: () -> Content
    @ViewBuilder let label: () -> MenuLabel
    @State private var isOpen = false

    init(arrowEdge: Edge = .bottom, @ViewBuilder content: @escaping () -> Content, @ViewBuilder label: @escaping () -> MenuLabel) {
        self.arrowEdge = arrowEdge
        self.content = content
        self.label = label
    }

    var body: some View {
        Button { isOpen.toggle() } label: { label() }
            .nookPopover(isPresented: $isOpen, arrowEdge: arrowEdge) {
                VStack(alignment: .leading, spacing: 2) { content() }
                    .padding(6)
                    .frame(minWidth: 170, alignment: .leading)
                    .fixedSize()
                    .environment(\.nookMenuDismiss, NookMenuDismiss { isOpen = false })
            }
    }
}

/// Closes the menu a row is in; a row outside a menu just acts.
struct NookMenuDismiss {
    var close: () -> Void = {}
}

private struct NookMenuDismissKey: EnvironmentKey {
    static let defaultValue = NookMenuDismiss()
}

extension EnvironmentValues {
    var nookMenuDismiss: NookMenuDismiss {
        get { self[NookMenuDismissKey.self] }
        set { self[NookMenuDismissKey.self] = newValue }
    }
}

/// One choice in a `NookMenu`. `selected` true shows the tick; `destructive` reads red.
struct NookMenuRow: View {
    let title: String
    var systemImage: String?
    var selected = false
    var destructive = false
    let action: () -> Void
    @Environment(\.nookMenuDismiss) private var dismiss
    @Environment(\.isEnabled) private var isEnabled
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false

    init(_ title: String, systemImage: String? = nil, selected: Bool = false, destructive: Bool = false, action: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.selected = selected
        self.destructive = destructive
        self.action = action
    }

    var body: some View {
        Button {
            dismiss.close()
            // After closing, so what it opens isn't closed with it.
            DispatchQueue.main.async(execute: action)
        } label: {
            NookMenuRowLabel(title: title, systemImage: systemImage, destructive: destructive, hovering: hovering && isEnabled) {
                if selected {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.notch.accent)
                }
            }
            .opacity(isEnabled ? 1 : 0.45)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// An on or off choice in a `NookMenu`, which stays open as it's changed.
struct NookMenuToggle: View {
    let title: String
    @Binding var isOn: Bool
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hovering = false

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        self._isOn = isOn
    }

    var body: some View {
        Button { isOn.toggle() } label: {
            NookMenuRowLabel(title: title, systemImage: nil, destructive: false, hovering: hovering) {
                if isOn {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.notch.accent)
                }
            }
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityValue(isOn ? "On" : "Off")
    }
}

private struct NookMenuRowLabel<Trailing: View>: View {
    let title: String
    let systemImage: String?
    let destructive: Bool
    let hovering: Bool
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 7) {
            if let systemImage {
                Image(systemName: systemImage).font(.system(size: 11, weight: .medium)).frame(width: 14)
            }
            Text(title).font(.system(size: 12, weight: .medium)).lineLimit(1)
            Spacer(minLength: 14)
            trailing()
        }
        .foregroundStyle(destructive ? Color.red : Color.primary)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(Color.primary.opacity(hovering ? 0.09 : 0), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// A hairline between groups of rows.
struct NookMenuDivider: View {
    var body: some View {
        Rectangle().fill(Color.primary.opacity(0.1)).frame(height: 1).padding(.horizontal, 6).padding(.vertical, 3)
    }
}

/// A small label over a group of rows, standing in for a submenu.
struct NookMenuHeading: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            .padding(.horizontal, 8).padding(.top, 4).padding(.bottom, 1)
    }
}

private struct NookPopoverContent<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        content()
            .foregroundStyle(theme.nookForeground)
            .tint(theme.notch.accent)
            .colorScheme(theme.notch.colorScheme)
            .background(theme.notch.surface.padding(-80))
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

/// Page work is cancellable when navigation changes before the shell has opened.
extension View {
    func nookAfterOpening(perform action: @escaping @MainActor () -> Void) -> some View {
        task {
            do { try await Task.sleep(nanoseconds: 420_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            action()
        }
    }
}
