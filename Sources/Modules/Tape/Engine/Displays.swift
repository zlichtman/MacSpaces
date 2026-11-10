import CoreGraphics
import Foundation

struct TapeDisplay: Identifiable, Sendable {
    let id: String
    let name: String
    var geometry: ScreenGeometry
    init(id: String, name: String, geometry: ScreenGeometry) {
        self.id = id
        self.name = name
        self.geometry = geometry
    }
}

enum DisplayLayout {
    /// Largest visible area owns a window. Preserve the owner at an exact shared-edge tie.
    static func owner(of frame: CGRect, in displays: [TapeDisplay], previous: String? = nil) -> String?
    {
        guard !displays.isEmpty, frame.width > 0, frame.height > 0 else { return nil }
        let areas = displays.map { display -> CGFloat in
            let intersection = display.geometry.frame.intersection(frame)
            return intersection.isNull ? 0 : intersection.width * intersection.height
        }
        let largest = areas.max() ?? 0
        if largest > 0 {
            if let previous, let index = displays.firstIndex(where: { $0.id == previous }),
                abs(areas[index] - largest) < 1
            {
                return previous
            }
            return displays[areas.firstIndex(of: largest)!].id
        }
        // A disconnected display must not strand a window at its old coordinates.
        return displays.min {
            distance(frame, to: $0.geometry.frame) < distance(frame, to: $1.geometry.frame)
        }?.id
    }
    static func at(_ point: CGPoint, in displays: [TapeDisplay]) -> String? {
        displays.first { $0.geometry.frame.contains(point) }?.id
    }
    static func next(after id: String, in displays: [TapeDisplay], excluding disabled: Set<String>)
        -> String?
    {
        let enabled = displays.filter { !disabled.contains($0.id) }
        guard enabled.count > 1, let index = enabled.firstIndex(where: { $0.id == id }) else { return nil }
        return enabled[(index + 1) % enabled.count].id
    }
    static func geometry(for display: TapeDisplay, in displays: [TapeDisplay]) -> ScreenGeometry {
        var geometry = display.geometry
        for other in displays
        where other.id != display.id && !geometry.neighbors.contains(other.geometry.frame) {
            geometry.neighbors.append(other.geometry.frame)
        }
        return geometry
    }
    static func restored(_ frame: CGRect, originalOrigin: CGPoint, on geometry: ScreenGeometry)
        -> CGRect
    {
        let translated = frame.offsetBy(
            dx: geometry.frame.minX - originalOrigin.x,
            dy: geometry.frame.minY - originalOrigin.y)
        return StripLayout.restored(translated, on: geometry)
    }
    private static func distance(_ frame: CGRect, to screen: CGRect) -> CGFloat {
        let x = min(max(frame.midX, screen.minX), screen.maxX)
        let y = min(max(frame.midY, screen.minY), screen.maxY)
        return pow(frame.midX - x, 2) + pow(frame.midY - y, 2)
    }
}
