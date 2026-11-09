import SwiftUI
import AppKit

/// Forwards two-finger scroll events aimed at the notch window to SwiftUI.
/// Uses a local event monitor so normal hit-testing (buttons, drags, taps)
/// is never affected; events are passed through unchanged.
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (NSEvent) -> Void
    var onEnded: () -> Void
    /// Only scrolling with the pointer over this view counts, not anywhere in the window.
    var onlyInside = false

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        view.onEnded = onEnded
        view.onlyInside = onlyInside
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onEnded = onEnded
        nsView.onlyInside = onlyInside
    }

    final class CatcherView: NSView {
        var onScroll: ((NSEvent) -> Void)?
        var onEnded: (() -> Void)?
        var onlyInside = false

        private var monitor: Any?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()

            if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
            guard window != nil else { return }

            monitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel]) { [weak self] event in
                guard let self, event.window === self.window else { return event }
                switch event.phase {
                case .ended, .cancelled:
                    self.onEnded?()
                default:
                    // Fingers landing start a new gesture, even if the last one's end went unseen.
                    if event.phase == .began || event.phase == .mayBegin { self.onEnded?() }
                    if self.onlyInside, !self.bounds.contains(self.convert(event.locationInWindow, from: nil)) { return event }
                    self.onScroll?(event)
                }
                return event
            }
        }

        // Never participate in hit-testing; the monitor sees events anyway.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        deinit {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
        }
    }
}

extension View {
    /// A sideways two-finger swipe over this song panel changes songs, while the setting is on.
    func swipesSongs(_ viewModel: NotchViewModel) -> some View {
        background {
            if viewModel.settings.swipeToChangeSongs {
                ScrollWheelCatcher(
                    onScroll: { event in
                        viewModel.handlePanelSwipe(deltaX: event.scrollingDeltaX, deltaY: event.scrollingDeltaY,
                                                   momentum: event.momentumPhase != [])
                    },
                    onEnded: { viewModel.scrollEnded() },
                    onlyInside: true
                )
            }
        }
    }
}
