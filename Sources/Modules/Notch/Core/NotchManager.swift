import AppKit
import SwiftUI
import Combine

/// Whether any Nook is open, so the menu bar offers Close Nook instead of Open Nook:
/// a Nook opened from the menu or keyboard stays pinned open, and the dock's Close
/// button can be hidden.
@MainActor
final class NookPresence: ObservableObject {
    static let shared = NookPresence()
    @Published fileprivate(set) var isOpen = false
}

/// Creates and maintains one notch window per screen, rebuilding when displays change.
@MainActor
final class NotchManager {
    private struct Entry {
        let window: NotchWindow
        let viewModel: NotchViewModel
        let screen: NSScreen
    }

    private var entries: [Entry] = []
    private var keyboardMonitor: Any?
    /// The running Nook, for the agent pop-out beside it.
    private(set) static weak var active: NotchManager?
    private var cancellables: Set<AnyCancellable> = []
    private var presenceWatchers: Set<AnyCancellable> = []
    private var isDisplayTransitionActive = false

    let settings = NookSettings.shared
    let shelf = ShelfStore.shared
    let nowPlaying = AppServices.shared.nowPlaying
    let powerMonitor = AppServices.shared.powerMonitor
    let timerService = AppServices.shared.timerService
    let bluetoothMonitor = AppServices.shared.bluetooth
    let systemActivityMonitor = AppServices.shared.systemActivity
    let teleprompter = AppServices.shared.teleprompter

    /// The Nook the agent pop-out belongs to: the notched display's, or the first.
    private var agentEntry: Entry? { entries.first(where: { $0.viewModel.geometry.isHardwareNotch }) ?? entries.first }

    /// Where the agent pop-out goes: beside that closed notch, on its screen, and
    /// whether that Nook is open (the pop-out steps aside then).
    func agentAnchor() -> (notch: NSRect, screen: NSRect, nookOpen: Bool)? {
        guard let entry = agentEntry, let notch = entry.viewModel.closedNotchFrame else { return nil }
        return (notch, entry.screen.frame, entry.viewModel.state == .expanded)
    }

    /// Clicking the agent pop-out: the Terminal page's Agents tab, with that session
    /// outlined. It isn't pinned (3.25): pinned, it stayed open for good when the dock's
    /// pin and close buttons were hidden. It closes like a hovered Nook instead.
    func openAgents(session: String?) {
        guard let entry = agentEntry else { return }
        UserDefaults.standard.set(CodingPanel.Tab.agents.rawValue, forKey: "terminal.tab")
        AgentActivityMonitor.shared.spotlight = session
        entry.viewModel.expand(to: .terminal)
        entry.window.makeKeyAndOrderFront(nil)
        closeWhenPointerLeaves(entry, after: 2)
    }

    /// A Nook opened by a click rather than a hover: once the pointer has had a moment
    /// to reach it, it closes if the pointer is off it. Once hover tracking sees the
    /// pointer inside, leaving closes it as usual; a pin keeps it open.
    private func closeWhenPointerLeaves(_ entry: Entry, after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            let model = entry.viewModel
            guard let self, model.state == .expanded, !model.isPinned, !model.isPointerInside else { return }
            if entry.window.frame.contains(NSEvent.mouseLocation) {
                self.closeWhenPointerLeaves(entry, after: 0.3)
            } else {
                model.collapse()
            }
        }
    }

    /// Explicit keyboard navigation opens and pins a page until it is closed.
    func openForKeyboard(_ tab: NotchTab) {
        guard let entry = entries.first(where: { $0.screen.frame.contains(NSEvent.mouseLocation) }) ?? entries.first else { return }
        isHiddenForApp = false
        entry.viewModel.isPinned = true
        entry.viewModel.expand(to: tab)
        entry.window.makeKeyAndOrderFront(nil)
    }

    func beginWidgetLibraryDrag() {
        WidgetDragSession.shared.finish()
        guard !isHiddenForApp,
              let entry = entries.first(where: { $0.viewModel.geometry.isHardwareNotch }) ?? entries.first else { return }
        let model = entry.viewModel
        let wasPinned = model.isPinned
        model.isPinned = true
        model.pageAnchor = .center
        model.expand(to: .nook)
        entry.window.orderFrontRegardless()
        WidgetDragSession.shared.begin { [weak model] in
            guard let model, !wasPinned, model.isPinned else { return }
            model.togglePin()
        }
    }

    func closeAll() {
        for entry in entries where entry.viewModel.state == .expanded { entry.viewModel.collapse() }
    }

    private func updatePresence() {
        let open = entries.contains { $0.viewModel.state == .expanded }
        if NookPresence.shared.isOpen != open { NookPresence.shared.isOpen = open }
    }

    func closeDictation() {
        for entry in entries where entry.viewModel.selectedTab == .dictation { entry.viewModel.collapse() }
    }

    func start() {
        Self.active = self
        rebuildWindows()
        if keyboardMonitor == nil {
            keyboardMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                guard event.keyCode == 53, let window = event.window as? NotchWindow,
                      let model = window.owner as? NotchViewModel, model.isPinned,
                      model.selectedWidget == nil, !(window.firstResponder is NSTextInputClient) else { return event }
                model.collapse()
                return nil
            }
        }

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .sink { [weak self] _ in
                self?.suspendWindowsForDisplayTransition()
            }
            .store(in: &cancellables)

        NotificationCenter.default
            .publisher(for: NSApplication.didChangeScreenParametersNotification)
            .debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.rebuildWindows()
            }
            .store(in: &cancellables)

        settings.$displayMode
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildWindows() }
            .store(in: &cancellables)

        settings.$selectedDisplayIDs
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.rebuildWindows() }
            .store(in: &cancellables)

        // The look is part of each window's geometry (Settings → Activities → Look).
        settings.$notchLook.removeDuplicates().dropFirst()
            .map { _ in () }
            .merge(with: settings.$notchlessHint.removeDuplicates().dropFirst().map { _ in () })
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.rebuildWindows() }
            .store(in: &cancellables)

        // Prepare the current scene at launch/theme change, while the Nook is closed.
        ThemeStore.shared.$family
            .sink { family in MotifImages.shared.prepare(family.motif) }
            .store(in: &cancellables)

        // New screenshots join the Tray (when turned on) and show beside the notch.
        ScreenshotWatcher.shared.onCapture = { [weak self] url in self?.shelf.add(url: url) }
        ScreenshotWatcher.shared.start()

        // In front of apps the user chose (games, presentations), the Nook steps away.
        NSWorkspace.shared.notificationCenter
            .publisher(for: NSWorkspace.didActivateApplicationNotification)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.applyHiddenApps() }
            .store(in: &cancellables)
        settings.$hiddenInApps
            .dropFirst()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.applyHiddenApps() } }
            .store(in: &cancellables)

        settings.objectWillChange
            .debounce(for: .milliseconds(40), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.settings.isInteractiveReorderActive == false,
                      self?.isDisplayTransitionActive == false else { return }
                self?.updateWindowFrames()
            }
            .store(in: &cancellables)
    }

    func stop() {
        if let keyboardMonitor { NSEvent.removeMonitor(keyboardMonitor); self.keyboardMonitor = nil }
        settings.cancelInteractiveReorder()
        cancellables.removeAll()
        entries.forEach { $0.viewModel.endAppPresentation(); $0.window.close() }
        entries.removeAll()
        presenceWatchers.removeAll()
        updatePresence()
        isDisplayTransitionActive = false
    }

    /// macOS briefly reports intermediate global coordinates while displays
    /// are being attached, detached, mirrored, or rearranged. Keeping the
    /// status-level panel visible during that interval lets AppKit visibly
    /// migrate it across the desktop. Hide it immediately and rebuild only
    /// after the display topology has settled.
    private func suspendWindowsForDisplayTransition() {
        guard !isDisplayTransitionActive else { return }
        isDisplayTransitionActive = true
        settings.cancelInteractiveReorder()
        entries.forEach { $0.viewModel.endAppPresentation(); $0.window.orderOut(nil) }
    }

    private func rebuildWindows() {
        settings.cancelInteractiveReorder()
        entries.forEach { $0.viewModel.endAppPresentation(); $0.window.close() }
        entries.removeAll()
        presenceWatchers.removeAll()

        let screens = DisplayTargeting.screens(
            mode: settings.displayMode,
            selectedIDs: settings.selectedDisplayIDs,
            preferBuiltIn: true
        )

        // Decided before any window is ordered front: an excluded app may already be
        // frontmost at launch or after a display change.
        isHiddenForApp = HiddenApps.hides(frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                          hiddenIn: settings.hiddenInApps)
        AgentPopout.shared.setHiddenForApp(isHiddenForApp)
        for screen in screens {
            let entry = makeWindow(for: screen)
            entries.append(entry)
            // `state` publishes before it changes, so read it on the next turn.
            entry.viewModel.$state
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.updatePresence(); AgentPopout.shared.refresh() }
                .store(in: &presenceWatchers)
        }
        updatePresence()
        isDisplayTransitionActive = false
        AgentPopout.shared.refresh()
    }

    private func makeWindow(for screen: NSScreen) -> Entry {
        let geometry = NotchGeometry.detect(on: screen)
        let viewModel = NotchViewModel(geometry: geometry,
                                       availableWidth: screen.frame.width,
                                       settings: settings,
                                       shelf: shelf,
                                       nowPlaying: nowPlaying,
                                       powerMonitor: powerMonitor,
                                       timerService: timerService,
                                       bluetoothMonitor: bluetoothMonitor,
                                       systemActivityMonitor: systemActivityMonitor,
                                       teleprompter: teleprompter)
        viewModel.screenFrame = screen.frame

        let frame = windowFrame(for: viewModel, on: screen)

        let window = NotchWindow(contentRect: frame)
        window.owner = viewModel
        let root = NotchContainerView(viewModel: viewModel)
        window.installNookContent(NotchHostingView(
            rootView: root,
            interactiveSize: { [weak viewModel] in
                guard let viewModel else { return .zero }
                return viewModel.state == .expanded
                    ? viewModel.expandedSize
                    : viewModel.collapsedInteractiveSize
            },
            interactiveOffset: { [weak viewModel] in
                guard let viewModel, viewModel.state != .expanded else { return 0 }
                return viewModel.collapsedContentOffset
            },
            topCameraClearance: { [weak viewModel] in
                guard let viewModel, viewModel.state == .expanded else { return .zero }
                return viewModel.geometry.expandedShoulderClearance
            },
            fileDragActivationSize: { [weak viewModel] in
                guard let viewModel else { return .zero }
                if viewModel.state == .expanded {
                    return viewModel.expandedSize
                }
                guard viewModel.settings.openTrayOnFileDrag else { return .zero }
                // A small drag-only margin around the closed notch. Drags that
                // merely pass along the top of the screen stay with the app
                // underneath; ordinary pointer events always pass through.
                let collapsed = viewModel.collapsedInteractiveSize
                return CGSize(
                    width: collapsed.width + 60,
                    height: collapsed.height + 28
                )
            },
            fileDragEntered: { [weak viewModel] in
                viewModel?.fileDragEntered()
            },
            fileDragExited: { [weak viewModel] in
                viewModel?.fileDragExited()
            },
            fileURLsDropped: { [weak viewModel] urls in
                guard let viewModel, !urls.isEmpty else { return false }
                viewModel.acceptFileDrop(urls)
                return true
            },
            widgetDataDropped: { [weak viewModel] data in
                guard let viewModel, let kind = NookWidgetTransfer.decode(data) else { return false }
                viewModel.expand(to: .nook)
                withAnimation(Design.spring()) { viewModel.settings.setEnabled(true, for: kind) }
                viewModel.selectedWidget = kind
                WidgetDragSession.shared.finish()
                return true
            }
        ))
        window.setFrame(frame, display: true)
        if !isHiddenForApp { window.orderFrontRegardless() }
        // A closed Nook must not keep the keyboard (the Terminal and Notes take
        // it). Reordering hands key status back to the active app's window.
        viewModel.$state.removeDuplicates().dropFirst()
            .sink { [weak self, weak window] state in
                guard state == .collapsed, let window, window.isKeyWindow, self?.isHiddenForApp == false else { return }
                window.makeFirstResponder(nil)
                window.orderOut(nil)
                window.orderFrontRegardless()
            }
            .store(in: &presenceWatchers)
        viewModel.$measuredActivityLanes.removeDuplicates().dropFirst()
            .debounce(for: .milliseconds(20), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                guard self?.isDisplayTransitionActive == false else { return }
                self?.updateWindowFrames()
                // The notch grew or shrank: the pop-out moves with its edge.
                AgentPopout.shared.refresh()
            }
            .store(in: &presenceWatchers)
        return Entry(window: window, viewModel: viewModel, screen: screen)
    }

    private var isHiddenForApp = false

    private func applyHiddenApps() {
        let hide = HiddenApps.hides(frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                    hiddenIn: settings.hiddenInApps)
        guard hide != isHiddenForApp, !isDisplayTransitionActive else { return }
        isHiddenForApp = hide
        AgentPopout.shared.setHiddenForApp(hide)
        for entry in entries {
            if hide {
                entry.viewModel.state = .collapsed
                entry.window.orderOut(nil)
            } else {
                entry.window.orderFrontRegardless()
            }
        }
    }

    /// The closed notch gained or lost an activity: the window and the agent bubble
    /// follow its new edge.
    func closedLanesChanged() {
        guard !isDisplayTransitionActive else { return }
        updateWindowFrames()
        AgentPopout.shared.refresh()
    }

    private func updateWindowFrames() {
        for entry in entries {
            let frame = windowFrame(for: entry.viewModel, on: entry.screen)
            if entry.window.frame != frame {
                entry.window.setFrame(frame, display: true, animate: false)
            }
        }
    }

    private func windowFrame(for viewModel: NotchViewModel, on screen: NSScreen) -> NSRect {
        // Reserve every app page so navigation never clips a larger page or
        // moves the host window while the user is interacting with the dock.
        let pageSizes = NotchTab.allCases.map {
            NotchViewModel.fittedSize(widgets: settings.widgets, tab: $0,
                geometry: viewModel.geometry, availableWidth: screen.frame.width,
                sizes: settings.widgetSizes)
        }
        let surfaceWidth = max(pageSizes.map(\.width).max() ?? 0, viewModel.geometry.width + 2 * viewModel.collapsedActivityLaneWidth)
        let surfaceHeight = max(pageSizes.map(\.height).max() ?? 0, viewModel.collapsedSize.height)
        let width = surfaceWidth + 52
        let height = surfaceHeight + 38
        return NSRect(
            x: screen.frame.midX - width / 2,
            y: screen.frame.maxY - height,
            width: width,
            height: height
        )
    }
}
