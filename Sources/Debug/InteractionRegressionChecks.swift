#if DEBUG
import AppKit

@MainActor
enum InteractionRegressionChecks {
    static func run() {
        for appleDock in DockPosition.allCases {
            let allowed = DockPlacementPolicy.allowedEdges(appleDock: appleDock)
            precondition(allowed.count == 2 && !allowed.contains(appleDock))
            for preferred in DockPosition.allCases {
                let resolved = DockPlacementPolicy.resolved(preferred: preferred, appleDock: appleDock)
                precondition(resolved != appleDock)
                if preferred != appleDock { precondition(resolved == preferred) }
                if appleDock == .bottom { precondition(resolved.isVertical) }
            }
        }
        // A display to the left and below the primary screen exercises negative coordinates.
        let screen = NSRect(x: -1440, y: -200, width: 1440, height: 900)
        precondition(DockPlacementPolicy.isRevealPoint(NSPoint(x: -1439, y: 200), on: screen, edge: .left))
        precondition(DockPlacementPolicy.isRevealPoint(NSPoint(x: -1, y: 200), on: screen, edge: .right))
        precondition(DockPlacementPolicy.isRevealPoint(NSPoint(x: -700, y: -199), on: screen, edge: .bottom))
        precondition(!DockPlacementPolicy.isRevealPoint(NSPoint(x: 1, y: 200), on: screen, edge: .right))
        precondition(!DockPlacementPolicy.isRevealPoint(NSPoint(x: -700, y: 200), on: screen, edge: .left))
        for legacy in ["studio", "glass", "terminal", "soft", "signal", "orbit", "mono", "frame"] {
            let data = Data("\"\(legacy)\"".utf8)
            precondition(try! JSONDecoder().decode(WidgetVisualStyle.self, from: data) == .studio)
        }
        precondition(WidgetVisualStyle.allCases == [.studio])
        let legacyWidget = Data("{\"id\":\"DCA85B8C-E52C-40E8-A7B5-13C4A0659D12\",\"kind\":\"clock\",\"visualStyle\":\"terminal\"}".utf8)
        let widget = try! JSONDecoder().decode(WidgetInstance.self, from: legacyWidget)
        precondition(widget.kind == .clock && widget.visualStyle == .studio)
        print("Dock placement, edge activation and legacy style migration checks passed")
    }
}
#endif
