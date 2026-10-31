import AppKit
import SwiftUI

@main
enum NotchChecks {
    static func main() {
        notchAndNotchlessUnchanged()
        islandFromCutout()
        islandFromBandAndFallback()
        islandOutline()
        agentBubbleBesideIsland()
        outlines()
        clearLook()
        print("Notch checks passed")
    }

    /// One outline per state from the geometry; the solid notch and pill keep theirs.
    static func outlines() {
        let notch = NotchGeometry(width: 185, height: 32, isHardwareNotch: true)
        for geometry in [notch, NotchGeometry.synthetic] {
            precondition(geometry.outline(expanded: false, surfaceHeight: 36) == .init(top: 6, bottom: 10), "Solid: ears, as before")
            precondition(geometry.outline(expanded: true, surfaceHeight: 300) == .init(top: 12, bottom: 22, roundsTopInward: true),
                         "Solid: the open panel as before")
        }
        let island = NotchGeometry(width: 122, height: 26, cutout: .island, topInset: 4)
        precondition(island.outline(expanded: false, surfaceHeight: 30) == .init(top: 15, bottom: 15, isCapsule: true),
                     "A capsule, its radius half the surface's height")
        let open = NotchGeometry.Outline(top: 12, bottom: 22, inset: 12, isCapsule: true)
        precondition(island.outline(expanded: true, surfaceHeight: 300) == open, "Opens into the notch panel's shape")
        var clear = notch
        clear.look = .clear
        precondition(clear.outline(expanded: false, surfaceHeight: 32).isCapsule && clear.outline(expanded: true, surfaceHeight: 300) == open,
                     "The clear look rests as a capsule and opens into the same panel")
        // The open capsule, inset like the notch panel, has the notch panel's bounds.
        let panel = CGRect(x: 0, y: 0, width: 644, height: 300)
        let capsulePanel = NotchShape(open).path(in: panel).boundingRect
        let notchPanel = NotchShape(notch.outline(expanded: true, surfaceHeight: 300)).path(in: panel).boundingRect
        precondition(abs(capsulePanel.minX - notchPanel.minX) < 0.01 && abs(capsulePanel.maxX - notchPanel.maxX) < 0.01,
                     "Same width open: \(capsulePanel) \(notchPanel)")
    }

    /// The clear look: nothing drawn over the camera, bubbles in the agent bubble's row.
    static func clearLook() {
        let notch = NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 32, auxiliaryLeft: 663.5, auxiliaryRight: 663.5), look: .clear)
        precondition(notch.look == .clear && notch.cutout == .notch && notch.width == 185, "The switch leaves the cutout alone")
        precondition(NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 32)).look == .solid, "Solid unless switched")
        precondition(notch.closedSurfaceOpacity(showingActivities: false) == NotchGeometry.clearHitOpacity
                     && notch.closedSurfaceOpacity(showingActivities: true) == NotchGeometry.clearHitOpacity,
                     "Over a camera, only enough to catch the pointer")
        precondition(NotchGeometry.clearHitOpacity > 0, "Never alpha 0, which macOS treats as a hole")
        let external = NotchGeometry.resolve(.init(screenWidth: 1920, safeTop: 0), look: .clear)
        precondition(external.closedSurfaceOpacity(showingActivities: false) == NotchGeometry.notchlessHintOpacity,
                     "A faint resting pill on a screen without a camera")
        precondition(external.closedSurfaceOpacity(showingActivities: true) == NotchGeometry.clearHitOpacity, "Bubbles replace it")
        let noHint = NotchGeometry.resolve(.init(screenWidth: 1920, safeTop: 0), look: .clear, notchlessHint: false)
        precondition(noHint.closedSurfaceOpacity(showingActivities: false) == NotchGeometry.clearHitOpacity, "Or nothing, switched off")
        precondition(NotchGeometry.synthetic.closedSurfaceOpacity(showingActivities: false) == 1, "Solid stays solid")

        // Two activity bubbles and the agent bubble: one row, one size, one gap.
        let closedHeight = notch.closedHeight(showingActivities: true)
        let side = AgentPopoutLayout.bubbleSide(forHeight: closedHeight)
        precondition(side == closedHeight - AgentPopoutLayout.gap, "Inset from the top by the gap")
        precondition(AgentPopoutLayout.laneWidth(bubbles: 0, side: side) == 0)
        let lane = AgentPopoutLayout.laneWidth(bubbles: 1, side: side)
        precondition(lane == side + AgentPopoutLayout.gap)
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let closed = notch.closedFrame(size: CGSize(width: notch.width + 2 * lane, height: closedHeight), offset: 0, on: screen)
        let camera = CGRect(x: screen.midX - notch.width / 2, y: closed.minY, width: notch.width, height: closedHeight)
        let right = CGRect(x: camera.maxX + AgentPopoutLayout.gap, y: closed.minY, width: side, height: side)
        let left = CGRect(x: camera.minX - AgentPopoutLayout.gap - side, y: closed.minY, width: side, height: side)
        precondition(right.maxX == closed.maxX && left.minX == closed.minX, "Bubbles at the lanes' outer edges")
        let agent = AgentPopoutLayout.frame(besideNotch: closed, on: screen)
        precondition(agent.minX - right.maxX == AgentPopoutLayout.gap && agent.size == right.size && agent.minY == right.minY,
                     "The agent bubble continues the row")
    }

    /// `NotchGeometry.detect` before the island, kept here as the reference.
    static func legacy(_ reading: NotchGeometry.Reading) -> NotchGeometry {
        guard reading.safeTop > 0 else {
            let width: CGFloat
            switch reading.screenWidth {
            case ..<1500: width = 144
            case ..<1900: width = 156
            default: width = 168
            }
            return NotchGeometry(width: width, height: 30, isHardwareNotch: false)
        }
        if let left = reading.auxiliaryLeft, let right = reading.auxiliaryRight {
            return NotchGeometry(width: max(120, reading.screenWidth - left - right), height: reading.safeTop, isHardwareNotch: true)
        }
        return NotchGeometry(width: 185, height: reading.safeTop, isHardwareNotch: true)
    }

    /// Notched and notchless Macs resolve and lay out exactly as before.
    static func notchAndNotchlessUnchanged() {
        let readings: [NotchGeometry.Reading] = [
            .init(screenWidth: 1512, safeTop: 32, auxiliaryLeft: 663.5, auxiliaryRight: 663.5),   // 14-inch
            .init(screenWidth: 1728, safeTop: 32, auxiliaryLeft: 754, auxiliaryRight: 754),       // 16-inch
            .init(screenWidth: 1470, safeTop: 32, auxiliaryLeft: 642, auxiliaryRight: 642),       // 13-inch Air
            .init(screenWidth: 1800, safeTop: 38, auxiliaryLeft: 790, auxiliaryRight: 790),       // a scaled mode
            .init(screenWidth: 1512, safeTop: 32, auxiliaryLeft: 750, auxiliaryRight: 750),       // narrow gap: 120 floor
            .init(screenWidth: 1512, safeTop: 32),                                                // no auxiliary areas
            .init(screenWidth: 1440, safeTop: 0), .init(screenWidth: 1680, safeTop: 0),
            .init(screenWidth: 2560, safeTop: 0), .init(screenWidth: 1512, safeTop: 0, menuBarHeight: 37),
        ]
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        for reading in readings {
            let geometry = NotchGeometry.resolve(reading)
            precondition(geometry == legacy(reading), "Unchanged for \(reading)")
            precondition(!geometry.isIsland && geometry.topInset == 0)
            for height in [geometry.height, geometry.height + 4, geometry.height + 22, 60] {
                precondition(geometry.closedTopPadding(surfaceHeight: height) == 0, "A notch hangs from the top edge")
            }
            precondition(geometry.closedHeight(showingActivities: true) == geometry.height
                         && geometry.closedHeight(showingActivities: false) == geometry.height, "Lanes keep the notch's height")
            precondition(geometry.expandedPanelTopPadding == (geometry.isHardwareNotch ? geometry.height + 6 : 0),
                         "The open panel hangs 6 pt below a notch, from the top edge elsewhere")
            precondition(geometry.expandedShoulderClearance
                         == (geometry.isHardwareNotch ? CGSize(width: geometry.width, height: geometry.height) : .zero))
            precondition(geometry.cameraBottom == (geometry.isHardwareNotch ? geometry.height : 0))
            for (size, offset) in [(CGSize(width: geometry.width, height: geometry.height), CGFloat(0)),
                                   (CGSize(width: geometry.width + 96, height: geometry.height), 12)] {
                let old = CGRect(x: screen.midX + offset - size.width / 2, y: screen.maxY - size.height,
                                 width: size.width, height: size.height)
                precondition(geometry.closedFrame(size: size, offset: offset, on: screen) == old, "Closed frame unchanged")
                precondition(geometry.closedHoverFrame(size: size, offset: offset, on: screen) == old.insetBy(dx: -10, dy: -8),
                             "Hover area unchanged")
            }
        }
        precondition(NotchGeometry.synthetic == NotchGeometry(width: 156, height: 30, isHardwareNotch: false))
    }

    /// A measured cutout: the capsule is the cutout plus a 1 pt bleed, centred on it
    /// whatever its height, until it meets the top edge.
    static func islandFromCutout() {
        let pill = NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 0,
                                               islandCutout: CGRect(x: 696, y: 5, width: 120, height: 24)))
        precondition(pill == NotchGeometry(width: 122, height: 26, cutout: .island, topInset: 4),
                     "Pill cutout wrapped with a 1 pt bleed: \(pill)")
        let centre = pill.topInset + pill.height / 2
        for grown in [pill.height, pill.height + 4, NotchGeometry.islandLaneHeight] {
            let top = pill.closedTopPadding(surfaceHeight: grown)
            precondition(abs(top + grown / 2 - centre) <= 0.5, "The capsule stays centred on the cutout at \(grown) pt")
        }
        precondition(pill.closedTopPadding(surfaceHeight: pill.height + 22) == 0, "A big swell stops at the top edge")
        precondition(pill.closedHeight(showingActivities: true) == 26, "Already tall enough for lanes")
        precondition(pill.cameraBottom == 30, "Content and the teleprompter start below the cutout")
        precondition(pill.expandedPanelTopPadding == 36,
                     "The open panel hangs 6 pt below the island, leaving the island to macOS")
        precondition(pill.expandedShoulderClearance == CGSize(width: 0, height: 36),
                     "The whole band down to the panel passes clicks and touches to the system's island")

        let hole = NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 0, hasCameraIsland: true,
                                               islandCutout: CGRect(x: 0, y: 8, width: 12, height: 12)))
        precondition(hole.width == 14 && hole.height == 14 && hole.topInset == 7, "A hole-punch makes a circle: \(hole)")
        let lanes = hole.closedHeight(showingActivities: true)
        precondition(lanes == NotchGeometry.islandLaneHeight, "It grows to hold lanes")
        precondition(hole.closedTopPadding(surfaceHeight: lanes) + lanes / 2 == hole.topInset + hole.height / 2,
                     "and stays centred on the hole")
        precondition(hole.closedHeight(showingActivities: false) == 14, "and shrinks back to the hole at rest")

        // The capsule's frame on screen encloses the cutout exactly, bleed included.
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let frame = pill.closedFrame(size: CGSize(width: pill.width, height: pill.height), offset: 0, on: screen)
        let cutout = CGRect(x: 696, y: screen.maxY - 5 - 24, width: 120, height: 24)
        precondition(frame == cutout.insetBy(dx: -1, dy: -1), "Wraps the cutout exactly: \(frame)")
        let hover = pill.closedHoverFrame(size: frame.size, offset: 0, on: screen)
        precondition(hover.maxY >= screen.maxY && hover.contains(frame), "Pointing at the top edge above it counts")
    }

    /// No measured cutout: the band macOS keeps clear, else a stand-in in the menu bar.
    static func islandFromBandAndFallback() {
        let band = NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 32, auxiliaryLeft: 680, auxiliaryRight: 680,
                                               hasCameraIsland: true))
        precondition(band == NotchGeometry(width: 152, height: 32, cutout: .island),
                     "The reported band, as a capsule from the top edge: \(band)")
        let narrow = NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 32, auxiliaryLeft: 750, auxiliaryRight: 750,
                                                 hasCameraIsland: true))
        precondition(narrow.width == 32, "Never narrower than it is tall")
        let fallback = NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 0, menuBarHeight: 30, hasCameraIsland: true))
        precondition(fallback == NotchGeometry(width: 82, height: 24, cutout: .island, topInset: 3),
                     "A stand-in centred in the menu bar: \(fallback)")
        precondition(NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 0, menuBarHeight: 0, hasCameraIsland: true)).height == 20)
    }

    /// The outline is a true capsule when closed and stays inside its rect when open.
    static func islandOutline() {
        let rect = CGRect(x: 0, y: 0, width: 122, height: 26)
        let capsule = NotchShape(topCornerRadius: 13, bottomCornerRadius: 13, isCapsule: true).path(in: rect)
        precondition(capsule.boundingRect.insetBy(dx: -0.01, dy: -0.01).contains(rect)
                     && rect.insetBy(dx: -0.01, dy: -0.01).contains(capsule.boundingRect), "Fills its rect")
        // The cutout (a pill 1 pt inside) is covered; the corners outside the round ends aren't.
        let cutout = rect.insetBy(dx: 1, dy: 1)
        for t in stride(from: 0.0, to: 2 * Double.pi, by: .pi / 18) {
            let r = cutout.height / 2 - 0.05
            let left = CGPoint(x: cutout.minX + r + 0.05 + CGFloat(cos(t)) * r, y: cutout.midY + CGFloat(sin(t)) * r)
            let right = CGPoint(x: cutout.maxX - r - 0.05 + CGFloat(cos(t)) * r, y: cutout.midY + CGFloat(sin(t)) * r)
            precondition(capsule.contains(left) && capsule.contains(right), "Covers the cutout's round ends")
        }
        precondition(!capsule.contains(CGPoint(x: 1, y: 1)) && !capsule.contains(CGPoint(x: 121, y: 25)), "Round ends, not square")
        let edge = NotchEdgeShape(topCornerRadius: 13, bottomCornerRadius: 13, isCapsule: true).path(in: rect)
        precondition(edge.boundingRect == capsule.boundingRect, "The rim follows the capsule all the way round")
        let huge = NotchShape(topCornerRadius: 999, bottomCornerRadius: 999, isCapsule: true).path(in: rect)
        precondition(rect.insetBy(dx: -0.01, dy: -0.01).contains(huge.boundingRect), "Radii clamp to the rect")
        let panel = CGRect(x: 0, y: 0, width: 620, height: 300)
        let open = NotchShape(topCornerRadius: 22, bottomCornerRadius: 22, isCapsule: true).path(in: panel)
        precondition(open.contains(CGPoint(x: 310, y: 1)) && open.contains(CGPoint(x: 23, y: 23)) && !open.contains(CGPoint(x: 1, y: 1)),
                     "The open panel's top edge covers the cutout, with round corners")
        // A notch keeps its own outline.
        let notch = NotchShape(topCornerRadius: 6, bottomCornerRadius: 10).path(in: CGRect(x: 0, y: 0, width: 185, height: 32))
        precondition(notch.contains(CGPoint(x: 92, y: 1)) && !notch.contains(CGPoint(x: 1, y: 30)))
    }

    /// The agent bubble sits beside the island, its height and top-aligned with it.
    static func agentBubbleBesideIsland() {
        let screen = CGRect(x: 0, y: 0, width: 1512, height: 982)
        let island = NotchGeometry.resolve(.init(screenWidth: 1512, safeTop: 0,
                                                 islandCutout: CGRect(x: 0, y: 5, width: 120, height: 24)))
        let size = CGSize(width: island.width + 2 * 48, height: island.closedHeight(showingActivities: true))
        let closed = island.closedFrame(size: size, offset: 0, on: screen)
        precondition(closed.maxY == screen.maxY - island.closedTopPadding(surfaceHeight: size.height), "Below the top edge")
        let bubble = AgentPopoutLayout.frame(besideNotch: closed, on: screen)
        precondition(bubble.maxY == closed.maxY - AgentPopoutLayout.gap && bubble.minY == closed.minY
                     && bubble.width == bubble.height, "A circle the gap inside the capsule's top, level with its bottom")
        precondition(bubble.minX == closed.maxX + AgentPopoutLayout.gap && !bubble.intersects(closed), "Just right of it")
        let start = AgentPopoutLayout.startFrame(besideNotch: closed)
        precondition(closed.contains(start), "It slides out from under the capsule")
    }
}
