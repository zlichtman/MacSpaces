import SwiftUI
import CoreLocation

/// The Clock page: the Map clock with a time scrubber ("what time is it there at 3 pm
/// here?"), your places as chips with their times, and a search to add more: time-zone
/// cities and countries at once, then any town, state or address from Apple's geocoder
/// (kept under its own name and position). Hover the map to read any spot; click to add it.
struct ClockPage: View {
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var offsetHours: Double = 0
    @State private var adding = false
    @State private var query = ""
    @State private var found: [Result] = []
    @State private var lookup: Task<Void, Never>?
    @State private var searching = false
    @State private var hoveredChip: String?
    private static let geocoder = CLGeocoder()

    /// A search result: what to show, and the place string to save.
    private struct Result: Identifiable {
        let title: String
        let place: String
        var id: String { place }
    }
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 6) {
            MapClock(offset: offsetHours * 3600, addsOnTap: true)
            HStack(spacing: 14) {
                // The scrubber gives up some width when the places bar is crowded.
                scrubber.frame(width: options.clockPlaces.filter { $0 != WidgetOptions.local }.count >= 4 ? 150 : 210)
                if adding { search } else { placesRow }
            }
            .frame(height: 34)
        }
        .padding(.horizontal, 14).padding(.bottom, 8)
        .onChange(of: searchFocused) { onEditingChanged($0) }
    }

    // MARK: Time

    private var scrubber: some View {
        TimelineView(.everyMinute) { context in
            let shifted = context.date.addingTimeInterval(offsetHours * 3600)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(offsetHours == 0 ? "NOW" : offsetText).font(.system(size: 9, weight: .bold)).tracking(0.6)
                        .foregroundStyle(offsetHours == 0 ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.notch.accent))
                    Text(shifted.formatted(date: .omitted, time: .shortened) + " here")
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).monospacedDigit()
                    Spacer(minLength: 0)
                    if offsetHours != 0 {
                        Button("Now") { withAnimation(Design.spring()) { offsetHours = 0 } }
                            .buttonStyle(WidgetChipStyle(height: 16))
                            .help("Back to the current time")
                    }
                }
                Slider(value: $offsetHours, in: -12...12, step: 0.25)
                    .controlSize(.mini)
                    .help("Move every clock up to 12 hours earlier or later")
                    .accessibilityLabel("Time shift")
                    .accessibilityValue(offsetHours == 0 ? "Now" : offsetText)
            }
        }
    }

    private var offsetText: String {
        let minutes = Int((abs(offsetHours) * 60).rounded())
        let text = minutes % 60 == 0 ? "\(minutes / 60)H" : "\(minutes / 60)H \(minutes % 60)M"
        return (offsetHours > 0 ? "+" : "−") + text
    }

    // MARK: Places

    private var placesRow: some View {
        TimelineView(.everyMinute) { context in
            let date = context.date.addingTimeInterval(offsetHours * 3600)
            let places = options.clockPlaces.filter { $0 != WidgetOptions.local }
            // Full chips when they fit; then tighter ones whose remove button shows on
            // hover; then Add as just "+"; only then a scroll. A chip never sits cut off by Add.
            ViewThatFits(in: .horizontal) {
                row(places, date: date, tight: false, iconAdd: false)
                row(places, date: date, tight: true, iconAdd: false)
                row(places, date: date, tight: true, iconAdd: true)
                HStack(spacing: 6) {
                    ScrollView(.horizontal, showsIndicators: false) { chips(places, date: date, tight: true) }
                    addButton(icon: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func row(_ places: [String], date: Date, tight: Bool, iconAdd: Bool) -> some View {
        HStack(spacing: 6) {
            chips(places, date: date, tight: tight)
            Spacer(minLength: 0)
            addButton(icon: iconAdd)
        }
    }

    @ViewBuilder private func addButton(icon: Bool) -> some View {
        if options.clockPlaces.count < WidgetOptions.maxPlaces {
            Button { adding = true; searchFocused = true } label: {
                if icon {
                    Image(systemName: "plus").font(.system(size: 10, weight: .semibold))
                } else {
                    Label("Add", systemImage: "plus").font(.system(size: 10, weight: .semibold))
                }
            }
            .buttonStyle(WidgetChipStyle(prominent: options.clockPlaces.isEmpty, height: 22))
            .help("Add a city or country")
            .accessibilityLabel("Add a place")
        }
    }

    private func chips(_ places: [String], date: Date, tight: Bool) -> some View {
        HStack(spacing: tight ? 4 : 6) {
            ForEach(places, id: \.self) { chip($0, date: date, tight: tight) }
        }
        .fixedSize()
    }

    private func chip(_ place: String, date: Date, tight: Bool) -> some View {
        // The first saved place in this Mac's time zone is where you are, marked like its map pin.
        let current = options.clockPlaces.first(where: WidgetOptions.isCurrent) == place
        return HStack(spacing: 5) {
            if current {
                Image(systemName: "location.fill").font(.system(size: 7, weight: .bold))
                    .foregroundStyle(theme.notch.accent)
                    .accessibilityLabel("Current location")
            }
            Text(WidgetOptions.placeName(place).uppercased())
                .font(.system(size: 9, weight: .semibold)).tracking(0.5).lineLimit(1)
                .foregroundStyle(current ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(.primary))
            Text(DotClock.time(WidgetOptions.zone(place), at: date))
                .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
            if !tight || hoveredChip == place {
                Button { options.clockPlaces.removeAll { $0 == place } } label: {
                    Image(systemName: "xmark").font(.system(size: 7, weight: .bold))
                }
                .buttonStyle(.plain).foregroundStyle(.secondary)
                .help("Remove \(WidgetOptions.placeName(place))")
            }
        }
        .padding(.horizontal, tight ? 7 : 9).frame(height: 22)
        .background(theme.nookForeground.opacity(0.08), in: Capsule())
        .onHover { hoveredChip = $0 ? place : (hoveredChip == place ? nil : hoveredChip) }
    }

    // MARK: Search

    private var search: some View {
        HStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "magnifyingglass").font(.system(size: 9)).foregroundStyle(.secondary)
                TextField("City or country", text: $query)
                    .textFieldStyle(.plain).font(.system(size: 11))
                    .focused($searchFocused)
                    .onSubmit { if let first = results.first { add(first) } }
                    .onExitCommand { close() }
                    .onChange(of: query) { search(for: $0) }
            }
            .padding(.horizontal, 8).frame(width: 130, height: 22)
            .background(theme.nookForeground.opacity(0.08), in: Capsule())
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    ForEach(results) { result in
                        Button { add(result) } label: {
                            Text(result.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                        }
                        .buttonStyle(WidgetChipStyle(height: 22))
                    }
                    if !query.isEmpty && results.isEmpty {
                        Text(searching ? "Searching…" : "No match").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                }
            }
            Button { close() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(WidgetChipStyle(height: 22)).help("Done")
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
    }

    private func close() {
        lookup?.cancel()
        found = []
        searching = false
        adding = false
        query = ""
        searchFocused = false
    }
}
