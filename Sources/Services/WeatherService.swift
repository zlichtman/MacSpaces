import Foundation
import CoreLocation
import Combine

struct WeatherSnapshot: Equatable {
    var temperature: Double
    var weatherCode: Int
    var high: Double
    var low: Double

    /// SF Symbol for a WMO weather interpretation code.
    var symbolName: String {
        switch weatherCode {
        case 0: return "sun.max"
        case 1, 2: return "cloud.sun"
        case 3: return "cloud"
        case 45, 48: return "cloud.fog"
        case 51...57: return "cloud.drizzle"
        case 61...67, 80...82: return "cloud.rain"
        case 71...77, 85, 86: return "cloud.snow"
        case 95...99: return "cloud.bolt.rain"
        default: return "cloud"
        }
    }

    var conditionName: String {
        switch weatherCode {
        case 0: return "Clear"
        case 1, 2: return "Partly Cloudy"
        case 3: return "Cloudy"
        case 45, 48: return "Fog"
        case 51...57: return "Drizzle"
        case 61...67, 80...82: return "Rain"
        case 71...77, 85, 86: return "Snow"
        case 95...99: return "Thunderstorms"
        default: return "Current Conditions"
        }
    }
}

/// Local weather via the free Open-Meteo API (no key required).
/// Uses CoreLocation when authorized; falls back to an IP-based lookup.
@MainActor
final class WeatherService: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var errorText: String?

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var requestTask: Task<Void, Never>?
    private var started = false

    /// Shared session with a bounded timeout so a stalled request cannot hang
    /// until the next 15-minute refresh.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

    /// Called lazily by the weather widget so location permission is only
    /// requested when the widget is actually used.
    func startIfNeeded() {
        guard !started else { return }
        started = true

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        locationManager.requestWhenInUseAuthorization()
        requestLocationOrFallback()

        timer = Timer.scheduledTimer(withTimeInterval: 15 * 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.requestLocationOrFallback()
            }
        }
    }

    private func requestLocationOrFallback() {
        guard started else { return }
        let status = locationManager.authorizationStatus
        if status == .authorizedAlways || status == .authorized {
            locationManager.requestLocation()
        } else {
            requestTask?.cancel()
            requestTask = Task { await self.fetchViaIPLocation() }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let coordinate = locations.last?.coordinate else { return }
        Task { @MainActor in
            guard self.started else { return }
            self.requestTask?.cancel()
            self.requestTask = Task {
                await self.fetchForecast(
                    latitude: coordinate.latitude,
                    longitude: coordinate.longitude
                )
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            guard self.started else { return }
            self.requestTask?.cancel()
            self.requestTask = Task { await self.fetchViaIPLocation() }
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard self.started else { return }
            self.requestLocationOrFallback()
        }
    }

    // MARK: - Fetching

    func stop() {
        started = false
        timer?.invalidate()
        timer = nil
        requestTask?.cancel()
        requestTask = nil
        locationManager.stopUpdatingLocation()
    }

    private func fetchViaIPLocation() async {
        // ipapi.co returns approximate coordinates for the current IP; good
        // enough for a weather forecast without any permission prompt.
        guard let url = URL(string: "https://ipapi.co/json/"),
              let (data, _) = try? await Self.session.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = object["latitude"] as? Double,
              let lon = object["longitude"] as? Double else {
            guard started, !Task.isCancelled else { return }
            errorText = "Location unavailable"
            return
        }
        guard started, !Task.isCancelled else { return }
        await fetchForecast(latitude: lat, longitude: lon)
    }

    private func fetchForecast(latitude: Double, longitude: Double) async {
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else {
            errorText = "Forecast failed"
            return
        }
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "forecast_days", value: "1"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
            }
            struct Daily: Decodable {
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
            }
            let current: Current
            let daily: Daily
        }

        guard let url = components.url else {
            errorText = "Forecast failed"
            return
        }

        do {
            let (data, _) = try await Self.session.data(from: url)
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard started, !Task.isCancelled else { return }
            snapshot = WeatherSnapshot(temperature: response.current.temperature_2m,
                                       weatherCode: response.current.weather_code,
                                       high: response.daily.temperature_2m_max.first ?? 0,
                                       low: response.daily.temperature_2m_min.first ?? 0)
            errorText = nil
        } catch {
            guard started, !Task.isCancelled else { return }
            errorText = "Forecast failed"
        }
    }

    deinit {
        timer?.invalidate()
        requestTask?.cancel()
    }
}
