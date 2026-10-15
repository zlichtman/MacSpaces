import AppKit
import SwiftUI

/// Presents one predictable settings window on the active Space and brings it
/// forward even when invoked from a non-activating Nook panel.
@MainActor
final class SettingsWindowController: NSWindowController, NSWindowDelegate {
    static let shared = SettingsWindowController()
    /// Settings can grow (to see more of a long list) but never shrinks below
    /// the size its layout is designed for: a squashed window (dragged, tiled
    /// or restored small) clipped its pages.
    static let size = NSSize(width: 980, height: 680)

    private init() {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MacSpaces"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.contentMinSize = Self.size
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenNone]
        let host = NSHostingView(rootView: SettingsView())
        // Window minSize and user resizing own geometry, not SwiftUI's animated
        // ideal-size propagation during a palette or destination change.
        host.sizingOptions = []
        host.autoresizingMask = [.width, .height]
        window.contentView = host
        super.init(window: window)
        window.delegate = self
    }

    /// Window tiling and restoration set the frame directly, below the minimum; grow it back.
    func windowDidResize(_ notification: Notification) {
        guard let window else { return }
        let minimum = fittedSize(on: window.screen)
        guard window.frame.width < minimum.width - 0.5 || window.frame.height < minimum.height - 0.5 else { return }
        var frame = window.frame
        let size = NSSize(width: max(frame.width, minimum.width), height: max(frame.height, minimum.height))
        frame.origin.y += frame.height - size.height
        frame.size = size
        window.setFrame(frame, display: true)
    }

    /// The smallest size, smaller only on a screen too short to hold it.
    private func fittedSize(on screen: NSScreen?) -> NSSize {
        guard let window else { return Self.size }
        let frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: Self.size)).size
        guard let usable = screen?.visibleFrame else { return frame }
        return NSSize(width: min(frame.width, usable.width), height: min(frame.height, usable.height))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ destination: SettingsDestination? = nil) {
        guard let window else { return }
        if let destination { SettingsNavigationModel.shared.open(destination) }

        if !window.isVisible {
            positionOnPointerScreen(window)
        }

        NSRunningApplication.current.activate(options: [.activateAllWindows])
        NSApp.activate(ignoringOtherApps: true)
        showWindow(nil)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func positionOnPointerScreen(_ window: NSWindow) {
        let pointer = NSEvent.mouseLocation
        let screen = NSScreen.screens.first(where: { NSMouseInRect(pointer, $0.frame, false) })
            ?? NSScreen.main
            ?? NSScreen.screens.first
        guard let screen else {
            window.center()
            return
        }

        let usable = screen.visibleFrame
        let size = fittedSize(on: screen)
        let origin = NSPoint(
            x: usable.midX - size.width / 2,
            y: usable.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
