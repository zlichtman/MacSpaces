import AppKit
import SwiftUI

/// Borderless, non-activating panel that floats above the menu bar and hosts the notch UI.
final class NotchWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(contentRect: contentRect,
                   styleMask: [.borderless, .nonactivatingPanel],
                   backing: .buffered,
                   defer: false)

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        isMovable = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        level = .statusBar
        animationBehavior = .none
        // Transient auxiliary panels follow every desktop but disappear from
        // Mission Control/Exposé instead of covering window previews.
        collectionBehavior = [.canJoinAllSpaces, .transient, .fullScreenAuxiliary, .ignoresCycle]
    }

    // Allow the panel to receive keyboard focus for the shelf without activating the app.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

/// The panel needs transparent room for the Nook shadow, but that room must
/// not become an invisible mouse trigger over the app underneath.
final class NotchHostingView<Content: View>: NSHostingView<Content> {
    private let interactiveSize: () -> CGSize

    required init(rootView: Content) {
        self.interactiveSize = { .zero }
        super.init(rootView: rootView)
    }

    init(rootView: Content, interactiveSize: @escaping () -> CGSize) {
        self.interactiveSize = interactiveSize
        super.init(rootView: rootView)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        let size = interactiveSize()
        let interactiveFrame = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        )
        guard interactiveFrame.contains(point) else { return nil }
        return super.hitTest(point)
    }
}
