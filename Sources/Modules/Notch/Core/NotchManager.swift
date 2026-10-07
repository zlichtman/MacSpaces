import AppKit
import SwiftUI
import Combine

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
    /// The running Nook, for notifications that open their page instead of a card.
    private(set) static weak var active: NotchManager?
    private var cancellables: Set<AnyCancellable> = []
    private var isDisplayTransitionActive = false

    let settings = NookSettings.shared
    let shelf = ShelfStore.shared
    let nowPlaying = AppServices.shared.nowPlaying
    let powerMonitor = AppServices.shared.powerMonitor
    let timerService = AppServices.shared.timerService
    let bluetoothMonitor = AppServices.shared.bluetooth
    let systemActivityMonitor = AppServices.shared.systemActivity
    let teleprompter = AppServices.shared.teleprompter

    /// Opens `tab` briefly on the notched display (or the first one). Returns false when
    /// there's no Nook or it's in use, so the caller shows a card instead.
    func present(_ tab: NotchTab, for seconds: TimeInterval, prepare: () -> Void = {}) -> Bool {
        guard !isHiddenForApp, !entries.contains(where: { $0.viewModel.isInUse }),
              let entry = entries.first(where: { $0.viewModel.geometry.isHardwareNotch }) ?? entries.first else { return false }
        prepare()
        entry.viewModel.present(tab, for: seconds)
        return true
    }

    /// Explicit keyboard navigation opens and pins a page until it is closed.
    func openForKeyboard(_ tab: NotchTab) {
        guard let entry = entries.first(where: { $0.screen.frame.contains(NSEvent.mouseLocation) }) ?? entries.first else { return }
        isHiddenForApp = false
        entry.viewModel.isPinned = true
        entry.viewModel.expand(to: tab)
        entry.window.makeKeyAndOrderFront(nil)
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

        // Live activity labels can need more room than a small widget profile.
        // Resize the host window too, otherwise SwiftUI draws beyond its bounds.
        Publishers.MergeMany([
            powerMonitor.objectWillChange,
            nowPlaying.objectWillChange, timerService.objectWillChange,
            systemActivityMonitor.objectWillChange, MessageActivityState.shared.objectWillChange,
            PasteQueueState.shared.objectWillChange, MeetingCountdown.shared.objectWillChange,
            ScreenshotWatcher.shared.objectWillChange,
            AppServices.shared.extraTimers[0].objectWillChange, AppServices.shared.extraTimers[1].objectWillChange,
            AgentActivityMonitor.shared.objectWillChange,
        ])
        .debounce(for: .milliseconds(20), scheduler: DispatchQueue.main)
        .sink { [weak self] _ in
            guard self?.isDisplayTransitionActive == false else { return }
            self?.updateWindowFrames()
        }
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

        let screens = DisplayTargeting.screens(
            mode: settings.displayMode,
            selectedIDs: settings.selectedDisplayIDs,
            preferBuiltIn: true
        )

        // Decided before any window is ordered front: an excluded app may already be
        // frontmost at launch or after a display change.
        isHiddenForApp = HiddenApps.hides(frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                          hiddenIn: settings.hiddenInApps)
        for screen in screens {
            entries.append(makeWindow(for: screen))
        }
        isDisplayTransitionActive = false
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
                    : viewModel.collapsedSize
            },
            topCameraClearance: { [weak viewModel] in
                guard let viewModel, viewModel.state == .expanded, viewModel.geometry.isHardwareNotch else { return .zero }
                return CGSize(width: viewModel.geometry.width, height: viewModel.geometry.height)
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
                let collapsed = viewModel.collapsedSize
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
            .store(in: &cancellables)
        return Entry(window: window, viewModel: viewModel, screen: screen)
    }

    private var isHiddenForApp = false

    private func applyHiddenApps() {
        let hide = HiddenApps.hides(frontmost: NSWorkspace.shared.frontmostApplication?.bundleIdentifier,
                                    hiddenIn: settings.hiddenInApps)
        guard hide != isHiddenForApp, !isDisplayTransitionActive else { return }
        isHiddenForApp = hide
        for entry in entries {
            if hide {
                entry.viewModel.state = .collapsed
                entry.window.orderOut(nil)
            } else {
                entry.window.orderFrontRegardless()
            }
        }
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
        let surfaceWidth = max(pageSizes.map(\.width).max() ?? 0, viewModel.collapsedSize.width)
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
