import SwiftUI
import CoreLocation

/// The Clock's Map style: a dot map of the world with night shaded and a pin for each
/// of your places with its time. Hovering reads out any spot (city, country, time).
/// In the tile, clicking drops a pin there, whose time shows large, and clicking the
/// pin removes it; on the Clock page, clicking adds the spot to your places instead.
/// Your place is the saved one in this Mac's time zone (else "local"), in the accent.
/// `offset` shifts every time and the shading, for the Clock page's time scrubber.
/// Small shows the pinned (or your) time in dots.
struct MapClock: View {
    var compact = false
    var offset: TimeInterval = 0
    /// On the Clock page a click adds the spot to your places (no pin or readout).
    var addsOnTap = false
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var hover: CGPoint?
    /// The hover card's measured width, so it's kept wholly inside the map.
    @State private var hoverCardWidth: CGFloat = 160

    private static let aspect = CGFloat(ClockGeography.columns) / CGFloat(ClockGeography.rows)
    private static let geocoder = CLGeocoder()

    var body: some View {
        if compact {
            DotClock(places: [options.clockPin?.zone ?? WidgetOptions.local], compact: true)
        } else {
            TimelineView(.everyMinute) { context in
                let date = Design.clockDate(context.date).addingTimeInterval(offset)
                GeometryReader { proxy in
                    let frame = mapFrame(in: proxy.size)
                    ZStack(alignment: .topLeading) {
                        map(date: date)
                            .frame(width: frame.width, height: frame.height)
                            .offset(x: frame.minX, y: frame.minY)
                        let pins = pins(in: frame, date: date)
                        // Labels need the Large tile's room; Medium shows the pins alone.
                        let labelled = proxy.size.width >= 380
                        ForEach(pins, id: \.place) { pin in
                            let color = pin.isCurrent ? theme.notch.accent : theme.nookForeground
                            Circle().fill(color).frame(width: 6, height: 6)
                                .overlay(Circle().stroke(theme.notch.surface, lineWidth: 1.5))
                                .position(pin.point)
                            if labelled {
                                Text(pin.label)
                                    .font(.system(size: 8, weight: .semibold)).tracking(0.4).monospacedDigit()
                                    .foregroundStyle(color)
                                    .frame(width: pin.labelFrame.width, height: pin.labelFrame.height)
                                    .background(theme.notch.surface.opacity(0.75), in: Capsule())
                                    .position(x: pin.labelFrame.midX, y: pin.labelFrame.midY)
                            }
                        }
                        if !addsOnTap, let pin = options.clockPin {
                            // The dropped pin: an accent head with a ring, standing on its spot.
                            let spot = point(pin.latitude, pin.longitude, in: frame)
                            Circle().fill(theme.notch.accent.opacity(0.25)).frame(width: 18, height: 18).position(spot)
                            Circle().fill(theme.notch.accent).frame(width: 9, height: 9)
                                .overlay(Circle().stroke(theme.notch.surface, lineWidth: 2))
                                .position(spot)
                        }
                        if let hover, frame.contains(hover), let spot = coordinate(hover, in: frame),
                           let zone = ClockGeography.nearestZone(latitude: spot.latitude, longitude: spot.longitude) {
                            let half = min(hoverCardWidth, proxy.size.width - 8) / 2
                            hoverCard(zone, date: date)
                                .background(GeometryReader { card in
                                    Color.clear.preference(key: HoverCardWidthKey.self, value: card.size.width)
                                })
                                .onPreferenceChange(HoverCardWidthKey.self) { hoverCardWidth = $0 }
                                .position(x: min(max(hover.x, half + 4), proxy.size.width - half - 4), y: max(hover.y - 24, 12))
                                .allowsHitTesting(false)
                        }
                        // With labels, every place already shows its time, so the large readout only
                        // appears for a dropped pin (owner: it covered the map).
                        if !addsOnTap && (options.clockPin != nil || !labelled) {
                            readout(date: date)
                                .padding(6)
                                .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
                        }
                    }
                    .contentShape(Rectangle())
                    .onContinuousHover { phase in
                        if case .active(let location) = phase { hover = location } else { hover = nil }
                    }
                    .gesture(SpatialTapGesture().onEnded { tap($0.location, in: frame) })
                }
                .padding(10)
            }
            .help(addsOnTap ? "Click the map to add that place"
                  : options.clockPin == nil ? "Click the map to drop a pin and see the time there"
                  : "Click elsewhere to move the pin, or on it to remove it")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityText)
        }
    }

    /// Your places, with where you are first: a saved place in this Mac's time zone, or "local".
    private var places: [String] {
        let saved = options.clockPlaces.filter { $0 != WidgetOptions.local }
        let current = saved.first(where: WidgetOptions.isCurrent) ?? WidgetOptions.local
        return [current] + saved.filter { $0 != current }
    }

    // MARK: Geometry

    private func mapFrame(in size: CGSize) -> CGRect {
        let width = min(size.width, size.height * Self.aspect)
        let height = width / Self.aspect
        return CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2, width: width, height: height)
    }

    private func point(_ latitude: Double, _ longitude: Double, in frame: CGRect) -> CGPoint {
        let span = Double(ClockGeography.rows) * ClockGeography.cell
        return CGPoint(x: frame.minX + CGFloat((longitude + 180) / 360) * frame.width,
                       y: frame.minY + CGFloat((ClockGeography.northEdge - latitude) / span) * frame.height)
    }

    private func coordinate(_ location: CGPoint, in frame: CGRect) -> (latitude: Double, longitude: Double)? {
        let span = Double(ClockGeography.rows) * ClockGeography.cell
        let longitude = Double((location.x - frame.minX) / frame.width) * 360 - 180
        let latitude = ClockGeography.northEdge - Double((location.y - frame.minY) / frame.height) * span
        guard (-180...180).contains(longitude), (ClockGeography.southEdge...ClockGeography.northEdge).contains(latitude) else { return nil }
        return (latitude, longitude)
    }

    private func tap(_ location: CGPoint, in frame: CGRect) {
        if addsOnTap {
            if let spot = coordinate(location, in: frame),
               let zone = ClockGeography.nearestZone(latitude: spot.latitude, longitude: spot.longitude) {
                Self.addPlace(latitude: spot.latitude, longitude: spot.longitude, zone: zone)
            }
            return
        }
        if let pin = options.clockPin, hypot(location.x - point(pin.latitude, pin.longitude, in: frame).x,
                                             location.y - point(pin.latitude, pin.longitude, in: frame).y) < 12 {
            options.clockPin = nil
            return
        }
        guard let spot = coordinate(location, in: frame),
              let zone = ClockGeography.nearestZone(latitude: spot.latitude, longitude: spot.longitude) else { return }
        // The nearest zone's city shows at once; Apple's geocoder then gives the exact
        // place, country and time zone (offline or at sea, the nearest zone stands).
        let pin = WidgetOptions.ClockPin(latitude: spot.latitude, longitude: spot.longitude, zone: zone.identifier,
                                         name: zone.name, country: zone.country)
        options.clockPin = pin
        Self.geocoder.cancelGeocode()
        Self.geocoder.reverseGeocodeLocation(CLLocation(latitude: spot.latitude, longitude: spot.longitude)) { placemarks, _ in
            guard let place = placemarks?.first else { return }
            let zone = place.timeZone?.identifier
            let name = place.locality ?? place.administrativeArea ?? place.ocean ?? place.name
            let country = place.country
            Task { @MainActor in
                guard options.clockPin == pin else { return }
                var refined = pin
                if let zone { refined.zone = zone }
                if let name { refined.name = name }
                refined.country = country
                options.clockPin = refined
            }
        }
    }

    /// Adds a clicked spot (on this map or the Clock page's globe) to your places under the
    /// nearest zone's city at once, then renames it in place when Apple's geocoder names
    /// the exact town.
    static func addPlace(latitude: Double, longitude: Double, zone: ClockGeography.Zone) {
        let spot = (latitude: latitude, longitude: longitude)
        let options = WidgetOptions.shared
        let names = Set(options.clockPlaces.map(WidgetOptions.placeName))
        guard options.clockPlaces.count < WidgetOptions.maxPlaces, !names.contains(zone.name) else { return }
        let quick = WidgetOptions.namedPlace(zone: zone.identifier, name: zone.name,
                                             latitude: spot.latitude, longitude: spot.longitude)
        options.addPlace(quick)
        Self.geocoder.cancelGeocode()
        Self.geocoder.reverseGeocodeLocation(CLLocation(latitude: spot.latitude, longitude: spot.longitude)) { placemarks, _ in
            guard let place = placemarks?.first,
                  let name = place.locality ?? place.administrativeArea ?? place.ocean ?? place.name else { return }
            let refined = WidgetOptions.namedPlace(zone: place.timeZone?.identifier ?? zone.identifier, name: name,
                                                   latitude: spot.latitude, longitude: spot.longitude)
            Task { @MainActor in
                let options = WidgetOptions.shared
                guard let index = options.clockPlaces.firstIndex(of: quick),
                      !options.clockPlaces.contains(where: { WidgetOptions.placeName($0) == name && $0 != quick }) else { return }
                options.clockPlaces[index] = refined
            }
        }
    }

    // MARK: Drawing

    /// Land in dots, brighter where it's day; the sea as the faintest grid.
    private func map(date: Date) -> some View {
        let ink = theme.nookForeground
        let sun = ClockGeography.subsolarPoint(date)
        return Canvas { context, size in
            let pitch = size.width / CGFloat(ClockGeography.columns)
            let dot = pitch * 0.62
            for row in 0..<ClockGeography.rows {
                let latitude = ClockGeography.northEdge - (Double(row) + 0.5) * ClockGeography.cell
                for column in 0..<ClockGeography.columns {
                    let longitude = -180 + (Double(column) + 0.5) * ClockGeography.cell
                    let land = ClockGeography.isLand(row: row, column: column)
                    let day = ClockGeography.isDaylight(latitude: latitude, longitude: longitude, sun: sun)
                    let opacity = land ? (day ? 0.42 : 0.15) : (day ? 0.05 : 0.025)
                    let rect = CGRect(x: CGFloat(column) * pitch + (pitch - dot) / 2,
                                      y: CGFloat(row) * pitch + (pitch - dot) / 2, width: dot, height: dot)
                    context.fill(Path(ellipseIn: rect), with: .color(ink.opacity(opacity)))
                }
            }
        }
    }

    private struct Pin {
        let place: String
        var isCurrent = false
        let point: CGPoint
        let label: String
        let labelFrame: CGRect
    }

    /// Each place's pin and label. A label goes right of its pin, else left, else a
    /// row above or below, whichever first clears the other labels and pins.
    private func pins(in frame: CGRect, date: Date) -> [Pin] {
        let spots = places.compactMap { place -> (String, CGPoint)? in
            ClockGeography.position(of: place).map { (place, point($0.latitude, $0.longitude, in: frame)) }
        }
        var placed: [Pin] = []
        for (place, spot) in spots {
            let label = WidgetOptions.placeName(place).uppercased() + "  " + DotClock.time(WidgetOptions.zone(place), at: date)
            let size = CGSize(width: CGFloat(label.count) * 5.2 + 8, height: 12)
            let candidates = [(1, 0), (-1, 0), (1, -1), (-1, -1), (1, 1), (-1, 1)].map { side, row -> CGRect in
                CGRect(x: side > 0 ? spot.x + 6 : spot.x - 6 - size.width,
                       y: spot.y - size.height / 2 + CGFloat(row) * (size.height + 2), width: size.width, height: size.height)
            }
            let blocked = placed.map(\.labelFrame) + spots.map { CGRect(x: $0.1.x - 4, y: $0.1.y - 4, width: 8, height: 8) }
            let choice = candidates.first { rect in frame.insetBy(dx: -4, dy: -4).contains(rect) && !blocked.contains { $0.intersects(rect) } }
                ?? candidates.first { frame.insetBy(dx: -4, dy: -4).contains($0) } ?? candidates[0]
            placed.append(Pin(place: place, isCurrent: place == places.first, point: spot, label: label, labelFrame: choice))
        }
        return placed
    }

    /// What's under the pointer: "MADRID · SPAIN  23:45  +7h".
    private func hoverCard(_ zone: ClockGeography.Zone, date: Date) -> some View {
        let timeZone = TimeZone(identifier: zone.identifier) ?? .current
        return HStack(spacing: 6) {
            Text("\(zone.name) · \(zone.country)".uppercased())
                .font(.system(size: 8, weight: .semibold)).tracking(0.4)
            Text(DotClock.time(timeZone, at: date)).font(.system(size: 10, weight: .bold, design: .rounded)).monospacedDigit()
            Text(relative(timeZone, at: date)).font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
            if addsOnTap {
                let full = options.clockPlaces.count >= WidgetOptions.maxPlaces
                Text(full ? "Remove a place to add more" : "Click to add")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(full ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.notch.accent))
            }
        }
        .lineLimit(1)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(theme.notch.surface.opacity(0.9), in: Capsule())
        .overlay(Capsule().strokeBorder(theme.nookForeground.opacity(0.12)))
        .fixedSize()
    }

    /// The pinned place's time, large, or yours when nothing is pinned.
    private func readout(date: Date) -> some View {
        let zone = options.clockPin.flatMap { TimeZone(identifier: $0.zone) } ?? .current
        let pin = options.clockPin
        let name = pin.map { [$0.name, $0.country].compactMap { $0 }.joined(separator: " · ") }
            ?? WidgetOptions.placeName(WidgetOptions.local)
        return VStack(alignment: .leading, spacing: 4) {
            Text(name.uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(0.8)
                .foregroundStyle(pin != nil ? theme.notch.accent : theme.nookForeground.opacity(0.75))
                .lineLimit(1)
            DotTime(text: DotClock.time(zone, at: date), date: date,
                    lit: theme.nookForeground, unlit: theme.nookForeground.opacity(0.07))
                .frame(width: 74, height: 20)
            Text(pin != nil ? relative(zone, at: date) : date.formatted(.dateTime.weekday(.wide)))
                .font(.system(size: 9, weight: .medium)).foregroundStyle(theme.nookForeground.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.horizontal, 9).padding(.vertical, 7)
        .background(theme.notch.surface.opacity(0.82), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// "+5h · Tomorrow", "Same time", "−8h".
    private func relative(_ zone: TimeZone, at date: Date) -> String {
        let hours = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        var text = hours == 0 ? "Same time" : (hours > 0 ? "+" : "−") + (hours == hours.rounded()
            ? String(Int(abs(hours))) : String(format: "%.1f", abs(hours))) + "h"
        if let day = DotClock.dayOffset(zone, at: date) { text += day == "+1" ? " · Tomorrow" : " · Yesterday" }
        return text
    }

    private var accessibilityText: String {
        let now = Date().addingTimeInterval(offset)
        var parts = places.map { "\(WidgetOptions.placeName($0)) \(DotClock.time(WidgetOptions.zone($0), at: now))" }
        if let pin = options.clockPin { parts.insert("Pinned \(pin.name) \(DotClock.time(TimeZone(identifier: pin.zone), at: now))", at: 0) }
        return parts.joined(separator: ", ")
    }
}

private struct HoverCardWidthKey: PreferenceKey {
    static var defaultValue: CGFloat = 160
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
