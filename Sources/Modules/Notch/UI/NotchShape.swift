import SwiftUI

/// The classic notch outline: flat top edge flush with the screen, rounded
/// bottom corners, and small outward-curving "ears" at the top corners.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var roundsTopInward = false
    /// A capsule-family outline instead (`NotchShape.capsule`), its sides `inset`.
    var isCapsule = false
    var inset: CGFloat = 0

    /// The outline `NotchGeometry` chooses for this state.
    init(_ outline: NotchGeometry.Outline) {
        self.init(topCornerRadius: outline.top, bottomCornerRadius: outline.bottom,
                  roundsTopInward: outline.roundsTopInward, isCapsule: outline.isCapsule, inset: outline.inset)
    }

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, roundsTopInward: Bool = false,
         isCapsule: Bool = false, inset: CGFloat = 0) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.roundsTopInward = roundsTopInward
        self.isCapsule = isCapsule
        self.inset = inset
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(topCornerRadius, bottomCornerRadius), inset) }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            inset = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if isCapsule { return Self.capsule(in: rect.insetBy(dx: inset, dy: 0), top: topCornerRadius, bottom: bottomCornerRadius) }
        var path = Path()
        let top = topCornerRadius
        let bottom = min(bottomCornerRadius, rect.height / 2)

        if roundsTopInward {
            let body = rect.insetBy(dx: top, dy: 0)
            path.move(to: CGPoint(x: body.minX + top, y: body.minY))
            path.addQuadCurve(to: CGPoint(x: body.minX, y: body.minY + top),
                              control: CGPoint(x: body.minX, y: body.minY))
            path.addLine(to: CGPoint(x: body.minX, y: body.maxY - bottom))
            path.addQuadCurve(to: CGPoint(x: body.minX + bottom, y: body.maxY),
                              control: CGPoint(x: body.minX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.maxX - bottom, y: body.maxY))
            path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.maxY - bottom),
                              control: CGPoint(x: body.maxX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.maxX, y: body.minY + top))
            path.addQuadCurve(to: CGPoint(x: body.maxX - top, y: body.minY),
                              control: CGPoint(x: body.maxX, y: body.minY))
            path.closeSubpath()
            return path
        }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))

        // Top-left ear curves inward without drawing outside the surface's
        // bounds. The old negative-X path produced a pale clipped halo.
        path.addQuadCurve(to: CGPoint(x: rect.minX + top, y: rect.minY + top),
                          control: CGPoint(x: rect.minX + top, y: rect.minY))

        // Left edge down to bottom-left corner.
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
                          control: CGPoint(x: rect.minX + top, y: rect.maxY))

        // Bottom edge.
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
                          control: CGPoint(x: rect.maxX - top, y: rect.maxY))

        // Right edge up to the top-right ear.
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                          control: CGPoint(x: rect.maxX - top, y: rect.minY))

        path.closeSubpath()
        return path
    }
}

extension NotchShape {
    /// A rectangle with circular top and bottom corners, each clamped to half the height
    /// and width, so equal radii of half the height make a capsule (the closed island,
    /// the clear look's hint) and the open panel keeps the same family of curves.
    static func capsule(in rect: CGRect, top: CGFloat, bottom: CGFloat) -> Path {
        let limit = min(rect.width, rect.height) / 2
        let top = max(0, min(top, limit)), bottom = max(0, min(bottom, limit))
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + top, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.maxX, y: rect.minY + top), radius: top)
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - bottom))
        path.addArc(tangent1End: CGPoint(x: rect.maxX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.maxX - bottom, y: rect.maxY), radius: bottom)
        path.addLine(to: CGPoint(x: rect.minX + bottom, y: rect.maxY))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.maxY),
                    tangent2End: CGPoint(x: rect.minX, y: rect.maxY - bottom), radius: bottom)
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + top))
        path.addArc(tangent1End: CGPoint(x: rect.minX, y: rect.minY),
                    tangent2End: CGPoint(x: rect.minX + top, y: rect.minY), radius: top)
        path.closeSubpath()
        return path
    }
}

/// The visible rim of an expanded Nook. This deliberately omits the top
/// segment so the surface stays visually attached to the display instead of
/// looking like a floating outlined window (a capsule's rim goes all the way
/// round: it does float).
struct NotchEdgeShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var roundsTopInward = false
    var isCapsule = false
    var inset: CGFloat = 0

    init(_ outline: NotchGeometry.Outline) {
        self.init(topCornerRadius: outline.top, bottomCornerRadius: outline.bottom,
                  roundsTopInward: outline.roundsTopInward, isCapsule: outline.isCapsule, inset: outline.inset)
    }

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, roundsTopInward: Bool = false,
         isCapsule: Bool = false, inset: CGFloat = 0) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
        self.roundsTopInward = roundsTopInward
        self.isCapsule = isCapsule
        self.inset = inset
    }

    var animatableData: AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat> {
        get { AnimatablePair(AnimatablePair(topCornerRadius, bottomCornerRadius), inset) }
        set {
            topCornerRadius = newValue.first.first
            bottomCornerRadius = newValue.first.second
            inset = newValue.second
        }
    }

    func path(in rect: CGRect) -> Path {
        if isCapsule {
            return NotchShape.capsule(in: rect.insetBy(dx: inset, dy: 0), top: topCornerRadius, bottom: bottomCornerRadius)
        }
        var path = Path()
        let top = topCornerRadius
        let bottom = min(bottomCornerRadius, rect.height / 2)

        if roundsTopInward {
            let body = rect.insetBy(dx: top, dy: 0)
            path.move(to: CGPoint(x: body.minX + top, y: body.minY))
            path.addQuadCurve(to: CGPoint(x: body.minX, y: body.minY + top),
                              control: CGPoint(x: body.minX, y: body.minY))
            path.addLine(to: CGPoint(x: body.minX, y: body.maxY - bottom))
            path.addQuadCurve(to: CGPoint(x: body.minX + bottom, y: body.maxY),
                              control: CGPoint(x: body.minX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.maxX - bottom, y: body.maxY))
            path.addQuadCurve(to: CGPoint(x: body.maxX, y: body.maxY - bottom),
                              control: CGPoint(x: body.maxX, y: body.maxY))
            path.addLine(to: CGPoint(x: body.maxX, y: body.minY + top))
            path.addQuadCurve(to: CGPoint(x: body.maxX - top, y: body.minY),
                              control: CGPoint(x: body.maxX, y: body.minY))

            return path
        }
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top, y: rect.minY + top),
            control: CGPoint(x: rect.minX + top, y: rect.minY)
        )
        path.addLine(to: CGPoint(x: rect.minX + top, y: rect.maxY - bottom))
        path.addQuadCurve(
            to: CGPoint(x: rect.minX + top + bottom, y: rect.maxY),
            control: CGPoint(x: rect.minX + top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top - bottom, y: rect.maxY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX - top, y: rect.maxY - bottom),
            control: CGPoint(x: rect.maxX - top, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.maxX - top, y: rect.minY + top))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.maxX - top, y: rect.minY)
        )
        return path
    }
}
