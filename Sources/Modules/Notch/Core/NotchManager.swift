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
    private var cancellables: Set<AnyCancellable> = []
    private var isDisplayTransitionActive = false

    let settings = NookSettings.shared
    let shelf = ShelfStore()
    let nowPlaying = AppServices.shared.nowPlaying
    let powerMonitor = AppServices.shared.powerMonitor
    let timerService = AppServices.shared.timerService
    let bluetoothMonitor = AppServices.shared.bluetooth
    let systemActivityMonitor = AppServices.shared.systemActivity
    let teleprompter = AppServices.shared.teleprompter

    func start() {
        rebuildWindows()

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
        settings.cancelInteractiveReorder()
        cancellables.removeAll()
        entries.forEach { $0.window.close() }
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
        entries.forEach { $0.window.orderOut(nil) }
    }

    private func rebuildWindows() {
        settings.cancelInteractiveReorder()
        entries.forEach { $0.window.close() }
        entries.removeAll()

        let screens = DisplayTargeting.screens(
            mode: settings.displayMode,
            selectedIDs: settings.selectedDisplayIDs,
            preferBuiltIn: true
        )

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
        let root = NotchContainerView(viewModel: viewModel)
        window.contentView = NotchHostingView(
            rootView: root,
            interactiveSize: { [weak viewModel] in
                guard let viewModel else { return .zero }
                return viewModel.state == .expanded
                    ? viewModel.expandedSize
                    : viewModel.collapsedSize
            },
            fileDragActivationSize: { [weak viewModel] in
                guard let viewModel else { return .zero }
                if viewModel.state == .expanded {
                    return viewModel.expandedSize
                }
                // Catch Finder drags well below the macOS top-edge gesture.
                // The extra room is drag-only; ordinary pointer events still
                // pass through to the app underneath.
                return CGSize(
                    width: min(viewModel.expandedSize.width, 760),
                    height: 148
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
        )
        window.setFrame(frame, display: true)
        window.orderFrontRegardless()
        return Entry(window: window, viewModel: viewModel, screen: screen)
    }

    private func updateWindowFrames() {
        for entry in entries {
            let frame = windowFrame(for: entry.viewModel, on: entry.screen)
            entry.window.setFrame(frame, display: true, animate: false)
        }
    }

    private func windowFrame(for viewModel: NotchViewModel, on screen: NSScreen) -> NSRect {
        let surfaceWidth = max(viewModel.expandedSize.width, viewModel.collapsedSize.width)
        let surfaceHeight = max(viewModel.expandedSize.height, viewModel.collapsedSize.height)
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
