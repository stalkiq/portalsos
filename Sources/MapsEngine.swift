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
    let rating: Double?
    let types: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    var subtitle: String {
        if address.isEmpty { return types.prefix(2).joined(separator: " · ") }
        return address
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

    var googleMode: String {
        switch self {
        case .drive: return "DRIVE"
        case .walk: return "WALK"
        }
    }

    var symbol: String {
        switch self {
        case .drive: return "car.fill"
        case .walk: return "figure.walk"
        }
    }
}

struct MapsRouteSummary: Equatable {
    var durationText: String
    var distanceText: String
    var durationSeconds: Int
    var distanceMeters: Int
    var steps: [String]
    var polylineCoordinates: [CLLocationCoordinate2D]

    static func == (lhs: MapsRouteSummary, rhs: MapsRouteSummary) -> Bool {
        lhs.durationText == rhs.durationText
            && lhs.distanceText == rhs.distanceText
            && lhs.durationSeconds == rhs.durationSeconds
            && lhs.distanceMeters == rhs.distanceMeters
            && lhs.steps == rhs.steps
            && lhs.polylineCoordinates.count == rhs.polylineCoordinates.count
    }
}

@MainActor
final class MapsEngine: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var query = ""
    @Published var results: [MapsPlace] = []
    @Published var selectedPlace: MapsPlace?
    @Published var route: MapsRouteSummary?
    @Published var travelMode: MapsTravelMode = .drive
    @Published var originCoordinate: CLLocationCoordinate2D?
    @Published var originLabel = "Current location"
    @Published var isBusy = false
    @Published var isLocating = false
    @Published var isRouting = false
    @Published var statusText = "Search a place, then brief it with Token Factory."
    @Published var errorMessage: String?
    @Published var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 40.7128, longitude: -74.0060),
            span: MKCoordinateSpan(latitudeDelta: 0.08, longitudeDelta: 0.08)
        )
    )

    private let manager = CLLocationManager()
    private var locationContinuation: CheckedContinuation<CLLocation, Error>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    var hasAPIKey: Bool {
        !resolvedAPIKey().isEmpty
    }

    var insightContext: String? {
        guard let place = selectedPlace else {
            if results.isEmpty { return nil }
            var parts = ["Google Maps Places search results for “\(query)”."]
            for item in results.prefix(6) {
                parts.append("- \(item.name) · \(item.subtitle)")
            }
            return parts.joined(separator: "\n")
        }
        var parts = [
            "Google Maps place selected via Places API (New).",
            "Destination: \(place.name)",
            "Address: \(place.address.isEmpty ? "n/a" : place.address)",
            "Coordinates: \(String(format: "%.5f", place.latitude)), \(String(format: "%.5f", place.longitude))"
        ]
        if let rating = place.rating {
            parts.append("Rating: \(String(format: "%.1f", rating))")
        }
        if !place.types.isEmpty {
            parts.append("Types: \(place.types.prefix(4).joined(separator: ", "))")
        }
        parts.append("Origin: \(originLabel)")
        if let route {
            parts.append("Route mode: \(travelMode.title)")
            parts.append("ETA: \(route.durationText) · \(route.distanceText)")
            if !route.steps.isEmpty {
                parts.append("Steps:")
                for step in route.steps.prefix(8) {
                    parts.append("- \(step)")
                }
            }
        } else {
            parts.append("No route computed yet.")
        }
        return parts.joined(separator: "\n")
    }

    func searchPlaces() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else {
            errorMessage = "Type a place, address, or business name."
            return
        }
        guard hasAPIKey else {
            errorMessage = "Add GOOGLE_MAPS_API_KEY to Config/Secrets.xcconfig, then rebuild."
            statusText = "Maps API key missing."
            return
        }
        errorMessage = nil
        isBusy = true
        statusText = "Searching Google Places…"
        route = nil
        selectedPlace = nil
        do {
            if originCoordinate == nil {
                await refreshOriginQuietly()
            }
            let found = try await placesTextSearch(trimmed)
            results = found
            if let first = found.first {
                selectedPlace = first
                focus(on: found)
                await computeRoute()
            } else {
                statusText = "No places matched."
            }
        } catch {
            errorMessage = error.localizedDescription
            statusText = "Places search failed."
        }
        isBusy = false
    }

    func selectPlace(_ place: MapsPlace) async {
        selectedPlace = place
        focus(on: [place])
        await computeRoute()
    }

    func setTravelMode(_ mode: MapsTravelMode) async {
        travelMode = mode
        guard selectedPlace != nil else { return }
        await computeRoute()
    }

    func useCurrentLocationAsOrigin() async {
        errorMessage = nil
        isLocating = true
        statusText = "Finding your location…"
        do {
            let location = try await requestLocation()
            originCoordinate = location.coordinate
            originLabel = await reverseName(for: location) ?? "Current location"
            statusText = "Origin set to \(originLabel)."
            if selectedPlace != nil {
                await computeRoute()
            }
        } catch {
            errorMessage = "Location unavailable. You can still search a destination; routes need an origin."
            statusText = "Location denied."
        }
        isLocating = false
    }

    func computeRoute() async {
        guard let destination = selectedPlace else { return }
        guard hasAPIKey else {
            errorMessage = "Add GOOGLE_MAPS_API_KEY to Config/Secrets.xcconfig, then rebuild."
            return
        }
        if originCoordinate == nil {
            await refreshOriginQuietly()
        }
        guard let origin = originCoordinate else {
            errorMessage = "Set your location (or allow GPS) so Routes can compute a path."
            return
        }
        isRouting = true
        statusText = "Computing \(travelMode.title.lowercased()) route…"
        do {
            let summary = try await fetchRoute(
                from: origin,
                to: destination.coordinate,
                mode: travelMode
            )
            route = summary
            focusRoute(origin: origin, destination: destination.coordinate, polyline: summary.polylineCoordinates)
            statusText = "\(summary.durationText) · \(summary.distanceText)"
            errorMessage = nil
        } catch {
            route = nil
            errorMessage = error.localizedDescription
            statusText = "Route failed."
        }
        isRouting = false
    }

    private func refreshOriginQuietly() async {
        do {
            let location = try await requestLocation()
            originCoordinate = location.coordinate
            originLabel = await reverseName(for: location) ?? "Current location"
        } catch {
            // Keep previous origin if any; search still works without it.
        }
    }

    private func focus(on places: [MapsPlace]) {
        guard let first = places.first else { return }
        if places.count == 1 {
            cameraPosition = .region(
                MKCoordinateRegion(
                    center: first.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)
                )
            )
            return
        }
        var minLat = places[0].latitude
        var maxLat = places[0].latitude
        var minLon = places[0].longitude
        var maxLon = places[0].longitude
        for place in places.dropFirst() {
            minLat = min(minLat, place.latitude)
            maxLat = max(maxLat, place.latitude)
            minLon = min(minLon, place.longitude)
            maxLon = max(maxLon, place.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.6, 0.04),
            longitudeDelta: max((maxLon - minLon) * 1.6, 0.04)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func focusRoute(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        polyline: [CLLocationCoordinate2D]
    ) {
        let points = polyline.isEmpty ? [origin, destination] : polyline
        var minLat = points[0].latitude
        var maxLat = points[0].latitude
        var minLon = points[0].longitude
        var maxLon = points[0].longitude
        for point in points.dropFirst() {
            minLat = min(minLat, point.latitude)
            maxLat = max(maxLat, point.latitude)
            minLon = min(minLon, point.longitude)
            maxLon = max(maxLon, point.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 1.35, 0.02),
            longitudeDelta: max((maxLon - minLon) * 1.35, 0.02)
        )
        cameraPosition = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func placesTextSearch(_ text: String) async throws -> [MapsPlace] {
        let url = URL(string: "https://places.googleapis.com/v1/places:searchText")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(resolvedAPIKey(), forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "places.id,places.displayName,places.formattedAddress,places.location,places.rating,places.types",
            forHTTPHeaderField: "X-Goog-FieldMask"
        )
        var body: [String: Any] = [
            "textQuery": text,
            "pageSize": 8,
            "languageCode": "en"
        ]
        if let origin = originCoordinate {
            body["locationBias"] = [
                "circle": [
                    "center": [
                        "latitude": origin.latitude,
                        "longitude": origin.longitude
                    ],
                    "radius": 25000.0
                ]
            ]
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MapsEngineError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MapsEngineError.server(googleErrorMessage(from: data) ?? "Places API HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(PlacesSearchResponse.self, from: data)
        return (decoded.places ?? []).compactMap { place in
            guard let location = place.location,
                  let lat = location.latitude,
                  let lon = location.longitude else { return nil }
            let name = place.displayName?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "Place"
            let id = place.id ?? "\(lat),\(lon),\(name)"
            return MapsPlace(
                id: id,
                name: name,
                address: place.formattedAddress ?? "",
                latitude: lat,
                longitude: lon,
                rating: place.rating,
                types: place.types ?? []
            )
        }
    }

    private func fetchRoute(
        from origin: CLLocationCoordinate2D,
        to destination: CLLocationCoordinate2D,
        mode: MapsTravelMode
    ) async throws -> MapsRouteSummary {
        let url = URL(string: "https://routes.googleapis.com/directions/v2:computeRoutes")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(resolvedAPIKey(), forHTTPHeaderField: "X-Goog-Api-Key")
        request.setValue(
            "routes.duration,routes.distanceMeters,routes.legs.steps.navigationInstruction,routes.polyline.encodedPolyline",
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
            "languageCode": "en-US",
            "units": "IMPERIAL"
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw MapsEngineError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            throw MapsEngineError.server(googleErrorMessage(from: data) ?? "Routes API HTTP \(http.statusCode)")
        }
        let decoded = try JSONDecoder().decode(RoutesResponse.self, from: data)
        guard let first = decoded.routes?.first else {
            throw MapsEngineError.server("No route found between origin and destination.")
        }
        let seconds = parseDurationSeconds(first.duration)
        let meters = first.distanceMeters ?? 0
        var steps: [String] = []
        for leg in first.legs ?? [] {
            for step in leg.steps ?? [] {
                if let instruction = step.navigationInstruction?.instructions?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                   !instruction.isEmpty {
                    steps.append(instruction)
                }
            }
        }
        let coords = decodePolyline(first.polyline?.encodedPolyline ?? "")
        return MapsRouteSummary(
            durationText: formatDuration(seconds),
            distanceText: formatDistance(meters),
            durationSeconds: seconds,
            distanceMeters: meters,
            steps: steps,
            polylineCoordinates: coords
        )
    }

    private func parseDurationSeconds(_ raw: String?) -> Int {
        guard let raw else { return 0 }
        let digits = raw.replacingOccurrences(of: "s", with: "")
        return Int(Double(digits) ?? 0)
    }

    private func formatDuration(_ seconds: Int) -> String {
        let minutes = max(1, Int((Double(seconds) / 60.0).rounded()))
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let rem = minutes % 60
        return rem == 0 ? "\(hours) hr" : "\(hours) hr \(rem) min"
    }

    private func formatDistance(_ meters: Int) -> String {
        let miles = Double(meters) / 1609.344
        if miles < 0.1 {
            let feet = Int((Double(meters) * 3.28084).rounded())
            return "\(feet) ft"
        }
        return String(format: "%.1f mi", miles)
    }

    private func googleErrorMessage(from data: Data) -> String? {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let error = object["error"] as? [String: Any],
           let message = error["message"] as? String {
            return message
        }
        return nil
    }

    private func resolvedAPIKey() -> String {
        let candidates = [
            ProcessInfo.processInfo.environment["GOOGLE_MAPS_API_KEY"],
            Bundle.main.object(forInfoDictionaryKey: "GOOGLE_MAPS_API_KEY") as? String
        ]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { continue }
            return trimmed
        }
        return ""
    }

    private func reverseName(for location: CLLocation) async -> String? {
        await withCheckedContinuation { continuation in
            CLGeocoder().reverseGeocodeLocation(location) { marks, _ in
                let mark = marks?.first
                let name = mark?.name ?? mark?.locality
                continuation.resume(returning: name)
            }
        }
    }

    private func requestLocation() async throws -> CLLocation {
        switch manager.authorizationStatus {
        case .denied, .restricted:
            throw MapsEngineError.locationDenied
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
                locationContinuation?.resume(throwing: MapsEngineError.locationDenied)
                locationContinuation = nil
            default:
                break
            }
        }
    }

    /// Decodes Google encoded polylines into coordinates for MapKit overlays.
    private func decodePolyline(_ encoded: String) -> [CLLocationCoordinate2D] {
        guard !encoded.isEmpty else { return [] }
        var coords: [CLLocationCoordinate2D] = []
        var index = encoded.startIndex
        var lat = 0
        var lon = 0
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

            result = 0
            shift = 0
            guard index < encoded.endIndex else { break }
            repeat {
                byte = Int(encoded[index].asciiValue ?? 63) - 63
                index = encoded.index(after: index)
                result |= (byte & 0x1f) << shift
                shift += 5
            } while byte >= 0x20 && index < encoded.endIndex
            let deltaLon = (result & 1) != 0 ? ~(result >> 1) : (result >> 1)
            lon += deltaLon

            coords.append(
                CLLocationCoordinate2D(
                    latitude: Double(lat) / 1e5,
                    longitude: Double(lon) / 1e5
                )
            )
        }
        return coords
    }
}

enum MapsEngineError: Error, LocalizedError {
    case invalidResponse
    case locationDenied
    case server(String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Google Maps returned an invalid response."
        case .locationDenied:
            return "Location access denied."
        case .server(let message):
            return message
        }
    }
}

private struct PlacesSearchResponse: Decodable {
    let places: [PlaceDTO]?
}

private struct PlaceDTO: Decodable {
    let id: String?
    let displayName: DisplayNameDTO?
    let formattedAddress: String?
    let location: LatLngDTO?
    let rating: Double?
    let types: [String]?
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
    let legs: [LegDTO]?
    let polyline: PolylineDTO?
}

private struct LegDTO: Decodable {
    let steps: [StepDTO]?
}

private struct StepDTO: Decodable {
    let navigationInstruction: NavigationInstructionDTO?
}

private struct NavigationInstructionDTO: Decodable {
    let instructions: String?
}

private struct PolylineDTO: Decodable {
    let encodedPolyline: String?
}
