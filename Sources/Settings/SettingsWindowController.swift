import AppKit
import SwiftUI

/// Presents one predictable settings window on the active Space and brings it
/// forward even when invoked from a non-activating Nook or Dock panel.
@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() {
        let initialSize = NSSize(width: 980, height: 680)
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: initialSize),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "MacSpaces"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 880, height: 600)
        window.collectionBehavior = [.moveToActiveSpace, .fullScreenPrimary]
        window.contentView = NSHostingView(rootView: SettingsView())
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(_ destination: SettingsDestination = .notch) {
        guard let window else { return }
        SettingsNavigationModel.shared.selection = destination

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
        let size = NSSize(
            width: min(max(window.frame.width, 880), usable.width - 48),
            height: min(max(window.frame.height, 600), usable.height - 48)
        )
        let origin = NSPoint(
            x: usable.midX - size.width / 2,
            y: usable.midY - size.height / 2
        )
        window.setFrame(NSRect(origin: origin, size: size), display: false)
    }
}
