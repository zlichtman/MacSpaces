import SwiftUI
import AppKit

/// Forwards two-finger scroll events aimed at the notch window to SwiftUI.
/// Uses a local event monitor so normal hit-testing (buttons, drags, taps)
/// is never affected; events are passed through unchanged.
struct ScrollWheelCatcher: NSViewRepresentable {
    var onScroll: (CGFloat, CGFloat) -> Void
    var onEnded: () -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onScroll = onScroll
        view.onEnded = onEnded
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onScroll = onScroll
        nsView.onEnded = onEnded
    }

    final class CatcherView: NSView {
        var onScroll: ((CGFloat, CGFloat) -> Void)?
        var onEnded: (() -> Void)?

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
                    self.onScroll?(event.scrollingDeltaX, event.scrollingDeltaY)
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
