import Combine
import CoreLocation
import Foundation

struct WeatherDay: Identifiable, Equatable {
    let id: String
    let date: Date
    let code: Int
    let high: Double
    let low: Double
    let precipChance: Int

    var weekday: String {
        if Calendar.current.isDateInToday(date) { return "Today" }
        if Calendar.current.isDateInTomorrow(date) { return "Tomorrow" }
        return date.formatted(.dateTime.weekday(.wide))
    }

    var symbol: String {
        WeatherSnapshot.symbol(for: code)
    }

    var summary: String {
        WeatherSnapshot.summary(for: code)
    }
}

struct WeatherSnapshot: Equatable {
    var placeName: String
    var latitude: Double
    var longitude: Double
    var temperature: Double
    var feelsLike: Double
    var humidity: Int
    var wind: Double
    var code: Int
    var units: String
    var days: [WeatherDay]

    var symbol: String { Self.symbol(for: code) }
    var summary: String { Self.summary(for: code) }

    var insightContext: String {
        var parts = [
            "Open-Meteo forecast for \(placeName) (\(String(format: "%.2f", latitude)), \(String(format: "%.2f", longitude))).",
            "Now: \(Int(temperature.rounded()))\(units), feels like \(Int(feelsLike.rounded()))\(units), \(summary.lowercased()).",
            "Humidity \(humidity)%. Wind \(Int(wind.rounded())) km/h."
        ]
        parts.append("Next days:")
        for day in days.prefix(7) {
            parts.append("\(day.weekday): \(day.summary), high \(Int(day.high.rounded()))\(units), low \(Int(day.low.rounded()))\(units), rain \(day.precipChance)%.")
        }
        return parts.joined(separator: "\n")
    }

    static func symbol(for code: Int) -> String {
        switch code {
        case 0: return "sun.max.fill"
        case 1, 2: return "cloud.sun.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 51, 53, 55, 56, 57, 61, 63, 65, 66, 67, 80, 81, 82: return "cloud.rain.fill"
        case 71, 73, 75, 77, 85, 86: return "cloud.snow.fill"
        case 95, 96, 99: return "cloud.bolt.rain.fill"
        default: return "cloud.sun.fill"
        }
    }

    static func summary(for code: Int) -> String {
        switch code {
        case 0: return "Clear"
        case 1, 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Fog"
        case 51, 53, 55, 56, 57: return "Drizzle"
        case 61, 63, 65, 66, 67: return "Rain"
        case 71, 73, 75, 77, 85, 86: return "Snow"
        case 80, 81, 82: return "Showers"
        case 95, 96, 99: return "Thunderstorms"
        default: return "Mixed"
        }
    }
}

@MainActor
final class WeatherEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var snapshot: WeatherSnapshot?
    @Published var cityQuery = ""
    @Published var isBusy = false
    @Published var isLocating = false
    @Published var statusText = "Find a city or use your location."
    @Published var errorMessage: String?

    private let manager = CLLocationManager()
    private let defaultsKey = "portalsos.weather.place.v1"
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
        if let stored = UserDefaults.standard.dictionary(forKey: defaultsKey),
           let name = stored["name"] as? String,
           let lat = stored["lat"] as? Double,
           let lon = stored["lon"] as? Double {
            cityQuery = name
            Task { await loadForecast(name: name, latitude: lat, longitude: lon) }
        }
    }

    var insightContext: String? {
        snapshot?.insightContext
    }

    func searchCity() async {
        let query = cityQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard query.count >= 2 else {
            errorMessage = "Type a city name."
            return
        }
        errorMessage = nil
        isBusy = true
        statusText = "Looking up \(query)..."
        do {
            let place = try await geocode(query)
            persist(name: place.name, latitude: place.latitude, longitude: place.longitude)
            await loadForecast(name: place.name, latitude: place.latitude, longitude: place.longitude)
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Could not find that city."
            isBusy = false
        }
    }

    func useCurrentLocation() async {
        errorMessage = nil
        isLocating = true
        statusText = "Finding your location..."
        do {
            let location = try await requestLocation()
            let name = await reverseName(for: location) ?? "Current location"
            cityQuery = name
            persist(name: name, latitude: location.coordinate.latitude, longitude: location.coordinate.longitude)
            await loadForecast(
                name: name,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude
            )
        } catch {
            errorMessage = "Location unavailable. Type a city instead — Open-Meteo does not need GPS."
            statusText = "Use a city name."
        }
        isLocating = false
    }

    private func loadForecast(name: String, latitude: Double, longitude: Double) async {
        isBusy = true
        statusText = "Loading Open-Meteo..."
        do {
            snapshot = try await fetchForecast(name: name, latitude: latitude, longitude: longitude)
            statusText = snapshot?.summary ?? "Forecast ready."
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Open-Meteo request failed."
        }
        isBusy = false
    }

    private func fetchForecast(name: String, latitude: Double, longitude: Double) async throws -> WeatherSnapshot {
        var components = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        components.queryItems = [
            URLQueryItem(name: "latitude", value: String(latitude)),
            URLQueryItem(name: "longitude", value: String(longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,relative_humidity_2m,apparent_temperature,weather_code,wind_speed_10m"),
            URLQueryItem(name: "daily", value: "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max"),
            URLQueryItem(name: "forecast_days", value: "7"),
            URLQueryItem(name: "timezone", value: "auto")
        ]
        guard let url = components.url else { throw WeatherEngineError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("PortalOS/1.0 (hackathon; open-meteo)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherEngineError.server("Open-Meteo did not return a forecast.")
        }
        let decoded = try JSONDecoder().decode(OpenMeteoForecast.self, from: data)
        guard let current = decoded.current else { throw WeatherEngineError.invalidResponse }
        let days = zipDays(decoded.daily)
        return WeatherSnapshot(
            placeName: name,
            latitude: latitude,
            longitude: longitude,
            temperature: current.temperature2m ?? 0,
            feelsLike: current.apparentTemperature ?? current.temperature2m ?? 0,
            humidity: Int((current.relativeHumidity2m ?? 0).rounded()),
            wind: current.windSpeed10m ?? 0,
            code: current.weatherCode ?? 1,
            units: decoded.currentUnits?.temperature2m ?? "°C",
            days: days
        )
    }

    private func geocode(_ query: String) async throws -> (name: String, latitude: Double, longitude: Double) {
        var components = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "name", value: query),
            URLQueryItem(name: "count", value: "1"),
            URLQueryItem(name: "language", value: "en"),
            URLQueryItem(name: "format", value: "json")
        ]
        guard let url = components.url else { throw WeatherEngineError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("PortalOS/1.0 (hackathon; open-meteo)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw WeatherEngineError.server("Open-Meteo geocoding failed.")
        }
        let decoded = try JSONDecoder().decode(OpenMeteoGeocode.self, from: data)
        guard let first = decoded.results?.first else {
            throw WeatherEngineError.server("No match for “\(query)”.")
        }
        let region = [first.admin1, first.country].compactMap { $0 }.joined(separator: ", ")
        let name = region.isEmpty ? first.name : "\(first.name), \(region)"
        return (name, first.latitude, first.longitude)
    }

    private func reverseName(for location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { marks, _ in
                let mark = marks?.first
                let name = mark?.locality ?? mark?.name
                continuation.resume(returning: name)
            }
        }
    }

    private func requestLocation() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw WeatherEngineError.locationDenied
        case .notDetermined:
            return try await withCheckedThrowingContinuation { continuation in
                locationContinuation = continuation
                manager.requestWhenInUseAuthorization()
            }
        default:
            return try await withCheckedThrowingContinuation { continuation in
                locationContinuation = continuation
                manager.requestLocation()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            locationContinuation?.resume(returning: location)
            locationContinuation = nil
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            locationContinuation?.resume(throwing: error)
            locationContinuation = nil
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard locationContinuation != nil else { return }
            switch status {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                locationContinuation?.resume(throwing: WeatherEngineError.locationDenied)
                locationContinuation = nil
            default:
                break
            }
        }
    }

    private func persist(name: String, latitude: Double, longitude: Double) {
        UserDefaults.standard.set(
            ["name": name, "lat": latitude, "lon": longitude],
            forKey: defaultsKey
        )
    }

    private func zipDays(_ daily: OpenMeteoDaily?) -> [WeatherDay] {
        guard let daily, let times = daily.time else { return [] }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return times.enumerated().compactMap { index, raw in
            guard let date = formatter.date(from: raw) else { return nil }
            return WeatherDay(
                id: raw,
                date: date,
                code: daily.weatherCode?[safe: index] ?? 1,
                high: daily.temperature2mMax?[safe: index] ?? 0,
                low: daily.temperature2mMin?[safe: index] ?? 0,
                precipChance: daily.precipitationProbabilityMax?[safe: index] ?? 0
            )
        }
    }
}

enum WeatherEngineError: Error, LocalizedError {
    case invalidResponse
    case locationDenied
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Open-Meteo returned an unexpected forecast."
        case .locationDenied:
            return "Location permission denied."
        case .server(let value):
            return value
        }
    }
}

private struct OpenMeteoForecast: Decodable {
    let current: OpenMeteoCurrent?
    let currentUnits: OpenMeteoCurrentUnits?
    let daily: OpenMeteoDaily?

    enum CodingKeys: String, CodingKey {
        case current
        case currentUnits = "current_units"
        case daily
    }
}

private struct OpenMeteoCurrent: Decodable {
    let temperature2m: Double?
    let relativeHumidity2m: Double?
    let apparentTemperature: Double?
    let weatherCode: Int?
    let windSpeed10m: Double?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
        case relativeHumidity2m = "relative_humidity_2m"
        case apparentTemperature = "apparent_temperature"
        case weatherCode = "weather_code"
        case windSpeed10m = "wind_speed_10m"
    }
}

private struct OpenMeteoCurrentUnits: Decodable {
    let temperature2m: String?

    enum CodingKeys: String, CodingKey {
        case temperature2m = "temperature_2m"
    }
}

private struct OpenMeteoDaily: Decodable {
    let time: [String]?
    let weatherCode: [Int]?
    let temperature2mMax: [Double]?
    let temperature2mMin: [Double]?
    let precipitationProbabilityMax: [Int]?

    enum CodingKeys: String, CodingKey {
        case time
        case weatherCode = "weather_code"
        case temperature2mMax = "temperature_2m_max"
        case temperature2mMin = "temperature_2m_min"
        case precipitationProbabilityMax = "precipitation_probability_max"
    }
}

private struct OpenMeteoGeocode: Decodable {
    let results: [OpenMeteoPlace]?
}

private struct OpenMeteoPlace: Decodable {
    let name: String
    let latitude: Double
    let longitude: Double
    let country: String?
    let admin1: String?
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
