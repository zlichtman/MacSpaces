import AppKit
import Combine

/// Placement is independent of whether Apple's Dock is currently auto-hidden.
enum DockPlacementPolicy {
    static func allowedEdges(appleDock: DockPosition) -> [DockPosition] {
        DockPosition.allCases.filter { $0 != appleDock }
    }

    static func resolved(preferred: DockPosition, appleDock: DockPosition) -> DockPosition {
        guard preferred == appleDock else { return preferred }
        return appleDock == .right ? .left : .right
    }

    static func isRevealPoint(_ point: NSPoint, on screen: NSRect, edge: DockPosition) -> Bool {
        guard screen.contains(point) else { return false }
        let distance: CGFloat = 8
        switch edge {
        case .bottom: return point.y <= screen.minY + distance
        case .left: return point.x <= screen.minX + distance
        case .right: return point.x >= screen.maxX - distance
        }
    }
}

@MainActor
final class AppleDockPlacement: ObservableObject {
    static let shared = AppleDockPlacement()
    @Published private(set) var edge: DockPosition
    private var timer: Timer?

    private init() {
        edge = Self.readEdge()
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let current = Self.readEdge()
                if self.edge != current { self.edge = current }
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

#if DEBUG
    func setPreviewEdge(_ edge: DockPosition) {
        timer?.invalidate()
        timer = nil
        self.edge = edge
    }
#endif

    private static func readEdge() -> DockPosition {
        let domain = "com.apple.dock" as CFString
        CFPreferencesAppSynchronize(domain)
        let raw = CFPreferencesCopyAppValue("orientation" as CFString, domain) as? String
        return DockPosition(rawValue: raw ?? "bottom") ?? .bottom
    }
}
