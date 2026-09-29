import AppKit
import SwiftUI
@main struct WindowChecks {
    @MainActor static func main() {
        _ = NSApplication.shared
        let frame = NSRect(x: -700, y: 900, width: 800, height: 300)
        let panel = NotchWindow(contentRect: frame)
        precondition(panel.collectionBehavior.contains(.stationary))
        precondition(!panel.collectionBehavior.contains(.transient))
        precondition(!panel.collectionBehavior.contains(.managed))
        precondition(panel.collectionBehavior.contains(.canJoinAllSpaces))
        precondition(panel.collectionBehavior.contains(.fullScreenAuxiliary))
        precondition(panel.collectionBehavior.contains(.ignoresCycle))
        precondition(panel.styleMask.contains(.nonactivatingPanel))
        precondition(!panel.isMovable && !panel.hidesOnDeactivate)
        precondition(panel.canBecomeKey && !panel.canBecomeMain)
        precondition(panel.frame == frame)
        let host = NotchHostingView(rootView: WindowProbe(width: 400, height: 80))
        panel.contentView = host
        panel.setFrame(frame, display: false)
        precondition(host.sizingOptions.isEmpty)
        if #available(macOS 13.3, *) { precondition(host.safeAreaRegions.isEmpty) }
        for iteration in 0..<120 {
            host.rootView = WindowProbe(width: iteration.isMultiple(of: 2) ? 300 : 1100,
                                        height: iteration.isMultiple(of: 2) ? 40 : 700)
            host.layoutSubtreeIfNeeded()
            panel.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.001))
            precondition(panel.frame == frame, "SwiftUI content must not resize the host window")
        }
        panel.close()
        print("Nook window checks passed: stationary desktop policy, Spaces, full screen, focus, geometry and 120 content-size transitions")
    }
}

private struct WindowProbe: View {
    let width: CGFloat
    let height: CGFloat
    var body: some View { Color.clear.frame(width: width, height: height) }
}
