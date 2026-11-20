import SwiftUI

/// The Nook's outline: a rectangle with circular top and bottom corners (`capsule`), its sides
/// inset, so a closed capsule and the open panel are one animatable path.
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var inset: CGFloat = 0

    /// The outline `NotchGeometry` chooses for this state.
    init(_ outline: NotchGeometry.Outline) {
        self.init(topCornerRadius: outline.top, bottomCornerRadius: outline.bottom, inset: outline.inset)
    }

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, inset: CGFloat = 0) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
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
        Self.capsule(in: rect.insetBy(dx: inset, dy: 0), top: topCornerRadius, bottom: bottomCornerRadius)
    }

    /// A rectangle with circular top and bottom corners, each clamped to half the height
    /// and width, so equal radii of half the height make a capsule (the closed surface)
    /// and the open panel keeps the same family of curves.
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

/// The visible rim of the Nook: the same path as `NotchShape`, all the way round.
struct NotchEdgeShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat
    var inset: CGFloat = 0

    init(_ outline: NotchGeometry.Outline) {
        self.init(topCornerRadius: outline.top, bottomCornerRadius: outline.bottom, inset: outline.inset)
    }

    init(topCornerRadius: CGFloat, bottomCornerRadius: CGFloat, inset: CGFloat = 0) {
        self.topCornerRadius = topCornerRadius
        self.bottomCornerRadius = bottomCornerRadius
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
        NotchShape.capsule(in: rect.insetBy(dx: inset, dy: 0), top: topCornerRadius, bottom: bottomCornerRadius)
    }
}
