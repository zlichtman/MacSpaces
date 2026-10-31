import SwiftUI

/// The Clock page's globe: the world's land in dots on a sphere, brighter where it's
/// day, with a pin and time for each of your places (`GlobeProjection` does the maths).
/// Drag to spin it (it coasts to a stop and never turns by itself, so it costs nothing
/// at rest); hover a dot to read the place and its time; click one to add that place.
/// `latitude`/`longitude` is the point facing you, so the page can spin to a place.
struct GlobeClock: View {
    @Binding var latitude: Double
    @Binding var longitude: Double
    /// Places chosen for Match up, ringed in the accent.
    var selected: Set<String> = []
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hover: CGPoint?
    @State private var dragStart: GlobeProjection?
    @State private var hoverCardWidth: CGFloat = 180
    @State private var input = GlobeInput()

    var body: some View {
        TimelineView(.everyMinute) { context in
            GeometryReader { proxy in
                let projection = projection(in: proxy.size)
                GlobeScene(latitude: latitude, longitude: longitude, center: projection.center, radius: projection.radius,
                           date: Design.clockDate(context.date), places: places, selected: selected,
                           ink: theme.nookForeground, accent: theme.notch.accent, surface: theme.notch.surface)
                    .overlay {
                        if let hover, let spot = projection.coordinate(at: hover),
                           let zone = ClockGeography.nearestZone(latitude: spot.latitude, longitude: spot.longitude) {
                            let half = min(hoverCardWidth, proxy.size.width - 8) / 2
                            hoverCard(zone, date: Design.clockDate(context.date))
                                .fixedSize()
                                .background(GeometryReader { card in
                                    Color.clear.preference(key: GlobeHoverWidthKey.self, value: card.size.width)
                                })
                                .onPreferenceChange(GlobeHoverWidthKey.self) { hoverCardWidth = $0 }
                                .position(x: min(max(hover.x, half + 4), proxy.size.width - half - 4), y: max(hover.y - 26, 12))
                                .allowsHitTesting(false)
                        }
                    }
                    .contentShape(Circle().inset(by: (min(proxy.size.width, proxy.size.height) - projection.radius * 2) / 2))
                    .gesture(DragGesture(minimumDistance: 3)
                        .onChanged { value in
                            let start = dragStart ?? projection
                            dragStart = start
                            hover = nil
                            let next = start.dragged(by: value.translation)
                            latitude = next.latitude; longitude = next.longitude
                        }
                        .onEnded { value in
                            dragStart = nil
                            guard !reduceMotion && !theme.reduceMotion else { return }
                            // Coasts on in the direction it was thrown, then settles.
                            let fling = CGSize(width: (value.predictedEndTranslation.width - value.translation.width) * 0.5,
                                               height: (value.predictedEndTranslation.height - value.translation.height) * 0.5)
                            let coast = self.projection(in: proxy.size).dragged(by: fling)
                            withAnimation(.easeOut(duration: 0.9)) { latitude = coast.latitude; longitude = coast.longitude }
                        })
                    .simultaneousGesture(SpatialTapGesture().onEnded { tap in
                        guard let spot = projection.coordinate(at: tap.location),
                              let zone = ClockGeography.nearestZone(latitude: spot.latitude, longitude: spot.longitude) else { return }
                        MapClock.addPlace(latitude: spot.latitude, longitude: spot.longitude, zone: zone)
                    })
                    .onContinuousHover { phase in
                        if case .active(let location) = phase, dragStart == nil { hover = location } else { hover = nil }
                        if case .active = phase { input.inside = true } else { input.inside = false }
                    }
                    .onAppear { input.radius = projection.radius }
                    .onChange(of: proxy.size) { size in input.radius = self.projection(in: size).radius }
            }
        }
        // Two-finger scrolling spins the globe while the pointer is over it.
        .onAppear {
            input.spin = { delta in
                let next = GlobeProjection(latitude: latitude, longitude: longitude, center: .zero, radius: input.radius).dragged(by: delta)
                latitude = next.latitude; longitude = next.longitude
                hover = nil
            }
            input.start()
        }
        .onDisappear { input.stop() }
        .help("Drag to spin the globe; click a place to add it")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Globe with your places")
        .accessibilityValue(places.map { "\(WidgetOptions.placeName($0)) \(GlobeClock.time(WidgetOptions.zone($0), at: Date()))" }
            .joined(separator: ", "))
    }

    /// Your places, with where you are first.
    private var places: [String] {
        let saved = options.clockPlaces.filter { $0 != WidgetOptions.local }
        let current = saved.first(where: WidgetOptions.isCurrent) ?? WidgetOptions.local
        return [current] + saved.filter { $0 != current }
    }

    private func projection(in size: CGSize) -> GlobeProjection {
        GlobeProjection(latitude: latitude, longitude: longitude,
                        center: CGPoint(x: size.width / 2, y: size.height / 2),
                        radius: max(10, min(size.width, size.height) / 2 - 4))
    }

    /// What's under the pointer: "MADRID · SPAIN  23:45  +7h  Click to add".
    private func hoverCard(_ zone: ClockGeography.Zone, date: Date) -> some View {
        let timeZone = TimeZone(identifier: zone.identifier) ?? .current
        let full = options.clockPlaces.count >= WidgetOptions.maxPlaces
        return HStack(spacing: 6) {
            Text("\(zone.name) · \(zone.country)".uppercased()).font(.system(size: 8, weight: .semibold)).tracking(0.4)
            Text(GlobeClock.time(timeZone, at: date)).font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
            Text(GlobeClock.relative(timeZone, at: date)).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            Text(full ? "Remove a place to add more" : "Click to add").font(.system(size: 8, weight: .semibold))
                .foregroundStyle(full ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.notch.accent))
        }
        .lineLimit(1)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(theme.notch.surface.opacity(0.92), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.nookForeground.opacity(0.12)))
    }

    /// A place's time in the same style as yours ("9:14 PM", or "21:14" where 24-hour is used).
    static func time(_ zone: TimeZone?, at date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = zone ?? .current
        return date.formatted(style)
    }

    /// "+5h · Tomorrow", "Same time", "−8h".
    static func relative(_ zone: TimeZone, at date: Date) -> String {
        let hours = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        var text = hours == 0 ? "Same time" : (hours > 0 ? "+" : "−") + (hours == hours.rounded()
            ? String(Int(abs(hours))) : String(format: "%.1f", abs(hours))) + "h"
        if let day = DotClock.dayOffset(zone, at: date) { text += day == "+1" ? " · Tomorrow" : " · Yesterday" }
        return text
    }
}

/// The drawn globe at one orientation. It's `Animatable`, so spinning to a place (or
/// coasting after a drag) redraws every frame of the turn, dots and pins together.
private struct GlobeScene: View, Animatable {
    var latitude: Double
    var longitude: Double
    let center: CGPoint
    let radius: CGFloat
    let date: Date
    let places: [String]
    let selected: Set<String>
    let ink: Color
    let accent: Color
    let surface: Color

    var animatableData: AnimatablePair<Double, Double> {
        get { AnimatablePair(latitude, longitude) }
        set { latitude = newValue.first; longitude = newValue.second }
    }

    private var projection: GlobeProjection {
        GlobeProjection(latitude: latitude, longitude: longitude, center: center, radius: radius)
    }

    private struct Pin {
        let place: String
        let point: CGPoint
        let facing: Double
        let color: Color
        let text: String
        let label: CGRect?
    }

    /// Visible pins, with label frames that don't overlap each other or other pins.
    private var pins: [Pin] {
        let projection = projection
        let spots = places.enumerated().compactMap { index, place -> (Int, String, CGPoint, Double)? in
            guard let position = ClockGeography.position(of: place),
                  let spot = projection.project(latitude: position.latitude, longitude: position.longitude) else { return nil }
            return (index, place, spot.point, spot.facing)
        }
        var labels: [CGRect] = []
        let dots = spots.map { CGRect(x: $0.2.x - 5, y: $0.2.y - 5, width: 10, height: 10) }
        return spots.map { index, place, point, facing in
            let text = WidgetOptions.placeName(place).uppercased() + "  " + GlobeClock.time(WidgetOptions.zone(place), at: date)
            let size = CGSize(width: CGFloat(text.count) * 5.4 + 10, height: 13)
            let preferLeft = point.x > center.x + radius * 0.3
            let sides: [CGFloat] = preferLeft ? [-1, 1] : [1, -1]
            let candidates = [0, -1, 1].flatMap { row in sides.map { side in
                CGRect(x: side > 0 ? point.x + 7 : point.x - 7 - size.width,
                       y: point.y - size.height / 2 + CGFloat(row) * (size.height + 2), width: size.width, height: size.height)
            } }
            let free = candidates.first { rect in
                !labels.contains { $0.insetBy(dx: -2, dy: -1).intersects(rect) }
                    && !dots.enumerated().contains { $0.offset != spots.firstIndex { $0.1 == place } && $0.element.intersects(rect) }
            }
            if let free { labels.append(free) }
            return Pin(place: place, point: point, facing: facing, color: index == 0 ? accent : ink, text: text, label: free)
        }
    }

    var body: some View {
        let projection = projection
        let sun = ClockGeography.subsolarPoint(date)
        ZStack(alignment: .topLeading) {
            Canvas { context, _ in
                let disc = CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
                // The sphere: a faint fill, lit toward the top left, and a thin rim.
                context.fill(Path(ellipseIn: disc), with: .radialGradient(
                    Gradient(colors: [ink.opacity(0.07), ink.opacity(0.015)]),
                    center: CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.4), startRadius: 0, endRadius: radius * 1.5))
                context.stroke(Path(ellipseIn: disc), with: .color(ink.opacity(0.12)), lineWidth: 1)
                // One dot per grid cell, smaller and fainter toward the rim.
                let pitch = radius * CGFloat(ClockGeography.cell * .pi / 180)
                for row in 0..<ClockGeography.rows {
                    let lat = ClockGeography.northEdge - (Double(row) + 0.5) * ClockGeography.cell
                    // Rows of the flat grid shrink toward the poles on a sphere: skip columns so
                    // dots stay evenly spaced instead of bunching into rings.
                    let stride = max(1, Int((1 / max(cos(lat * .pi / 180), 0.05)).rounded()))
                    for column in Swift.stride(from: row % stride, to: ClockGeography.columns, by: stride) {
                        let lon = -180 + (Double(column) + 0.5) * ClockGeography.cell
                        guard let spot = projection.project(latitude: lat, longitude: lon) else { continue }
                        let land = ClockGeography.isLand(row: row, column: column)
                        let day = ClockGeography.isDaylight(latitude: lat, longitude: lon, sun: sun)
                        let base = land ? (day ? 0.62 : 0.24) : (day ? 0.045 : 0.025)
                        let rim = 0.35 + 0.65 * spot.facing
                        let size = pitch * (land ? 0.56 : 0.4) * CGFloat(0.45 + 0.55 * spot.facing)
                        context.fill(Path(ellipseIn: CGRect(x: spot.point.x - size / 2, y: spot.point.y - size / 2, width: size, height: size)),
                                     with: .color(ink.opacity(base * rim)))
                    }
                }
            }
            // Your places: a pin and its time, on the side facing you. Labels make room for
            // each other (right, left, then a row above or below); one that can't fit is left
            // off, never drawn over another.
            ForEach(pins, id: \.place) { pin in
                Circle().fill(pin.color).frame(width: 7, height: 7)
                    .overlay(Circle().stroke(surface, lineWidth: 1.5))
                    .overlay(Circle().stroke(accent, lineWidth: 1.5).frame(width: 13, height: 13).opacity(selected.contains(pin.place) ? 1 : 0))
                    .position(pin.point)
                    .opacity(0.4 + 0.6 * pin.facing)
                if let frame = pin.label {
                    Text(pin.text)
                        .font(.system(size: 8, weight: .semibold)).tracking(0.4).monospacedDigit()
                        .foregroundStyle(pin.color)
                        .lineLimit(1).fixedSize()
                        .frame(width: frame.width, height: frame.height)
                        .background(surface.opacity(0.8), in: Capsule())
                        .position(x: frame.midX, y: frame.midY)
                        .opacity(0.4 + 0.6 * pin.facing)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

/// Two-finger scrolling over the globe, through a local event monitor: scroll events
/// over it spin it (and aren't passed on); elsewhere they pass through untouched.
final class GlobeInput {
    var inside = false
    var radius: CGFloat = 100
    var spin: ((CGSize) -> Void)?
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, self.inside, let spin = self.spin else { return event }
            // A mouse wheel moves in lines; a trackpad in points.
            let scale: CGFloat = event.hasPreciseScrollingDeltas ? 1 : 8
            spin(CGSize(width: event.scrollingDeltaX * scale, height: event.scrollingDeltaY * scale))
            return nil
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    deinit { stop() }
}

private struct GlobeHoverWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 180
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
