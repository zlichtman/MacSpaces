import CoreGraphics
import Foundation

/// The Clock page's globe as seen from far away (an orthographic view): a place on
/// Earth to a point on the disc, and a click on the disc back to a place. The view is
/// centred on `latitude`/`longitude`; screen y grows downward.
struct GlobeProjection: Equatable {
    var latitude: Double
    var longitude: Double
    var center: CGPoint
    var radius: CGFloat

    /// How far the globe tips toward a pole when dragged, so a pole never faces you.
    static let tilt: ClosedRange<Double> = -60...60

    /// Where a place shows, and how squarely it faces you (1 at the centre, 0 at the
    /// rim); nil on the far side.
    func project(latitude φ: Double, longitude λ: Double) -> (point: CGPoint, facing: Double)? {
        let φ0 = latitude * .pi / 180, φr = φ * .pi / 180
        let Δλ = (λ - longitude) * .pi / 180
        let cosC = sin(φ0) * sin(φr) + cos(φ0) * cos(φr) * cos(Δλ)
        guard cosC > 0 else { return nil }
        let x = cos(φr) * sin(Δλ)
        let y = cos(φ0) * sin(φr) - sin(φ0) * cos(φr) * cos(Δλ)
        return (CGPoint(x: center.x + CGFloat(x) * radius, y: center.y - CGFloat(y) * radius), cosC)
    }

    /// The place under a point on the disc; nil off the globe.
    func coordinate(at point: CGPoint) -> (latitude: Double, longitude: Double)? {
        let x = Double((point.x - center.x) / radius), y = Double((center.y - point.y) / radius)
        let ρ = (x * x + y * y).squareRoot()
        guard ρ <= 1 else { return nil }
        guard ρ > 1e-9 else { return (latitude, Self.wrapped(longitude)) }
        let c = asin(ρ), φ0 = latitude * .pi / 180
        let φ = asin(cos(c) * sin(φ0) + y * sin(c) * cos(φ0) / ρ)
        let λ = longitude * .pi / 180 + atan2(x * sin(c), ρ * cos(c) * cos(φ0) - y * sin(c) * sin(φ0))
        return (φ * 180 / .pi, Self.wrapped(λ * 180 / .pi))
    }

    /// The view after dragging by `translation` points: across turns the globe, up and
    /// down tips it (within `tilt`).
    func dragged(by translation: CGSize) -> GlobeProjection {
        var next = self
        let degreesPerPoint = 180 / (Double.pi * Double(max(radius, 1)))
        next.longitude = longitude - Double(translation.width) * degreesPerPoint
        next.latitude = min(max(latitude + Double(translation.height) * degreesPerPoint, Self.tilt.lowerBound), Self.tilt.upperBound)
        return next
    }

    /// The shortest turn from one longitude to another, so spinning to a place never goes
    /// the long way round (the result can leave -180...180 to keep the animation smooth).
    static func nearestLongitude(_ target: Double, from current: Double) -> Double {
        current + wrapped(target - current)
    }

    static func wrapped(_ longitude: Double) -> Double {
        let value = (longitude + 180).truncatingRemainder(dividingBy: 360)
        return (value < 0 ? value + 360 : value) - 180
    }
}
