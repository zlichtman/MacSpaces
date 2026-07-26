import AppKit

/// Borderless, non-activating panel hosting the widget dock.
final class DockWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        // The panel is rectangular even though the SwiftUI dock is rounded.
        // A native panel shadow exposes that rectangle at the window bounds.
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .floating
        // Keep the utility available on each Space without presenting it as a
        // window—or drawing over app previews—in Mission Control.
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
    }

    // Text fields (search, notes) need key status without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
