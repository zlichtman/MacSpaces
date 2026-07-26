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
    private let fileDragActivationSize: () -> CGSize
    private let fileDragEntered: () -> Void
    private let fileDragExited: () -> Void
    private let fileURLsDropped: ([URL]) -> Bool
    private var isFileDragTargeted = false

    required init(rootView: Content) {
        self.interactiveSize = { .zero }
        self.fileDragActivationSize = { .zero }
        self.fileDragEntered = {}
        self.fileDragExited = {}
        self.fileURLsDropped = { _ in false }
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    init(
        rootView: Content,
        interactiveSize: @escaping () -> CGSize,
        fileDragActivationSize: @escaping () -> CGSize,
        fileDragEntered: @escaping () -> Void,
        fileDragExited: @escaping () -> Void,
        fileURLsDropped: @escaping ([URL]) -> Bool
    ) {
        self.interactiveSize = interactiveSize
        self.fileDragActivationSize = fileDragActivationSize
        self.fileDragEntered = fileDragEntered
        self.fileDragExited = fileDragExited
        self.fileURLsDropped = fileURLsDropped
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
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

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateFileDragTarget(sender)
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        updateFileDragTarget(sender)
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        setFileDragTargeted(false)
    }

    override func prepareForDragOperation(_ sender: NSDraggingInfo) -> Bool {
        isFileDragTargeted && isInsideFileDragActivationZone(sender)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        let urls = Self.fileURLs(from: sender.draggingPasteboard)
        guard isFileDragTargeted, !urls.isEmpty else { return false }
        isFileDragTargeted = false
        return fileURLsDropped(urls)
    }

    override func concludeDragOperation(_ sender: NSDraggingInfo?) {
        // A successful drop intentionally leaves Tray open so the user can
        // act on the file they just added. Cancellation is handled by
        // draggingExited(_:), which restores normal hover-close behavior.
    }

    private func updateFileDragTarget(_ sender: NSDraggingInfo) -> NSDragOperation {
        let shouldTarget =
            Self.containsFileURLs(sender.draggingPasteboard)
            && isInsideFileDragActivationZone(sender)
        setFileDragTargeted(shouldTarget)
        return shouldTarget ? .copy : []
    }

    private func setFileDragTargeted(_ targeted: Bool) {
        guard isFileDragTargeted != targeted else { return }
        isFileDragTargeted = targeted
        if targeted {
            fileDragEntered()
        } else {
            fileDragExited()
        }
    }

    private func isInsideFileDragActivationZone(_ sender: NSDraggingInfo) -> Bool {
        let size = fileDragActivationSize()
        let activationFrame = NSRect(
            x: bounds.midX - size.width / 2,
            y: bounds.maxY - size.height,
            width: size.width,
            height: size.height
        )
        return activationFrame.contains(convert(sender.draggingLocation, from: nil))
    }

    private static func containsFileURLs(_ pasteboard: NSPasteboard) -> Bool {
        pasteboard.canReadObject(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        )
    }

    private static func fileURLs(from pasteboard: NSPasteboard) -> [URL] {
        (pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) ?? []).compactMap { object in
            guard let url = object as? NSURL else { return nil }
            return url as URL
        }
    }
}
