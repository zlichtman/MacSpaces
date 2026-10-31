import SwiftUI
import CoreLocation

/// The Clock page: a globe of your places on the left (`GlobeClock`: drag to spin,
/// click a dot to add it), and on the right your time, a search for places (time-zone
/// cities and countries at once, then any town, state or address from Apple's
/// geocoder) and your places with their times. Select places and Match up shows when
/// their working hours line up with yours (`TimeOverlap`).
struct ClockPage: View {
    var onEditingChanged: (Bool) -> Void = { _ in }
    /// Debug captures: places chosen, and Match up open, from the start.
    var previewSelection: [String] = []
    var previewMatching = false
    /// Debug captures: the place the globe faces at first.
    var previewFocus: String?
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var latitude = 25.0
    @State private var longitude = ClockGeography.position(of: WidgetOptions.local)?.longitude ?? 0
    @State private var selected: Set<String> = []
    @State private var matching = false
    @State private var query = ""
    @State private var found: [Result] = []
    @State private var lookup: Task<Void, Never>?
    @State private var searching = false
    @State private var hoveredRow: String?
    @FocusState private var searchFocused: Bool
    private static let geocoder = CLGeocoder()
#if DEBUG
    /// The website tour: a place (`String`) ticks or unticks its circle, `true` or `false`
    /// opens or closes Match up, as the circle and the button do.
    static let demoAction = Notification.Name("MacSpaces.ClockPage.demoAction")
#endif

    /// A search result: what to show, and the place string to save.
    private struct Result: Identifiable {
        let title: String
        let place: String
        var id: String { place }
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 18) {
                GlobeClock(latitude: $latitude, longitude: $longitude, selected: selected)
                    .frame(width: min(proxy.size.height, proxy.size.width * 0.5), height: proxy.size.height)
                TimelineView(.everyMinute) { context in
                    VStack(alignment: .leading, spacing: 10) {
                        here(at: Design.clockDate(context.date))
                        if matching {
                            matchUp(at: Design.clockDate(context.date))
                        } else {
                            searchField
                            if query.trimmingCharacters(in: .whitespaces).isEmpty {
                                placesList(at: Design.clockDate(context.date))
                            } else {
                                resultsList
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10)
        .onAppear {
            if !previewSelection.isEmpty { selected = Set(previewSelection); matching = previewMatching }
            if let previewFocus, let spot = ClockGeography.position(of: previewFocus) {
                longitude = spot.longitude; latitude = min(max(spot.latitude * 0.6, GlobeProjection.tilt.lowerBound), GlobeProjection.tilt.upperBound)
            }
        }
        .onChange(of: searchFocused) { onEditingChanged($0) }
#if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: Self.demoAction)) { note in
            if let place = note.object as? String { toggle(place) }
            if let open = note.object as? Bool { withAnimation(Design.spring()) { matching = open } }
        }
#endif
        .onChange(of: options.clockPlaces) { places in selected.formIntersection(places) }
    }

    // MARK: Here

    /// Where you are, large: its name, time and day. Clicking it turns the globe home.
    private func here(at date: Date) -> some View {
        let current = options.clockPlaces.first(where: WidgetOptions.isCurrent) ?? WidgetOptions.local
        return VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Image(systemName: "location.fill").font(.system(size: 8, weight: .bold)).foregroundStyle(theme.notch.accent)
                Text(WidgetOptions.placeName(current).uppercased()).font(.system(size: 9, weight: .bold)).tracking(0.6)
                    .foregroundStyle(.secondary)
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(date.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 30, weight: .bold, design: .rounded)).monospacedDigit()
                Text(date.formatted(.dateTime.weekday(.wide).month(.abbreviated).day()))
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            }
            .lineLimit(1).minimumScaleFactor(0.7)
        }
        .contentShape(Rectangle())
        .onTapGesture { spin(to: current) }
        .accessibilityElement(children: .combine)
    }

    // MARK: Places

    /// Your other places: click one to turn the globe to it; the circle selects it for
    /// Match up; × removes it (on hover). Only the one place standing for "here" is left
    /// out; other places in this time zone (a town clicked nearby) are listed.
    private func placesList(at date: Date) -> some View {
        let current = options.clockPlaces.first(where: WidgetOptions.isCurrent) ?? WidgetOptions.local
        let places = options.clockPlaces.filter { $0 != current && $0 != WidgetOptions.local }
        return VStack(alignment: .leading, spacing: 6) {
            if places.isEmpty {
                Text("Search, or click the globe, to add places.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(spacing: 3) {
                        ForEach(places, id: \.self) { row($0, date: date) }
                    }
                }
                HStack {
                    Text(selected.isEmpty ? "Select places to find a time." : "\(selected.count) selected")
                        .font(.system(size: 10)).foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    Button { withAnimation(Design.spring()) { matching = true } } label: {
                        Label("Match up", systemImage: "calendar.badge.clock").font(.system(size: 10, weight: .semibold))
                    }
                    .buttonStyle(WidgetChipStyle(prominent: !selected.isEmpty, height: 24))
                    .disabled(selected.isEmpty)
                    .help("When these places' working hours line up with yours")
                }
            }
        }
    }

    private func row(_ place: String, date: Date) -> some View {
        let zone = WidgetOptions.zone(place) ?? .current
        let isSelected = selected.contains(place)
        return HStack(spacing: 8) {
            Button { toggle(place) } label: {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 12)).foregroundStyle(isSelected ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(.secondary))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(isSelected ? "Deselect \(WidgetOptions.placeName(place))" : "Select \(WidgetOptions.placeName(place))")
            VStack(alignment: .leading, spacing: 0) {
                Text(WidgetOptions.placeName(place).uppercased()).font(.system(size: 9, weight: .semibold)).tracking(0.5).lineLimit(1)
                Text(GlobeClock.relative(zone, at: date)).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 4)
            Text(GlobeClock.time(zone, at: date)).font(.system(size: 14, weight: .bold, design: .rounded)).monospacedDigit()
            Button { options.clockPlaces.removeAll { $0 == place } } label: {
                Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
            }
            .buttonStyle(.plain).foregroundStyle(.secondary)
            .opacity(hoveredRow == place ? 1 : 0)
            .help("Remove \(WidgetOptions.placeName(place))")
        }
        .padding(.horizontal, 8).frame(height: 32)
        .background(theme.nookForeground.opacity(isSelected ? 0.1 : 0.05), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture { spin(to: place) }
        .onHover { hoveredRow = $0 ? place : (hoveredRow == place ? nil : hoveredRow) }
    }

    private func toggle(_ place: String) {
        if selected.contains(place) { selected.remove(place) } else { selected.insert(place) }
    }

    /// Turns the globe to face a place, the short way round.
    private func spin(to place: String) {
        guard let spot = ClockGeography.position(of: place) else { return }
        let target = GlobeProjection.nearestLongitude(spot.longitude, from: longitude)
        let tilt = min(max(spot.latitude * 0.6, GlobeProjection.tilt.lowerBound), GlobeProjection.tilt.upperBound)
        withAnimation(reduceMotion || theme.reduceMotion ? nil : .spring(response: 0.7, dampingFraction: 0.9)) {
            longitude = target; latitude = tilt
        }
    }

    // MARK: Match up

    /// A row per place across today here (half hours): its working hours shaded, the
    /// times that suit everyone in the accent, and the best one in words.
    private func matchUp(at date: Date) -> some View {
        let current = options.clockPlaces.first(where: WidgetOptions.isCurrent) ?? WidgetOptions.local
        let places = [current] + options.clockPlaces.filter(selected.contains)
        let zones = places.map { WidgetOptions.zone($0) ?? .current }
        let result = TimeOverlap.matchUp(zones, on: date)
        let slots = TimeOverlap.slots(on: date, here: .current)
        let together = Set(slots.filter { slot in result.windows.contains { slot >= $0.start && slot < $0.end } })
        let hours = result.relaxed ? TimeOverlap.wakingHours : TimeOverlap.workingHours
        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("MATCH UP").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                Button("Done") { withAnimation(Design.spring()) { matching = false } }
                    .buttonStyle(WidgetChipStyle(height: 22))
            }
            ForEach(Array(zip(places, zones)), id: \.0) { place, zone in
                VStack(alignment: .leading, spacing: 2) {
                    Text(WidgetOptions.placeName(place).uppercased()).font(.system(size: 8, weight: .semibold)).tracking(0.5)
                        .foregroundStyle(.secondary).lineLimit(1)
                    HStack(spacing: 1) {
                        ForEach(slots, id: \.self) { slot in
                            Rectangle()
                                .fill(together.contains(slot) ? AnyShapeStyle(theme.notch.accent)
                                      : TimeOverlap.isWithin(hours, at: slot, in: zone) ? AnyShapeStyle(theme.nookForeground.opacity(0.3))
                                      : AnyShapeStyle(theme.nookForeground.opacity(0.07)))
                        }
                    }
                    .frame(height: 9)
                    .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }
            }
            HStack(spacing: 0) {
                ForEach(Array(["12 AM", "6 AM", "12 PM", "6 PM"].enumerated()), id: \.offset) { _, label in
                    Text(label).font(.system(size: 7)).foregroundStyle(.tertiary)
                    Spacer(minLength: 0)
                }
            }
            Text(summary(result, places: Array(zip(places, zones))))
                .font(.system(size: 11, weight: .medium)).fixedSize(horizontal: false, vertical: true)
        }
    }

    /// "Best: 9 AM–12 PM here (3–6 PM London)."
    private func summary(_ result: TimeOverlap.Result, places: [(String, TimeZone)]) -> String {
        guard let best = result.best else { return "No time today works for everyone, even outside working hours." }
        func span(_ zone: TimeZone) -> String {
            var style = Date.FormatStyle(date: .omitted, time: .shortened)
            style.timeZone = zone
            return "\(best.start.formatted(style))–\(best.end.formatted(style))"
        }
        let others = places.dropFirst().map { "\(span($0.1)) \(WidgetOptions.placeName($0.0))" }.joined(separator: ", ")
        let lead = result.relaxed ? "No working hours line up. Awake for everyone:" : "Best:"
        return "\(lead) \(span(.current)) here" + (others.isEmpty ? "." : " (\(others)).")
    }

    // MARK: Search

    private var searchField: some View {
        let full = options.clockPlaces.count >= WidgetOptions.maxPlaces
        return HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 10)).foregroundStyle(.secondary)
            TextField(full ? "Remove a place to add more" : "Add a city or country", text: $query)
                .textFieldStyle(.plain).font(.system(size: 11))
                .focused($searchFocused)
                .disabled(full)
                .onSubmit { if let first = results.first { add(first) } }
                .onExitCommand { close() }
                .onChange(of: query) { search(for: $0) }
            if !query.isEmpty {
                Button { close() } label: { Image(systemName: "xmark.circle.fill").font(.system(size: 10)) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 9).frame(height: 26)
        .background(theme.nookForeground.opacity(0.08), in: Capsule())
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(results) { result in
                Button { add(result) } label: {
                    HStack {
                        Text(result.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                        Spacer(minLength: 0)
                        Image(systemName: "plus").font(.system(size: 9, weight: .semibold)).foregroundStyle(theme.notch.accent)
                    }
                    .padding(.horizontal, 8).frame(height: 26)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if results.isEmpty {
                Text(searching ? "Searching…" : "No match").font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 8)
            }
        }
    }

    /// Time-zone cities first (instant, offline), then geocoded places.
    private var results: [Result] {
        let zones = ClockGeography.search(query).prefix(4).map { Result(title: "\($0.name) · \($0.country)", place: $0.identifier) }
        let names = Set(zones.map(\.title))
        let all = zones + found.filter { !names.contains($0.title) }
        return Array(all.filter { !options.clockPlaces.contains($0.place) }.prefix(6))
    }

    /// Asks Apple's geocoder a moment after typing stops, for places zone.tab doesn't name.
    private func search(for text: String) {
        lookup?.cancel()
        found = []
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        searching = trimmed.count >= 2
        guard searching else { return }
        lookup = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            Self.geocoder.cancelGeocode()
            Self.geocoder.geocodeAddressString(trimmed) { placemarks, _ in
                let results = (placemarks ?? []).compactMap { mark -> Result? in
                    guard let zone = mark.timeZone, let location = mark.location else { return nil }
                    let name = mark.locality ?? mark.name ?? mark.administrativeArea ?? trimmed
                    let region = [mark.administrativeArea, mark.country].compactMap { $0 }.filter { $0 != name }
                    let title = ([name] + region.prefix(1)).joined(separator: " · ")
                    return Result(title: title, place: WidgetOptions.namedPlace(zone: zone.identifier, name: name,
                        latitude: location.coordinate.latitude, longitude: location.coordinate.longitude))
                }
                Task { @MainActor in
                    guard query.trimmingCharacters(in: .whitespaces) == trimmed else { return }
                    found = results
                    searching = false
                }
            }
        }
    }

    private func add(_ result: Result) {
        options.addPlace(result.place)
        close()
        spin(to: result.place)
    }

    private func close() {
        lookup?.cancel()
        found = []
        searching = false
        query = ""
        searchFocused = false
    }
}
