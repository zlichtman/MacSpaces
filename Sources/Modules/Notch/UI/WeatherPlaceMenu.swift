import CoreLocation
import SwiftUI

/// The Weather page's location, which is also where you choose it: automatic, one of your Clock
/// places, or a city found by search. "Use My Location" is the only thing here that asks for
/// Location, and only when it's never been answered.
struct WeatherPlaceMenu: View {
    @ObservedObject var service: WeatherService
    var onEditingChanged: (Bool) -> Void = { _ in }
    @ObservedObject private var options = WidgetOptions.shared
    @State private var searching = false

    private var places: [String] { options.clockPlaces.filter { $0 != WidgetOptions.local } }

    var body: some View {
        NookMenu {
            NookMenuRow("Automatic", selected: service.place == nil) { service.setPlace(nil) }
            if !places.isEmpty {
                NookMenuDivider()
                ForEach(places, id: \.self) { place in
                    NookMenuRow(WidgetOptions.placeName(place), selected: service.place == place) { service.setPlace(place) }
                }
            }
            NookMenuDivider()
            NookMenuRow("Search for a City") { searching = true }
            if service.canAskForLocation {
                NookMenuRow("Use My Location") {
                    service.setPlace(nil)
                    service.stop()
                    service.startIfNeeded()
                }
            }
        } label: {
            HStack(spacing: 4) {
                // A fixed box and height: Automatic's arrow and a city's pin never move what's below.
                Image(systemName: service.place == nil ? "location.fill" : "mappin")
                    .frame(width: 14, height: 14)
                Text(service.locationName ?? "Local weather").lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 7, weight: .bold))
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(.secondary)
            .frame(height: 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .accessibilityLabel("Weather location, \(service.locationName ?? "automatic")")
        .nookPopover(isPresented: $searching, arrowEdge: .bottom) {
            WeatherPlaceSearch { place in
                service.setPlace(place)
                searching = false
            }
        }
        .onChange(of: searching) { onEditingChanged($0) }
        .onDisappear { onEditingChanged(false) }
    }
}

/// A field and its results: cities the Clock knows at once, then Apple's geocoder a moment after
/// typing stops, as the Clock page does.
struct WeatherPlaceSearch: View {
    let choose: (String) -> Void
    @State private var query = ""
    @State private var found: [Result] = []
    @State private var lookup: Task<Void, Never>?
    private static let geocoder = CLGeocoder()

    private struct Result: Identifiable {
        let title: String
        let place: String
        var id: String { place }
    }

    private var results: [Result] {
        let zones = ClockGeography.search(query).prefix(4).map { Result(title: "\($0.name) · \($0.country)", place: $0.identifier) }
        let names = Set(zones.map(\.title))
        return Array((zones + found.filter { !names.contains($0.title) }).prefix(6))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            NookTextField("City", text: $query, focusOnAppear: true)
                .padding(.bottom, 4)
            ForEach(results) { result in
                NookMenuRow(result.title) { choose(result.place) }
            }
        }
        .padding(12)
        .frame(width: 240)
        .onChange(of: query, perform: search)
        .onSubmit { if let first = results.first { choose(first.place) } }
        .onDisappear { lookup?.cancel() }
    }

    private func search(_ text: String) {
        lookup?.cancel()
        found = []
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.count >= 2 else { return }
        lookup = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard !Task.isCancelled else { return }
            Self.geocoder.cancelGeocode()
            Self.geocoder.geocodeAddressString(trimmed) { placemarks, _ in
                let matches = (placemarks ?? []).compactMap { mark -> Result? in
                    guard let zone = mark.timeZone, let location = mark.location else { return nil }
                    let name = mark.locality ?? mark.name ?? mark.administrativeArea ?? trimmed
                    let region = [mark.administrativeArea, mark.country].compactMap { $0 }.filter { $0 != name }
                    return Result(title: ([name] + region.prefix(1)).joined(separator: " · "),
                                  place: WidgetOptions.namedPlace(zone: zone.identifier, name: name,
                                                                  latitude: location.coordinate.latitude,
                                                                  longitude: location.coordinate.longitude))
                }
                Task { @MainActor in
                    guard query.trimmingCharacters(in: .whitespaces) == trimmed else { return }
                    found = matches
                }
            }
        }
    }
}
