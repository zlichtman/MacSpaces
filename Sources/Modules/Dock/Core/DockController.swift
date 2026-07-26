import AppKit
import SwiftUI
import Combine
import QuartzCore

/// Owns the dock windows (one per screen when enabled): sizes them to the
/// configured widgets, pins them to the chosen screen edge, and auto-hides.
@MainActor
final class DockController {
    private struct ManagedWindow {
        let window: DockWindow
        let screen: NSScreen
        var isHidden = false
        var hideWorkItem: DispatchWorkItem?
    }

    private let store: DockStore
    private var managed: [ManagedWindow] = []
    private var cancellables: Set<AnyCancellable> = []
    private var mouseMonitor: Any?
    private var lastMouseEvaluation: CFTimeInterval = 0
    private var launchGraceUntil: CFTimeInterval = 0

    static let outerPadding: CGFloat = 7
    static let tileSpacing: CGFloat = 6

    init(store: DockStore) {
        self.store = store
    }

    func start() {
        rebuildWindows()
        DockWindowPreviewController.shared.start()

        // Any config change re-lays-out; display-set changes rebuild windows.
        store.objectWillChange
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.store.isInteractiveReorderActive == false else { return }
                self?.reconcile()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(400), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildWindows() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.activeSpaceDidChangeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.ensureVisible() }
            .store(in: &cancellables)

        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didWakeNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildWindows() }
            .store(in: &cancellables)

        reconcileMouseMonitor()
    }

    func stop() {
        store.cancelInteractiveReorder()
        cancellables.removeAll()
        DockWindowPreviewController.shared.stop()
        managed.forEach { $0.hideWorkItem?.cancel() }
        removeMouseMonitor()
        managed.forEach { $0.window.close() }
        managed.removeAll()
    }

    private var targetScreens: [NSScreen] {
        DisplayTargeting.screens(
            mode: store.displayMode,
            selectedIDs: store.selectedDisplayIDs,
            preferBuiltIn: false
        )
    }

    private func reconcile() {
        let currentScreens = managed.map(\.screen)
        if currentScreens != targetScreens {
            rebuildWindows()
        } else {
            applyLayout()
            reconcileMouseMonitor()
        }
    }

    private func rebuildWindows() {
        store.cancelInteractiveReorder()
        managed.forEach { $0.hideWorkItem?.cancel() }
        managed.forEach { $0.window.close() }
        managed.removeAll()
        launchGraceUntil = CACurrentMediaTime() + 1.25

        for screen in targetScreens {
            let window = DockWindow(contentRect: .zero)
            let hostingView = NSHostingView(rootView: DockContainerView(store: store))
            hostingView.wantsLayer = true
            hostingView.layer?.backgroundColor = NSColor.clear.cgColor
            hostingView.layer?.isOpaque = false
            window.contentView = hostingView
            managed.append(
                ManagedWindow(
                    window: window,
                    screen: screen,
                    isHidden: false,
                    hideWorkItem: nil
                )
            )
        }
        applyLayout()
        reconcileMouseMonitor()
    }

    private func ensureVisible() {
        launchGraceUntil = CACurrentMediaTime() + 1.0
        for index in managed.indices {
            managed[index].hideWorkItem?.cancel()
            managed[index].hideWorkItem = nil
            managed[index].isHidden = false
            managed[index].window.ignoresMouseEvents = false
        }
        applyLayout()
    }

    // MARK: - Layout

    /// Length of the dock along its main axis, derived deterministically from
    /// the widget list so windows can be sized without SwiftUI feedback.
    private var mainAxisLength: CGFloat {
        let tile = CGFloat(store.tileSize)
        if store.widgets.isEmpty {
            return 76 + 2 * Self.outerPadding
        }
        let layoutItems = store.widgets.dockLayoutItems(
            vertical: store.effectivePosition.isVertical
        )
        let lengths = layoutItems.map { item in
            item.axisLength(tile: tile, spacing: Self.tileSpacing)
        }
        let content = lengths.reduce(0, +)
            + CGFloat(max(0, layoutItems.count - 1)) * Self.tileSpacing
        return content + 2 * Self.outerPadding
    }

    private var crossAxisLength: CGFloat {
        let contentWidth = store.effectivePosition.isVertical
            ? CGFloat(store.sideDockWidth)
            : CGFloat(store.tileSize)
        return contentWidth + 2 * Self.outerPadding
    }

    private func applyLayout() {
        for entry in managed {
            applyLayout(to: entry.window, on: entry.screen, isHidden: entry.isHidden)
        }
    }

    private func applyLayout(
        to window: DockWindow,
        on screen: NSScreen,
        isHidden: Bool,
        animated: Bool = false
    ) {
        guard store.isDockVisible else {
            window.orderOut(nil)
            return
        }

        let offset = CGFloat(store.edgeOffset)
        let visible = screen.visibleFrame
        var frame = NSRect.zero

        let position = store.effectivePosition
        switch position {
        case .bottom:
            frame.size = NSSize(width: min(mainAxisLength, visible.width * 0.92), height: crossAxisLength)
            frame.origin = NSPoint(x: visible.midX - frame.width / 2,
                                   y: visible.minY + offset)
        case .left:
            frame.size = NSSize(width: crossAxisLength, height: min(mainAxisLength, visible.height * 0.90))
            frame.origin = NSPoint(x: visible.minX + offset,
                                   y: visible.midY - frame.height / 2)
        case .right:
            frame.size = NSSize(width: crossAxisLength, height: min(mainAxisLength, visible.height * 0.90))
            frame.origin = NSPoint(x: visible.maxX - frame.width - offset,
                                   y: visible.midY - frame.height / 2)
        }

        if store.shouldAutoHide && isHidden {
            switch position {
            case .bottom: frame.origin.y -= 10
            case .left: frame.origin.x -= 10
            case .right: frame.origin.x += 10
            }
        }
        let targetAlpha: CGFloat = (store.shouldAutoHide && isHidden) ? 0 : 1
        let ignoresMouse = store.shouldAutoHide && isHidden
        window.orderFrontRegardless()

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = isHidden ? 0.16 : 0.22
                context.timingFunction = CAMediaTimingFunction(
                    name: isHidden ? .easeIn : .easeOut
                )
                window.animator().setFrame(frame, display: true)
                window.animator().alphaValue = targetAlpha
            } completionHandler: { [weak self] in
                Task { @MainActor in
                    // Re-derive from live state instead of the value captured
                    // when the animation started. A reveal that interrupts a
                    // hide used to be overwritten by the stale hide completion,
                    // leaving a fully visible dock that ignored every click.
                    guard let self else { return }
                    window.ignoresMouseEvents = self.shouldIgnoreMouse(for: window)
                }
            }
        } else {
            window.setFrame(frame, display: true)
            window.alphaValue = targetAlpha
            window.ignoresMouseEvents = ignoresMouse
        }
    }

    /// Whether a window should currently swallow or pass through the pointer,
    /// read from the managed entry rather than from any in-flight animation.
    private func shouldIgnoreMouse(for window: NSWindow) -> Bool {
        guard store.shouldAutoHide,
              let entry = managed.first(where: { $0.window === window }) else { return false }
        return entry.isHidden
    }

    // MARK: - Auto-hide

    private func reconcileMouseMonitor() {
        let needed = store.shouldAutoHide && store.isDockVisible && !store.widgets.isEmpty
        if needed, mouseMonitor == nil {
            mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved]) {
                [weak self] _ in
                self?.mouseMovedEvent()
            }
        } else if !needed {
            removeMouseMonitor()
        }
    }

    private func removeMouseMonitor() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
    }

    private func mouseMovedEvent() {
        let now = CACurrentMediaTime()
        guard now - lastMouseEvaluation >= 1.0 / 45.0 else { return }
        lastMouseEvaluation = now
        handleMouseMoved()
    }

    private func handleMouseMoved() {
        guard store.shouldAutoHide, store.isDockVisible, !store.widgets.isEmpty else { return }
        let mouse = NSEvent.mouseLocation

        for index in managed.indices {
            let entry = managed[index]
            let revealZone = entry.window.frame.insetBy(dx: -40, dy: -40)

            if entry.isHidden {
                let screenFrame = entry.screen.frame
                let nearEdge: Bool
                switch store.effectivePosition {
                case .bottom:
                    nearEdge = screenFrame.contains(mouse) && mouse.y <= screenFrame.minY + 4
                case .left:
                    nearEdge = screenFrame.contains(mouse) && mouse.x <= screenFrame.minX + 4
                case .right:
                    nearEdge = screenFrame.contains(mouse) && mouse.x >= screenFrame.maxX - 4
                }
                if nearEdge {
                    managed[index].hideWorkItem?.cancel()
                    managed[index].hideWorkItem = nil
                    setHidden(false, at: index)
                }
            } else if CACurrentMediaTime() < launchGraceUntil {
                managed[index].hideWorkItem?.cancel()
                managed[index].hideWorkItem = nil
            } else if !revealZone.contains(mouse) {
                scheduleHide(at: index)
            } else {
                managed[index].hideWorkItem?.cancel()
                managed[index].hideWorkItem = nil
            }
        }
    }

    private func scheduleHide(at index: Int) {
        guard managed.indices.contains(index), managed[index].hideWorkItem == nil else { return }
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.managed.indices.contains(index) else { return }
            self.managed[index].hideWorkItem = nil
            let mouse = NSEvent.mouseLocation
            let revealZone = self.managed[index].window.frame.insetBy(dx: -44, dy: -44)
            if !revealZone.contains(mouse) {
                self.setHidden(true, at: index)
            }
        }
        managed[index].hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + store.hideDelay, execute: work)
    }

    private func setHidden(_ hidden: Bool, at index: Int) {
        guard managed[index].isHidden != hidden else { return }
        managed[index].isHidden = hidden
        let window = managed[index].window
        // Keep the revealed Dock interactive immediately. On hide, defer
        // ignoring mouse events until the slide/fade finishes.
        if !hidden {
            window.ignoresMouseEvents = false
        }
        applyLayout(
            to: window,
            on: managed[index].screen,
            isHidden: hidden,
            animated: true
        )
    }
}
