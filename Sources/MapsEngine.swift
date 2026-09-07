import Combine
import CoreLocation
import Foundation
import MapKit

struct MapsPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let address: String
    let latitude: Double
    let longitude: Double
    let types: [String]
    let rating: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var typeLabel: String {
        guard let first = types.first else { return "Place" }
        return first
            .replacingOccurrences(of: "_", with: " ")
            .capitalized
    }
}

enum MapsTravelMode: String, CaseIterable, Identifiable {
    case drive
    case walk

    var id: String { rawValue }

    var title: String {
        switch self {
        case .drive: return "Drive"
        case .walk: return "Walk"
        }
    }

    var symbol: String {
        switch self {
        case .drive: return "car.fill"
        case .walk: return "figure.walk"
        }
    }

    var googleMode: String {
        switch self {
        case .drive: return "DRIVE"
        case .walk: return "WALK"
        }
    }
}

struct MapsRoute {
    var distanceMeters: Int
    var durationSeconds: Int
    var summary: String
    var steps: [String]
    var coordinates: [CLLocationCoordinate2D]

    var distanceLabel: String {
        if distanceMeters >= 1000 {
            return String(format: "%.1f km", Double(distanceMeters) / 1000)
        }
        return "\(distanceMeters) m"
    }

    var durationLabel: String {
        let minutes = max(1, Int((Double(durationSeconds) / 60).rounded()))
        if minutes >= 60 {
            let hours = minutes / 60
            let rem = minutes % 60
            return rem == 0 ? "\(hours) hr" : "\(hours) hr \(rem) min"
        }
        return "\(minutes) min"
    }
}

@MainActor
final class MapsEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var query = ""
    @Published var results: [MapsPlace] = []
    @Published var selectedPlace: MapsPlace?
    @Published var origin: MapsPlace?
    @Published var route: MapsRoute?
    @Published var travelMode: MapsTravelMode = .drive
    @Published var isBusy = false
    @Published var isLocating = false
    @Published var statusText = "Search a place, then route from your location."
    @Published var errorMessage: String?
    @Published var usingDemoData = false

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        if apiKey == nil {
            usingDemoData = true
            statusText = "Demo places loaded. Add GOOGLE_MAPS_API_KEY for live Google Places/Routes."
            results = Self.demoPlaces
        }
    }

    var hasAPIKey: Bool { apiKey != nil }

    var insightContext: String? {
        guard let place = selectedPlace else {
            if results.isEmpty { return nil }
            let lines = results.prefix(5).map { "- \($0.name) · \($0.address)" }
            return "Google Maps search results:\n" + lines.joined(separator: "\n")
        }
        var parts = [
            "Google Maps place (Places API):",
            "Name: \(place.name)",
            "Address: \(place.address)",
            "Coords: \(String(format: "%.5f", place.latitude)), \(String(format: "%.5f", place.longitude))",
            "Type: \(place.typeLabel)"
        ]
        if let rating = place.rating {
            parts.append("Rating: \(String(format: "%.1f", rating))")
        }
        if let origin {
            parts.append("Origin: \(origin.name) · \(origin.address)")
        }
        if let route {
            parts.append("Route (\(travelMode.title)): \(route.durationLabel), \(route.distanceLabel).")
            parts.append("Summary: \(route.summary)")
            if !route.steps.isEmpty {
                parts.append("Steps:")
                for step in route.steps.prefix(8) {
                    parts.append("- \(step)")
                }
            }
        }
        if usingDemoData {
            parts.append("Note: demo Google Maps data (no live API key in this build).")
        }
        return parts.joined(separator: "\n")
    }

    func search() async {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard q.count >= 2 else {
            errorMessage = "Type at least 2 characters."
            return
        }
        errorMessage = nil
        isBusy = true
        statusText = "Searching Google Places…"
        route = nil
        selectedPlace = nil
        defer { isBusy = false }

        if let apiKey {
            do {
                results = try await searchPlaces(query: q, apiKey: apiKey)
                usingDemoData = false
                statusText = results.isEmpty ? "No places found." : "\(results.count) places · pick one to route"
            } catch {
                errorMessage = error.localizedDescription
                statusText = "Places search failed."
            }
            return
        }

        usingDemoData = true
        results = Self.demoPlaces.filter {
            $0.name.localizedCaseInsensitiveContains(q) || $0.address.localizedCaseInsensitiveContains(q)
        }
        if results.isEmpty { results = Self.demoPlaces }
        statusText = "Demo results · add GOOGLE_MAPS_API_KEY for live search"
    }

    func select(_ place: MapsPlace) async {
        selectedPlace = place
        route = nil
        errorMessage = nil
        if origin == nil {
            await refreshOrigin()
        }
        await computeRoute()
    }

    func setTravelMode(_ mode: MapsTravelMode) async {
        travelMode = mode
        guard selectedPlace != nil else { return }
        await computeRoute()
    }

    func refreshOrigin() async {
        isLocating = true
        defer { isLocating = false }
        do {
            let location = try await requestLocation()
            let name = await reverseName(for: location) ?? "Current location"
            origin = MapsPlace(
                id: "origin",
                name: name,
                address: name,
                latitude: location.coordinate.latitude,
                longitude: location.coordinate.longitude,
                types: ["origin"],
                rating: nil
            )
        } catch {
            // Fall back to a city center so routing still works in Simulator / denied GPS.
            if origin == nil {
                origin = Self.demoOrigin
            }
            if errorMessage == nil {
                errorMessage = "Using a default origin. Enable location for live GPS."
            }
        }
    }

    func computeRoute() async {
        guard let destination = selectedPlace else { return }
        if origin == nil {
            await refreshOrigin()
        }
        guard let origin else {
            errorMessage = "Could not set an origin for the route."
            return
        }

        isBusy = true
        statusText = "Computing \(travelMode.title.lowercased()) route…"
        defer { isBusy = false }

        if let apiKey {
            do {
                route = try await fetchRoute(from: origin, to: destination, mode: travelMode, apiKey: apiKey)
                usingDemoData = false
                statusText = "\(route?.durationLabel ?? "—") · \(route?.distanceLabel ?? "—")"
                errorMessage = nil
                return
            } catch {
                errorMessage = error.localizedDescription
            }
        }

        route = Self.demoRoute(from: origin, to: destination, mode: travelMode)
        usingDemoData = true
        statusText = "\(route?.durationLabel ?? "—") · \(route?.distanceLabel ?? "—") (demo route)"
    }

    // MARK: - Google Places

    private func searchPlaces(query: String, apiKey: String) async throws -> [MapsPlace] {
        let url = URL(string: "https://places.googleapis.com/v1/places:searchText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "places.id,places.displayName,places.formattedAddress,places.location,places.types,places.rating",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        let body: [String: Any] = [
            "textQuery": query,
            "pageSize": 8
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MapsEngineError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw MapsEngineError.server(Self.friendlyGoogleError(message, code: http.statusCode))
        }
        let decoded = try JSONDecoder().decode(PlacesSearchResponse.self, from: data)
        return (decoded.places ?? []).compactMap { place in
            guard let lat = place.location?.latitude,
                  let lon = place.location?.longitude else { return nil }
            let id = place.id ?? "\(lat),\(lon)"
            return MapsPlace(
                id: id,
                name: place.displayName?.text ?? "Place",
                address: place.formattedAddress ?? "Address unavailable",
                latitude: lat,
                longitude: lon,
                types: place.types ?? [],
                rating: place.rating
            )
        }
    }

    // MARK: - Google Routes

    private func fetchRoute(
        from origin: MapsPlace,
        to destination: MapsPlace,
        mode: MapsTravelMode,
        apiKey: String
    ) async throws -> MapsRoute {
        let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "routes.duration,routes.distanceMeters,routes.polyline.encodedPolyline,routes.legs.steps.navigationInstruction",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        let body: [String: Any] = [
            "origin": [
                "location": [
                    "latLng": [
                        "latitude": origin.latitude,
                        "longitude": origin.longitude
                    ]
                ]
            ],
            "destination": [
                "location": [
                    "latLng": [
                        "latitude": destination.latitude,
                        "longitude": destination.longitude
                    ]
                ]
            ],
            "travelMode": mode.googleMode,
            "routingPreference": mode == .drive ? "TRAFFIC_AWARE" : "ROUTING_PREFERENCE_UNSPECIFIED",
            "languageCode": "en-US",
            "units": "METRIC"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MapsEngineError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw MapsEngineError.server(Self.friendlyGoogleError(message, code: http.statusCode))
        }
        let decoded = try JSONDecoder().decode(RoutesResponse.self, from: data)
        guard let first = decoded.routes?.first else {
            throw MapsEngineError.server("No route found.")
        }
        let seconds = Self.parseDurationSeconds(first.duration) ?? 0
        let meters = first.distanceMeters ?? 0
        let encoded = first.polyline?.encodedPolyline ?? ""
        let coords = PolylineDecoder.decode(encoded)
        let steps = (first.legs ?? [])
            .flatMap { $0.steps ?? [] }
            .compactMap { $0.navigationInstruction?.instructions }
            .filter { !$0.isEmpty }
        let summary: String
        if let head = steps.first {
            summary = "\(mode.title) · \(head)"
        } else {
            summary = "\(mode.title) to \(destination.name)"
        }
        return MapsRoute(
            distanceMeters: meters,
            durationSeconds: seconds,
            summary: summary,
            steps: steps,
            coordinates: coords.isEmpty
                ? [origin.coordinate, destination.coordinate]
                : coords
        )
    }

    // MARK: - Location

    private func requestLocation() async throws -> CLLocation {
        if let location = manager.location {
            return location
        }
        return try await withCheckedThrowingContinuation { continuation in
            locationContinuation = continuation
            switch manager.authorizationStatus {
            case .notDetermined:
                manager.requestWhenInUseAuthorization()
            case .denied, .restricted:
                continuation.resume(throwing: MapsEngineError.locationDenied)
                locationContinuation = nil
            default:
                manager.requestLocation()
            }
        }
    }

    private func reverseName(for location: CLLocation) async -> String? {
        let geocoder = CLGeocoder()
        let marks = try? await geocoder.reverseGeocodeLocation(location)
        guard let mark = marks?.first else { return nil }
        return [mark.name, mark.locality].compactMap { $0 }.joined(separator: ", ")
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            guard locationContinuation != nil else { return }
            switch manager.authorizationStatus {
            case .authorizedAlways, .authorizedWhenInUse:
                manager.requestLocation()
            case .denied, .restricted:
                locationContinuation?.resume(throwing: MapsEngineError.locationDenied)
                locationContinuation = nil
            default:
                break
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        Task { @MainActor in
            guard let location = locations.last else { return }
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

    // MARK: - Key + helpers

    private var apiKey: String? {
        let candidates = [
            ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"],
            Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String
        ]
        for raw in candidates {
            guard let value = raw?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  !value.hasPrefix("$(") else { continue }
            return value
        }
        return nil
    }

    private static func parseDurationSeconds(_ raw: String?) -> Int? {
        guard let raw, raw.hasSuffix("s"), let value = Double(raw.dropLast()) else { return nil }
        return Int(value.rounded())
    }

    private static func friendlyGoogleError(_ body: String, code: Int) -> String {
        if body.localizedCaseInsensitiveContains("API_KEY") || code == 403 {
            return "Google Maps rejected the key. Enable Places API (New) + Routes API, then rebuild."
        }
        if code == 429 {
            return "Google Maps quota exceeded. Try again shortly."
        }
        return "Google Maps error (\(code))."
    }

    private static let demoOrigin = MapsPlace(
        id: "demo-origin",
        name: "Midtown Manhattan",
        address: "New York, NY",
        latitude: 40.7549,
        longitude: -73.9840,
        types: ["origin"],
        rating: nil
    )

    private static let demoPlaces: [MapsPlace] = [
        MapsPlace(
            id: "demo-1",
            name: "The Metropolitan Museum of Art",
            address: "1000 5th Ave, New York, NY",
            latitude: 40.7794,
            longitude: -73.9632,
            types: ["museum"],
            rating: 4.8
        ),
        MapsPlace(
            id: "demo-2",
            name: "Grand Central Terminal",
            address: "89 E 42nd St, New York, NY",
            latitude: 40.7527,
            longitude: -73.9772,
            types: ["transit_station"],
            rating: 4.7
        ),
        MapsPlace(
            id: "demo-3",
            name: "Brooklyn Bridge",
            address: "Brooklyn Bridge, New York, NY",
            latitude: 40.7061,
            longitude: -73.9969,
            types: ["tourist_attraction"],
            rating: 4.8
        )
    ]

    private static func demoRoute(from origin: MapsPlace, to destination: MapsPlace, mode: MapsTravelMode) -> MapsRoute {
        let meters = Int(CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: destination.latitude, longitude: destination.longitude)))
        let seconds = mode == .walk ? Int(Double(meters) / 1.4) : Int(Double(meters) / 8.5)
        return MapsRoute(
            distanceMeters: meters,
            durationSeconds: max(180, seconds),
            summary: "\(mode.title) toward \(destination.name)",
            steps: [
                "Head toward \(destination.name)",
                "Continue for \(max(1, meters / 1000)) km",
                "Arrive at \(destination.address)"
            ],
            coordinates: [origin.coordinate, destination.coordinate]
        )
    }
}

enum MapsEngineError: Error, LocalizedError {
    case invalidResponse
    case locationDenied
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse: return "Invalid response from Google Maps."
        case .locationDenied: return "Location permission denied."
        case .server(let message): return message
        }
    }
}

// MARK: - Decoding

private struct PlacesSearchResponse: Decodable {
    let places: [PlaceDTO]?
}

private struct PlaceDTO: Decodable {
    let id: String?
    let displayName: DisplayNameDTO?
    let formattedAddress: String?
    let location: LatLngDTO?
    let types: [String]?
    let rating: Double?
}

private struct DisplayNameDTO: Decodable {
    let text: String?
}

private struct LatLngDTO: Decodable {
    let latitude: Double?
    let longitude: Double?
}

private struct RoutesResponse: Decodable {
    let routes: [RouteDTO]?
}

private struct RouteDTO: Decodable {
    let duration: String?
    let distanceMeters: Int?
    let polyline: PolylineDTO?
    let legs: [LegDTO]?
}

private struct PolylineDTO: Decodable {
    let encodedPolyline: String?
}

private struct LegDTO: Decodable {
    let steps: [StepDTO]?
}

private struct StepDTO: Decodable {
    let navigationInstruction: NavInstructionDTO?
}

private struct NavInstructionDTO: Decodable {
    let instructions: String?
}

enum PolylineDecoder {
    static func decode(_ encoded: String) -> [CLLocationCoordinate2D] {
        guard !encoded.isEmpty else { return [] }
        var coords: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var lat = 0
        var lng = 0

        while index < encoded.endIndex {
            var result = 0
            var shift = 0
            var byte: Int
            repeat {
                byte = Int(encoded[index].asciiValue ?? 63) - 63
                index = encoded.index(after: index)
                result |= (byte & 0x1f) << shift
                shift += 5
            } while byte >= 0x20 && index < encoded.endIndex
            let deltaLat = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lat += deltaLat

            guard index < encoded.endIndex else { break }
            result = 0
            shift = 0
            repeat {
                byte = Int(encoded[index].asciiValue ?? 63) - 63
                index = encoded.index(after: index)
                result |= (byte & 0x1f) << shift
                shift += 5
            } while byte >= 0x20 && index < encoded.endIndex
            let deltaLng = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lng += deltaLng

            coords.append(
                CLLocationCoordinate2D(
                    latitude: Double(lat) / 1e5,
                    longitude: Double(lng) / 1e5
                )
            )
        }
        return coords
    }
}
