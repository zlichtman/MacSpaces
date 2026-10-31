import AppKit

/// The camera cutout at the top of a screen and how the Nook meets it: one model for
/// every Mac. `cutout` is the hardware (a notch attached to the top edge, an island
/// floating below it, or none); `look` is how the closed Nook draws around it.
struct NotchGeometry: Equatable {
    enum Cutout: Equatable {
        /// Attached to the top edge (MacBooks since 2021).
        case notch
        /// An oval floating `topInset` below the top edge (MacBook Pro with PROLED XDR).
        case island
        /// No camera cutout: external and older displays get a synthetic resting pill.
        case none
    }

    /// How the closed Nook draws around the camera. An undecided design, so one switch.
    enum Look: String, Equatable {
        /// Black, in the cutout's shape (a notch with ears, a capsule round an island, a
        /// pill elsewhere), with activities in lanes beside the camera on that black.
        case solid
        /// Nothing drawn over the camera: the hardware is the only black. Activities are
        /// round bubbles beside it, in one row with the agent bubble.
        case clear
    }

    /// Width of the hardware notch or the island's capsule, or a synthetic width.
    var width: CGFloat
    /// Height of the hardware notch (== menu bar area height), the island's capsule,
    /// or a synthetic height.
    var height: CGFloat
    var cutout: Cutout
    /// Space between the screen's top edge and the island's capsule (0 otherwise).
    var topInset: CGFloat
    var look: Look
    /// In the clear look, a screen without a cutout still shows a faint resting pill to
    /// point at. Undecided, so a switch.
    var notchlessHint: Bool

    init(width: CGFloat, height: CGFloat, isHardwareNotch: Bool) {
        self.init(width: width, height: height, cutout: isHardwareNotch ? .notch : .none)
    }

    init(width: CGFloat, height: CGFloat, cutout: Cutout, topInset: CGFloat = 0,
         look: Look = .solid, notchlessHint: Bool = true) {
        self.width = width
        self.height = height
        self.cutout = cutout
        self.topInset = topInset
        self.look = look
        self.notchlessHint = notchlessHint
    }

    /// Whether the screen has a camera cutout (a notch or an island).
    var isHardwareNotch: Bool { cutout != .none }
    var isIsland: Bool { cutout == .island }
    var isClear: Bool { look == .clear }

    /// Fallback pill shown on external / notchless displays.
    static let synthetic = NotchGeometry(width: 156, height: 30, isHardwareNotch: false)

    /// Hidden preferences for trying the undecided looks, read when the Nook's windows
    /// are built: `defaults write dev.opensource.MacSpaces notch.look clear` (or `solid`)
    /// and `defaults write dev.opensource.MacSpaces notch.notchlessHint -bool NO`.
    static let lookKey = "notch.look"
    static let notchlessHintKey = "notch.notchlessHint"

    /// Space between the camera housing and the open panel, so the panel
    /// reads as hanging below the notch rather than fused to it.
    static let cameraGap: CGFloat = 6
    /// Black drawn past the island cutout's edge on every side, so no lit pixel
    /// shows between the hole and the capsule.
    static let islandBleed: CGFloat = 1
    /// The closed island's least height while it shows activities, so a hole-punch
    /// cutout still holds the lanes' glyphs (about 22 pt tall).
    static let islandLaneHeight: CGFloat = 26
    /// Width over height of the stand-in capsule used when macOS reports nothing
    /// about the island (the iPhone island's proportions).
    static let islandFallbackAspect: CGFloat = 3.4
    /// The clear look's resting pill on a screen without a cutout, while it shows.
    static let notchlessHintOpacity: Double = 0.35
    /// The clear look's camera area: invisible, but not alpha 0, which macOS treats as
    /// a hole and sends hovers and clicks through to the window behind.
    static let clearHitOpacity: Double = 0.012

    /// What a screen reports about its top edge, in points.
    struct Reading: Equatable {
        var screenWidth: CGFloat
        /// `safeAreaInsets.top`.
        var safeTop: CGFloat
        /// Widths of `auxiliaryTopLeftArea` and `auxiliaryTopRightArea`.
        var auxiliaryLeft: CGFloat? = nil
        var auxiliaryRight: CGFloat? = nil
        /// The menu bar's thickness on this screen.
        var menuBarHeight: CGFloat = 24
        /// The built-in display has the island cutout (it's the only touch Mac display).
        var hasCameraIsland = false
        /// The cutout's bounds, measured from the screen's top-left corner, y down, when
        /// known (Debug captures simulate one). The x position is ignored: it's centred.
        var islandCutout: CGRect? = nil
    }

    static func detect(on screen: NSScreen) -> NotchGeometry {
        let menuBar = screen.frame.maxY - screen.visibleFrame.maxY
        let defaults = UserDefaults.standard
        return resolve(Reading(screenWidth: screen.frame.width,
                               safeTop: screen.safeAreaInsets.top,
                               auxiliaryLeft: screen.auxiliaryTopLeftArea?.width,
                               auxiliaryRight: screen.auxiliaryTopRightArea?.width,
                               menuBarHeight: menuBar > 0 ? menuBar : NSStatusBar.system.thickness,
                               hasCameraIsland: hasCameraIsland(screen)),
                       look: defaults.string(forKey: lookKey).flatMap(Look.init(rawValue:)) ?? .solid,
                       notchlessHint: defaults.object(forKey: notchlessHintKey) as? Bool ?? true)
    }

    /// macOS 27 reports touch on the built-in PROLED display, the only Mac display with
    /// the island. Read by name, so SDKs without `touchCapabilities` still build and
    /// older systems simply say no.
    private static func hasCameraIsland(_ screen: NSScreen) -> Bool {
        guard screen.responds(to: NSSelectorFromString("touchCapabilities")),
              let id = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber,
              CGDisplayIsBuiltin(id.uint32Value) != 0 else { return false }
        return ((screen.value(forKey: "touchCapabilities") as? NSNumber)?.uintValue ?? 0) != 0
    }

    static func resolve(_ reading: Reading, look: Look = .solid, notchlessHint: Bool = true) -> NotchGeometry {
        var geometry = cutout(reading)
        geometry.look = look
        geometry.notchlessHint = notchlessHint
        return geometry
    }

    private static func cutout(_ reading: Reading) -> NotchGeometry {
        if reading.hasCameraIsland || reading.islandCutout != nil { return island(reading) }
        guard reading.safeTop > 0 else {
            // A synthetic resting pill scales gently by display class without
            // becoming a wide empty bar on large external displays.
            let width: CGFloat
            switch reading.screenWidth {
            case ..<1500: width = 144
            case ..<1900: width = 156
            default: width = 168
            }
            return NotchGeometry(width: width, height: 30, isHardwareNotch: false)
        }

        // The notch spans the gap between the two auxiliary top areas.
        if let left = reading.auxiliaryLeft, let right = reading.auxiliaryRight {
            let width = max(120, reading.screenWidth - left - right)
            return NotchGeometry(width: width, height: reading.safeTop, isHardwareNotch: true)
        }

        return NotchGeometry(width: 185, height: reading.safeTop, isHardwareNotch: true)
    }

    /// The capsule around the island, from the best thing known about it: its measured
    /// bounds, else the band macOS keeps clear of it (the gap between the auxiliary
    /// areas, the safe-area inset tall), else a stand-in centred in the menu bar.
    private static func island(_ reading: Reading) -> NotchGeometry {
        if let cutout = reading.islandCutout {
            let height = cutout.height + 2 * islandBleed
            return NotchGeometry(width: max(cutout.width + 2 * islandBleed, height), height: height,
                                 cutout: .island, topInset: max(0, cutout.minY - islandBleed))
        }
        if reading.safeTop > 0, let left = reading.auxiliaryLeft, let right = reading.auxiliaryRight {
            let width = max(reading.safeTop, reading.screenWidth - left - right)
            return NotchGeometry(width: width, height: reading.safeTop, cutout: .island)
        }
        let height = max(20, reading.menuBarHeight - 6)
        return NotchGeometry(width: (height * islandFallbackAspect).rounded(), height: height,
                             cutout: .island, topInset: ((reading.menuBarHeight - height) / 2).rounded())
    }

    // MARK: - Where the Nook's surface sits

    /// The closed surface's height for its content: the island grows to hold lanes.
    func closedHeight(showingActivities: Bool) -> CGFloat {
        isIsland && showingActivities ? max(height, Self.islandLaneHeight) : height
    }

    /// Space above the closed surface when it is `surfaceHeight` tall (hover peek and
    /// file-drag swell included): a notch hangs from the top edge; the island's capsule
    /// stays centred on the cutout, growing evenly until it meets the top edge.
    func closedTopPadding(surfaceHeight: CGFloat) -> CGFloat {
        guard isIsland else { return 0 }
        return max(0, (topInset + height / 2 - surfaceHeight / 2).rounded())
    }

    /// How much of the closed surface's black shows: all of it in the solid look; in the
    /// clear look only the faint hint on a screen without a cutout (while nothing shows
    /// beside it), otherwise just enough to keep catching the pointer.
    func closedSurfaceOpacity(showingActivities: Bool) -> Double {
        guard isClear else { return 1 }
        return cutout == .none && notchlessHint && !showingActivities ? Self.notchlessHintOpacity : Self.clearHitOpacity
    }

    /// Space inside the open surface above its panel: the panel hangs `cameraGap` below
    /// the camera, a notch's or the island's, so it never covers the island, where
    /// macOS 27 shows its own Dynamic Island (Spotlight, Siri, Live Activities).
    var expandedPanelTopPadding: CGFloat { isHardwareNotch ? cameraBottom + Self.cameraGap : 0 }

    /// The bottom of the camera cutout, measured from the screen's top edge.
    var cameraBottom: CGFloat { isHardwareNotch ? topInset + height : 0 }

    /// The open Nook's transparent top strip that passes clicks through: beside a notch,
    /// or, on the island, the whole band down to the panel, so clicks and touches on
    /// the system's island reach it.
    var expandedShoulderClearance: CGSize {
        guard isHardwareNotch else { return .zero }
        return isIsland ? CGSize(width: 0, height: expandedPanelTopPadding) : CGSize(width: width, height: height)
    }

    /// The closed surface, lanes included, in screen coordinates (origin bottom-left).
    func closedFrame(size: CGSize, offset: CGFloat, on screen: CGRect) -> CGRect {
        CGRect(x: screen.midX + offset - size.width / 2,
               y: screen.maxY - closedTopPadding(surfaceHeight: size.height) - size.height,
               width: size.width, height: size.height)
    }

    /// Where pointing counts as pointing at the closed surface: it, the room for its
    /// hover peek, and the strip above an island up to the top edge.
    func closedHoverFrame(size: CGSize, offset: CGFloat, on screen: CGRect) -> CGRect {
        var frame = closedFrame(size: size, offset: offset, on: screen)
        frame.size.height += closedTopPadding(surfaceHeight: size.height)
        return frame.insetBy(dx: -10, dy: -8)
    }

    // MARK: - The outline

    /// The surface's outline, for `NotchShape`. A solid notch or pill keeps its ears
    /// closed and opens into the panel inset 12 pt each side, as it always has. Everything
    /// else (the island, and the clear look, whose closed capsule only ever shows as the
    /// hint) is a capsule that opens into that same panel through one animatable path.
    func outline(expanded: Bool, surfaceHeight: CGFloat) -> Outline {
        guard isIsland || isClear else {
            return expanded ? Outline(top: 12, bottom: Self.openCornerRadius, roundsTopInward: true)
                : Outline(top: 6, bottom: 10)
        }
        return expanded ? Outline(top: 12, bottom: Self.openCornerRadius, inset: 12, isCapsule: true)
            : Outline(top: surfaceHeight / 2, bottom: surfaceHeight / 2, isCapsule: true)
    }

    /// `Design.nookRadius`, the open panel's bottom corners (this file builds alone in checks).
    static let openCornerRadius: CGFloat = 22

    struct Outline: Equatable {
        var top: CGFloat
        var bottom: CGFloat
        /// The capsule's sides, inset like the notch panel's when open.
        var inset: CGFloat = 0
        var roundsTopInward = false
        var isCapsule = false
    }
}
