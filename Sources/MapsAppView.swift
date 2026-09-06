import MapKit
import SwiftUI

private enum MapsTheme {
    static let canvas = Color(red: 0.06, green: 0.08, blue: 0.12)
    static let card = Color(red: 0.12, green: 0.15, blue: 0.20)
    static let accent = Color(red: 0.42, green: 0.72, blue: 0.95)
    static let action = Color(red: 0.18, green: 0.40, blue: 0.78)
}

struct MapsAppView: View {
    @ObservedObject var engine: MapsEngine
    var onAddToPortal: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var isSendingToPortal = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                MapsTheme.canvas.ignoresSafeArea(.container)
                VStack(spacing: 0) {
                    topBar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            searchRow
                            modeRow
                            mapCard
                            if let errorMessage = engine.errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.9))
                            }
                            if !engine.hasAPIKey {
                                missingKeyCard
                            } else if engine.results.isEmpty, !engine.isBusy {
                                emptyCard
                            } else {
                                resultsList
                            }
                            if let place = engine.selectedPlace {
                                selectedCard(place)
                            }
                            if engine.selectedPlace != nil {
                                Button {
                                    isSendingToPortal = true
                                    onAddToPortal()
                                    dismiss()
                                } label: {
                                    HStack {
                                        Image(systemName: "sparkles")
                                        Text(isSendingToPortal ? "Opening Insight..." : "Brief with Token Factory")
                                            .font(.system(size: 15, weight: .semibold))
                                    }
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(MapsTheme.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .disabled(isSendingToPortal)
                            }
                            Text("Places + Routes by Google Maps · Insight by NVIDIA Nemotron on Nebius Token Factory")
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(.white.opacity(0.38))
                                .frame(maxWidth: .infinity)
                                .multilineTextAlignment(.center)
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 16)
                        .padding(.bottom, 36)
                    }
                    .dismissesKeyboardOnScroll()
                }
            }
            .keyboardDoneButton()
            .toolbar(.hidden, for: .navigationBar)
            .task {
                if engine.originCoordinate == nil {
                    await engine.useCurrentLocationAsOrigin()
                }
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
        HStack(spacing: 10) {
            TextField("Search places…", text: $engine.query)
                .textInputAutocapitalization(.words)
                .foregroundStyle(.white)
                .focused($searchFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await engine.searchPlaces() }
                }
            Button {
                Task { await engine.searchPlaces() }
            } label: {
                if engine.isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)
            .background(MapsTheme.action, in: Circle())
            Button {
                Task { await engine.useCurrentLocationAsOrigin() }
            } label: {
                if engine.isLocating {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "location.fill")
                        .foregroundStyle(.white)
                }
            }
            .frame(width: 34, height: 34)
            .background(Color.white.opacity(0.12), in: Circle())
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(MapsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .foregroundStyle(engine.travelMode == mode ? .white : .white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .frame(height: 36)
                    .background(
                        engine.travelMode == mode ? MapsTheme.action : Color.white.opacity(0.06),
                        in: Capsule()
                    )
                }
            }
        }
    }

    private var mapCard: some View {
        Map(position: $engine.cameraPosition) {
            if let origin = engine.originCoordinate {
                Annotation(engine.originLabel, coordinate: origin) {
                    Image(systemName: "location.circle.fill")
                        .foregroundStyle(MapsTheme.accent)
                        .font(.system(size: 22))
                }
            }
            ForEach(engine.results) { place in
                Annotation(place.name, coordinate: place.coordinate) {
                    Image(systemName: engine.selectedPlace?.id == place.id ? "mappin.circle.fill" : "mappin")
                        .foregroundStyle(engine.selectedPlace?.id == place.id ? Color.orange : .white)
                        .font(.system(size: 20))
                }
            }
            if let route = engine.route, route.polylineCoordinates.count > 1 {
                MapPolyline(coordinates: route.polylineCoordinates)
                    .stroke(MapsTheme.accent, lineWidth: 4)
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .frame(height: 220)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        )
    }

    private var resultsList: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(engine.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            ForEach(engine.results) { place in
                Button {
                    Task { await engine.selectPlace(place) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundStyle(MapsTheme.accent)
                            .padding(.top, 2)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                            Text(place.subtitle)
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.white.opacity(0.55))
                                .multilineTextAlignment(.leading)
                            if let rating = place.rating {
                                Text(String(format: "%.1f ★", rating))
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundStyle(MapsTheme.accent)
                            }
                        }
                        Spacer(minLength: 0)
                        if engine.selectedPlace?.id == place.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(MapsTheme.accent)
                        }
                    }
                    .padding(12)
                    .background(
                        engine.selectedPlace?.id == place.id
                            ? MapsTheme.action.opacity(0.28)
                            : MapsTheme.card.opacity(0.9),
                        in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func selectedCard(_ place: MapsPlace) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(place.name)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            if !place.address.isEmpty {
                Text(place.address)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.62))
            }
            Text("From \(engine.originLabel)")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
            if engine.isRouting {
                HStack(spacing: 8) {
                    ProgressView().tint(.white)
                    Text("Computing route…")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.6))
                }
            } else if let route = engine.route {
                HStack(spacing: 16) {
                    metric("ETA", route.durationText)
                    metric("Distance", route.distanceText)
                    metric("Mode", engine.travelMode.title)
                }
                if let firstSteps = Optional(route.steps.prefix(3)), !firstSteps.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(firstSteps.enumerated()), id: \.offset) { _, step in
                            Text("• \(step)")
                                .font(.system(size: 12, weight: .regular))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MapsTheme.card, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Google Maps + Token Factory")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("Search a destination, compute Drive or Walk with Google Routes, then drop Maps into Insight. Nemotron briefs leave-by time and what to watch for.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MapsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var missingKeyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Maps API key needed")
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(.white)
            Text("Add GOOGLE_MAPS_API_KEY to Config/Secrets.xcconfig, enable Places API (New) and Routes API in Google Cloud, then rebuild PortalOS.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(MapsTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func metric(_ title: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.4))
            Text(value)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
        }
    }
}
