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
        // Ghostty's 819 themes decode off the main thread now, so Appearance's Terminal
        // drawer has them before anyone opens it.
        GhosttyLibrary.shared.load()
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

    /// Runs a system open panel for a Settings control: as a sheet on the Settings window
    /// while it is open, so the panel stays attached to it, else on its own. Either way
    /// MacSpaces and Settings come back to the front, key, once it closes (chosen or
    /// cancelled): MacSpaces has no Dock icon, so when a panel or a privacy prompt closes
    /// macOS can hand the front to another app's window, and Settings seems to have gone.
    func runPanel(_ panel: NSOpenPanel, completion: @escaping (_ chosen: Bool) -> Void) {
        NSApp.activate(ignoringOtherApps: true)
        guard let window, window.isVisible, window.attachedSheet == nil else {
            let response = panel.runModal()
            refront()
            completion(response == .OK)
            return
        }
        window.makeKeyAndOrderFront(nil)
        panel.beginSheetModal(for: window) { [weak self] response in
            self?.refront()
            completion(response == .OK)
        }
    }

    /// `runPanel` for async callers.
    func runPanel(_ panel: NSOpenPanel) async -> Bool {
        await withCheckedContinuation { continuation in
            runPanel(panel) { continuation.resume(returning: $0) }
        }
    }

    /// Brings MacSpaces forward with Settings key when Settings is open, now and once more on
    /// the next turn of the run loop (the system can take the front back as a panel closes).
    func refront() {
        guard let window, window.isVisible else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        DispatchQueue.main.async { [weak window] in
            guard let window, window.isVisible, !NSApp.isActive || !window.isKeyWindow else { return }
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
        }
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
