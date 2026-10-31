import Foundation
import CoreLocation
import Combine

struct WeatherSnapshot: Equatable, Codable, Sendable {
    struct Day: Equatable, Identifiable, Codable, Sendable {
        var date: Date
        var weatherCode: Int
        var high: Double
        var low: Double
        var id: Date { date }
        var symbolName: String { WeatherSnapshot.symbolName(for: weatherCode) }
    }

    struct Hour: Equatable, Identifiable, Codable, Sendable {
        var date: Date
        var weatherCode: Int
        var temperature: Double
        var isDay: Bool
        var precipitationChance: Int?
        var id: Date { date }
        var symbolName: String { WeatherSnapshot.symbolName(for: weatherCode, isDay: isDay) }
    }

    var temperature: Double
    var weatherCode: Int
    var high: Double
    var low: Double
    /// Upcoming days after today, in order. Empty until a forecast loads.
    var upcoming: [Day] = []
    /// The next hours, starting with the current one.
    var hourly: [Hour] = []
    var feelsLike: Double?
    var humidity: Int?
    var windSpeed: Double?
    var precipitationChance: Int?
    var sunrise: Date?
    var sunset: Date?
    var isDay = true

    var symbolName: String { Self.symbolName(for: weatherCode, isDay: isDay) }

    /// Clear and partly cloudy skies get night symbols after sunset.
    static func symbolName(for weatherCode: Int, isDay: Bool) -> String {
        guard !isDay else { return symbolName(for: weatherCode) }
        switch weatherCode {
        case 0: return "moon.stars"
        case 1, 2: return "cloud.moon"
        default: return symbolName(for: weatherCode)
        }
    }

    /// SF Symbol for a WMO weather interpretation code.
    static func symbolName(for weatherCode: Int) -> String {
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
    /// City or area name for the forecast, when known.
    @Published private(set) var locationName: String?

    private let locationManager = CLLocationManager()
    private var timer: Timer?
    private var requestTask: Task<Void, Never>?
    private var started = false
    private var fetchedAt: Date?
    private var forecastUnit: WidgetOptions.TemperatureUnit?
    private static let refreshInterval: TimeInterval = 15 * 60
    private var lastCoordinate: (latitude: Double, longitude: Double)?
    private var unitObserver: AnyCancellable?
    private let cacheURL: URL?
    private let networkSession: URLSession
    private var cacheRestore: Task<Void, Never>?
    private nonisolated static let cacheQueue = DispatchQueue(label: "dev.opensource.MacSpaces.weather-cache", qos: .utility)

    private struct CachedForecast: Codable, Sendable {
        let version: Int
        let snapshot: WeatherSnapshot
        let fetchedAt: Date
        let unit: String
        let locationName: String?
    }

    private static var defaultCacheURL: URL? {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return nil }
        return FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("MacSpaces", isDirectory: true).appendingPathComponent("weather-v1.json")
    }

    override convenience init() { self.init(cacheURL: Self.defaultCacheURL) }

    init(cacheURL: URL?, networkSession: URLSession? = nil) {
        self.cacheURL = cacheURL
        self.networkSession = networkSession ?? Self.session
        super.init()
        guard let cacheURL else { return }
        cacheRestore = Task { [weak self] in
            let cached: CachedForecast? = await withCheckedContinuation { continuation in
                Self.cacheQueue.async {
                    let record = (try? Data(contentsOf: cacheURL)).flatMap { try? JSONDecoder().decode(CachedForecast.self, from: $0) }
                    continuation.resume(returning: record)
                }
            }
            guard let self, let cached, cached.version == 1,
                  cached.unit == WidgetOptions.shared.temperatureUnit.rawValue,
                  (0..<(6 * 60 * 60)).contains(Date().timeIntervalSince(cached.fetchedAt)),
                  self.snapshot == nil else { return }
            self.snapshot = cached.snapshot
            self.fetchedAt = cached.fetchedAt
            self.forecastUnit = WidgetOptions.TemperatureUnit(rawValue: cached.unit)
            self.locationName = cached.locationName
            let nextPoll = cached.fetchedAt.addingTimeInterval(Self.refreshInterval)
            if nextPoll > Date() { self.timer?.fireDate = nextPoll }
        }
    }

    private func persistForecast() {
        guard let cacheURL, let snapshot, let fetchedAt, let forecastUnit else { return }
        let record = CachedForecast(version: 1, snapshot: snapshot, fetchedAt: fetchedAt,
                                    unit: forecastUnit.rawValue, locationName: locationName)
        Self.cacheQueue.async {
            do {
                let data = try JSONEncoder().encode(record)
                try FileManager.default.createDirectory(at: cacheURL.deletingLastPathComponent(), withIntermediateDirectories: true)
                try data.write(to: cacheURL, options: .atomic)
            } catch { /* A cache failure must not interrupt live weather. */ }
        }
    }

    /// Timer refreshes are due even if the initial network fetch finished after
    /// the poll clock started. Opening a page still reuses a fresh forecast.
    func refresh() { requestLocationOrFallback(force: true) }

    /// Shared session with a bounded timeout so a stalled request cannot hang
    /// until the next 15-minute refresh.
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        return URLSession(configuration: configuration)
    }()

#if DEBUG
    var locationAuthorizationOverride: CLAuthorizationStatus?
    var nextRefreshDate: Date? { timer?.fireDate }

    func setPreviewSnapshot(_ value: WeatherSnapshot) {
        stop()
        snapshot = value
        errorText = nil
        started = true
    }
#endif

    /// Called lazily by the weather widget so location permission is only
    /// requested when the widget is actually used.
    func startIfNeeded(allowLocationPrompt: Bool = true) {
        if allowLocationPrompt, locationManager.authorizationStatus == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
        }
        guard !started else { return }
        started = true
        // A unit change refetches instead of converting, so highs and lows
        // stay exactly what the forecast service reports.
        unitObserver = WidgetOptions.shared.$temperatureUnit.dropFirst().sink { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self, self.started else { return }
                if let coordinate = self.lastCoordinate {
                    self.requestTask?.cancel()
                    self.requestTask = Task { await self.fetchForecast(latitude: coordinate.latitude, longitude: coordinate.longitude) }
                } else {
                    self.requestLocationOrFallback(force: true)
                }
            }
        }

        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyKilometer
        let age = fetchedAt.map { Date().timeIntervalSince($0) } ?? .infinity
        let fresh = snapshot != nil && forecastUnit == WidgetOptions.shared.temperatureUnit
            && age >= 0 && age < Self.refreshInterval
        if !fresh {
            requestLocationOrFallback()
        }

        let poll = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.refresh()
            }
        }
        poll.fireDate = Date().addingTimeInterval(fresh ? max(1, Self.refreshInterval - age) : Self.refreshInterval)
        RunLoop.main.add(poll, forMode: .common)
        timer = poll
    }

    private func requestLocationOrFallback(force: Bool = false) {
        guard started else { return }
        requestTask?.cancel()
        requestTask = Task { [weak self] in
            guard let self else { return }
            await self.cacheRestore?.value
            guard self.started, !Task.isCancelled else { return }
            if !force, let fetchedAt = self.fetchedAt, self.snapshot != nil,
               self.forecastUnit == WidgetOptions.shared.temperatureUnit,
               (0..<Self.refreshInterval).contains(Date().timeIntervalSince(fetchedAt)) { return }
#if DEBUG
            let status = self.locationAuthorizationOverride ?? self.locationManager.authorizationStatus
#else
            let status = self.locationManager.authorizationStatus
#endif
            if status == .authorizedAlways || status == .authorized {
                self.locationManager.requestLocation()
            } else {
                await self.fetchViaIPLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        let coordinate = location.coordinate
        Task { @MainActor in
            guard self.started else { return }
            // Name the place for the Weather page; the forecast never waits on it.
            CLGeocoder().reverseGeocodeLocation(location) { placemarks, _ in
                let name = placemarks?.first?.locality
                Task { @MainActor in if self.started, let name { self.locationName = name } }
            }
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
        unitObserver = nil
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
              let (data, _) = try? await networkSession.data(from: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let lat = object["latitude"] as? Double,
              let lon = object["longitude"] as? Double else {
            guard started, !Task.isCancelled else { return }
            errorText = "Location unavailable"
            return
        }
        guard started, !Task.isCancelled else { return }
        locationName = (object["city"] as? String).flatMap { $0.isEmpty ? nil : $0 }
        await fetchForecast(latitude: lat, longitude: lon)
    }

    private func fetchForecast(latitude: Double, longitude: Double) async {
        guard var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast") else {
            errorText = "Forecast failed"
            return
        }
        let unit = WidgetOptions.shared.temperatureUnit
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,weather_code,apparent_temperature,relative_humidity_2m,wind_speed_10m,is_day"),
            URLQueryItem(name: "hourly", value: "temperature_2m,weather_code,is_day,precipitation_probability"),
            URLQueryItem(name: "forecast_hours", value: "12"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,sunrise,sunset"),
            URLQueryItem(name: "forecast_days", value: "5"),
            URLQueryItem(name: "temperature_unit", value: unit.rawValue),
            URLQueryItem(name: "wind_speed_unit", value: unit == .fahrenheit ? "mph" : "kmh"),
            URLQueryItem(name: "timezone", value: "auto"),
        ]

        struct Response: Decodable {
            struct Current: Decodable {
                let temperature_2m: Double
                let weather_code: Int
                let apparent_temperature: Double?
                let relative_humidity_2m: Double?
                let wind_speed_10m: Double?
                let is_day: Int?
            }
            struct Hourly: Decodable {
                let time: [String]?
                let temperature_2m: [Double]?
                let weather_code: [Int]?
                let is_day: [Int]?
                let precipitation_probability: [Int?]?
            }
            struct Daily: Decodable {
                let time: [String]?
                let weather_code: [Int]?
                let temperature_2m_max: [Double]
                let temperature_2m_min: [Double]
                let precipitation_probability_max: [Int?]?
                let sunrise: [String]?
                let sunset: [String]?
            }
            let utc_offset_seconds: Int?
            let current: Current
            let hourly: Hourly?
            let daily: Daily
        }

        guard let url = components.url else {
            errorText = "Forecast failed"
            return
        }

        do {
            let (data, _) = try await networkSession.data(from: url)
            let response = try JSONDecoder().decode(Response.self, from: data)
            guard started, !Task.isCancelled, unit == WidgetOptions.shared.temperatureUnit else { return }
            lastCoordinate = (latitude, longitude)
            // Open-Meteo returns local wall-clock times for the forecast's
            // own time zone; parse them with that offset.
            let zone = TimeZone(secondsFromGMT: response.utc_offset_seconds ?? 0) ?? .current
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "yyyy-MM-dd"
            dayFormatter.timeZone = zone
            let timeFormatter = DateFormatter()
            timeFormatter.dateFormat = "yyyy-MM-dd'T'HH:mm"
            timeFormatter.timeZone = zone

            let daily = response.daily
            let count = min(daily.time?.count ?? 0, daily.weather_code?.count ?? 0,
                            daily.temperature_2m_max.count, daily.temperature_2m_min.count)
            let upcoming: [WeatherSnapshot.Day] = count > 1 ? (1..<count).compactMap { index in
                guard let date = dayFormatter.date(from: daily.time![index]) else { return nil }
                return .init(date: date, weatherCode: daily.weather_code![index],
                             high: daily.temperature_2m_max[index], low: daily.temperature_2m_min[index])
            } : []

            var hourly: [WeatherSnapshot.Hour] = []
            if let h = response.hourly, let times = h.time, let temps = h.temperature_2m, let codes = h.weather_code {
                for index in 0..<min(times.count, temps.count, codes.count) {
                    guard let date = timeFormatter.date(from: times[index]) else { continue }
                    hourly.append(.init(date: date, weatherCode: codes[index], temperature: temps[index],
                                        isDay: (h.is_day?[safe: index] ?? 1) == 1,
                                        precipitationChance: h.precipitation_probability?[safe: index] ?? nil))
                }
            }

            let current = response.current
            snapshot = WeatherSnapshot(
                temperature: current.temperature_2m,
                weatherCode: current.weather_code,
                high: daily.temperature_2m_max.first ?? 0,
                low: daily.temperature_2m_min.first ?? 0,
                upcoming: upcoming,
                hourly: hourly,
                feelsLike: current.apparent_temperature,
                humidity: current.relative_humidity_2m.map { Int($0.rounded()) },
                windSpeed: current.wind_speed_10m,
                precipitationChance: daily.precipitation_probability_max?.first ?? nil,
                sunrise: daily.sunrise?.first.flatMap(timeFormatter.date(from:)),
                sunset: daily.sunset?.first.flatMap(timeFormatter.date(from:)),
                isDay: (current.is_day ?? 1) == 1)
            fetchedAt = Date()
            forecastUnit = unit
            errorText = nil
            timer?.fireDate = fetchedAt!.addingTimeInterval(Self.refreshInterval)
            persistForecast()
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

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
