import MapKit
import SwiftUI

private enum MapsTheme {
    static let canvas = Color(red: 0.07, green: 0.09, blue: 0.12)
    static let card = Color(red: 0.12, green: 0.15, blue: 0.20)
    static let accent = Color(red: 0.45, green: 0.72, blue: 0.95)
    static let action = Color(red: 0.18, green: 0.42, blue: 0.78)
}

struct MapsAppView: View {
    @ObservedObject var engine: MapsEngine
    var onAddToPortal: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSendingToPortal = false
    @State private var cameraPosition: MapCameraPosition = .automatic
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                MapsTheme.canvas.ignoresSafeArea(.container)
                VStack(spacing: 0) {
                    topBar
                    searchRow
                    modeRow
                    mapPane
                    bottomPane
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .keyboardDoneButton()
            .task {
                if engine.origin == nil {
                    await engine.refreshOrigin()
                }
            }
            .onChange(of: engine.selectedPlace?.id) { _, _ in
                fitMap()
            }
            .onChange(of: engine.statusText) { _, _ in
                fitMap()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Text("Maps")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Color.clear.frame(width: 48, height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.black.opacity(0.25))
    }

    private var searchRow: some View {
        HStack(spacing: 8) {
            TextField("Search places…", text: $engine.query)
                .textInputAutocapitalization(.words)
                .foregroundStyle(.white)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await engine.search() }
                }
            Button {
                searchFocused = false
                Task { await engine.search() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(MapsTheme.action, in: Circle())
            }
            Button {
                Task { await engine.refreshOrigin() }
            } label: {
                Image(systemName: engine.isLocating ? "location" : "location.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .disabled(engine.isLocating)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(MapsTheme.card)
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var modeRow: some View {
        HStack(spacing: 8) {
            ForEach(MapsTravelMode.allCases) { mode in
                Button {
                    Task { await engine.setTravelMode(mode) }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: mode.symbol)
                        Text(mode.title)
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(engine.travelMode == mode ? .white : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: 34)
                    .background(
                        engine.travelMode == mode ? MapsTheme.action : Color.white.opacity(0.06),
                        in: Capsule()
                    )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 10)
    }

    private var mapPane: some View {
        Map(position: $cameraPosition) {
            if let origin = engine.origin {
                Annotation("Origin", coordinate: origin.coordinate) {
                    Image(systemName: "location.circle.fill")
                        .foregroundStyle(.cyan)
                        .font(.system(size: 22))
                }
            }
            ForEach(engine.results) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    Image(systemName: engine.selectedPlace?.id == place.id ? "mappin.circle.fill" : "mappin")
                        .foregroundStyle(engine.selectedPlace?.id == place.id ? MapsTheme.accent : .white)
                        .font(.system(size: 20))
                }
            }
            if let route = engine.route, route.coordinates.count >= 2 {
                MapPolyline(coordinates: route.coordinates)
                    .stroke(MapsTheme.accent, lineWidth: 4)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .overlay(alignment: .topLeading) {
            if engine.usingDemoData {
                Text("DEMO")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.8)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.orange.opacity(0.85), in: Capsule())
                    .padding(.leading, 24)
                    .padding(.top, 22)
            }
        }
    }

    private var bottomPane: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(engine.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))

            if let errorMessage = engine.errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.red.opacity(0.9))
            }

            if engine.isBusy {
                ProgressView().tint(.white)
            }

            if let place = engine.selectedPlace {
                selectedCard(place)
            } else {
                resultsList
            }

            Text("Places & Routes by Google · Insight by NVIDIA Nemotron on Nebius Token Factory")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity)
                .multilineTextAlignment(.center)
                .padding(.bottom, 8)
        }
        .padding(.horizontal, 14)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var resultsList: some View {
        Group {
            if engine.results.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Find a place")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white)
                    Text(engine.hasAPIKey
                         ? "Search with Google Places, pick a pin, then brief the route with Token Factory."
                         : "No GOOGLE_MAPS_API_KEY yet — demo places are available. Add the key in Secrets.xcconfig for live Google data.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                        .fixedSize(horizontal: false, vertical: true)
                    if !engine.hasAPIKey {
                        Button("Load demo places") {
                            engine.query = "New York"
                            Task { await engine.search() }
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.top, 4)
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(MapsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
            } else {
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(engine.results) { place in
                            Button {
                                Task { await engine.select(place) }
                            } label: {
                                HStack(alignment: .top, spacing: 10) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundStyle(MapsTheme.accent)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(place.name)
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(.white)
                                            .multilineTextAlignment(.leading)
                                        Text(place.address)
                                            .font(.system(size: 12))
                                            .foregroundStyle(.white.opacity(0.55))
                                            .multilineTextAlignment(.leading)
                                        HStack(spacing: 8) {
                                            Text(place.typeLabel)
                                                .font(.system(size: 11, weight: .medium))
                                                .foregroundStyle(.white.opacity(0.45))
                                            if let rating = place.rating {
                                                Text(String(format: "★ %.1f", rating))
                                                    .font(.system(size: 11, weight: .medium))
                                                    .foregroundStyle(.yellow.opacity(0.85))
                                            }
                                        }
                                    }
                                    Spacer(minLength: 0)
                                }
                                .padding(12)
                                .background(MapsTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
    }

    private func selectedCard(_ place: MapsPlace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(place.name)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(.white)
                    Text(place.address)
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.55))
                }
                Spacer()
                Button("Results") {
                    engine.selectedPlace = nil
                    engine.route = nil
                }
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(MapsTheme.accent)
            }

            if let route = engine.route {
                HStack(spacing: 12) {
                    labelChip(route.durationLabel, symbol: "clock")
                    labelChip(route.distanceLabel, symbol: "arrow.triangle.swap")
                    labelChip(engine.travelMode.title, symbol: engine.travelMode.symbol)
                }
                Text(route.summary)
                    .font(.system(size: 13))
                    .foregroundStyle(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button {
                isSendingToPortal = true
                onAddToPortal()
                dismiss()
            } label: {
                HStack {
                    Image(systemName: "sparkles")
                    Text(isSendingToPortal ? "Opening Insight…" : "Brief with Token Factory")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(MapsTheme.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .disabled(engine.selectedPlace == nil)
        }
        .padding(16)
        .background(MapsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func labelChip(_ text: String, symbol: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: symbol)
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.08), in: Capsule())
    }

    private func fitMap() {
        var coords: [CLLocationCoordinate2D] = []
        if let origin = engine.origin { coords.append(origin.coordinate) }
        if let place = engine.selectedPlace {
            coords.append(place.coordinate)
        } else {
            coords.append(contentsOf: engine.results.prefix(5).map(\.coordinate))
        }
        if let routeCoords = engine.route?.coordinates, routeCoords.count >= 2 {
            coords.append(contentsOf: routeCoords)
        }
        guard !coords.isEmpty else { return }
        var rect = MKMapRect.null
        for coord in coords {
            let point = MKMapPoint(coord)
            rect = rect.union(MKMapRect(origin: point, size: MKMapSize(width: 1, height: 1)))
        }
        let region = MKCoordinateRegion(rect)
        withAnimation(.easeInOut(duration: 0.35)) {
            cameraPosition = .region(region)
        }
    }
}
