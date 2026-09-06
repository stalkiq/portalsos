import SwiftUI

private enum WeatherTheme {
    static let canvas = Color(red: 0.07, green: 0.12, blue: 0.18)
    static let card = Color(red: 0.11, green: 0.18, blue: 0.26)
    static let accent = Color(red: 0.45, green: 0.78, blue: 0.95)
    static let action = Color(red: 0.16, green: 0.42, blue: 0.62)
}

struct WeatherAppView: View {
    @ObservedObject var engine: WeatherEngine
    var onAddToPortal: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var isSendingToPortal = false
    @FocusState private var cityFocused: Bool

    var body: some View {
        NavigationStack {
            ZStack {
                WeatherTheme.canvas.ignoresSafeArea(.container)
                VStack(spacing: 0) {
                    topBar
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            searchRow
                            if let errorMessage = engine.errorMessage {
                                Text(errorMessage)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.9))
                            }
                            if let snapshot = engine.snapshot {
                                currentCard(snapshot)
                                weekList(snapshot)
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
                                    .background(WeatherTheme.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                            } else if engine.isBusy {
                                ProgressView().tint(.white).padding(.top, 30)
                            } else {
                                emptyCard
                            }
                            Text("Forecast by Open-Meteo · Insight by NVIDIA Nemotron on Nebius Token Factory")
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
        }
    }

    private var topBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Text("Weather")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                Task { await engine.useCurrentLocation() }
            } label: {
                Image(systemName: engine.isLocating ? "location.fill" : "location")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
            .disabled(engine.isLocating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.05, green: 0.09, blue: 0.14))
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            TextField("City, like Miami or Paris", text: $engine.cityQuery)
                .textInputAutocapitalization(.words)
                .disableAutocorrection(true)
                .foregroundStyle(.white)
                .focused($cityFocused)
                .submitLabel(.search)
                .onSubmit {
                    Task { await engine.searchCity() }
                }
            Button {
                cityFocused = false
                Task { await engine.searchCity() }
            } label: {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(WeatherTheme.action, in: Circle())
            }
            .disabled(engine.isBusy)
        }
        .padding(12)
        .background(WeatherTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func currentCard(_ snapshot: WeatherSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(snapshot.placeName)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white.opacity(0.7))
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(Int(snapshot.temperature.rounded()))\(snapshot.units)")
                        .font(.system(size: 56, weight: .bold))
                        .foregroundStyle(.white)
                    Text(snapshot.summary)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(WeatherTheme.accent)
                }
                Spacer()
                Image(systemName: snapshot.symbol)
                    .font(.system(size: 42, weight: .semibold))
                    .foregroundStyle(WeatherTheme.accent)
                    .symbolRenderingMode(.hierarchical)
            }
            HStack(spacing: 16) {
                metric("Feels", "\(Int(snapshot.feelsLike.rounded()))\(snapshot.units)")
                metric("Wind", "\(Int(snapshot.wind.rounded())) km/h")
                metric("Humidity", "\(snapshot.humidity)%")
            }
            Text(engine.statusText)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.4))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeatherTheme.card, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func weekList(_ snapshot: WeatherSnapshot) -> some View {
        VStack(spacing: 8) {
            ForEach(snapshot.days) { day in
                HStack {
                    Text(day.weekday)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 92, alignment: .leading)
                    Image(systemName: day.symbol)
                        .foregroundStyle(WeatherTheme.accent)
                        .frame(width: 22)
                    Text("\(day.precipChance)%")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.45))
                        .frame(width: 36)
                    Spacer()
                    Text("\(Int(day.low.rounded()))°")
                        .foregroundStyle(.white.opacity(0.45))
                    Text("\(Int(day.high.rounded()))°")
                        .foregroundStyle(.white)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(WeatherTheme.card.opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Open-Meteo weather")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(.white)
            Text("Search a city or tap location. Drop Weather on Insight and Token Factory will say what to wear and whether you need an umbrella.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(WeatherTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
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
