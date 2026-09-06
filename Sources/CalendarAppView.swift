import SwiftUI

private enum CalendarTheme {
    static let canvas = Color(red: 0.08, green: 0.09, blue: 0.16)
    static let card = Color(red: 0.13, green: 0.14, blue: 0.24)
    static let accent = Color(red: 0.55, green: 0.58, blue: 0.98)
    static let action = Color(red: 0.28, green: 0.32, blue: 0.72)
}

struct CalendarAppView: View {
    @ObservedObject var account: GmailEngine
    @ObservedObject var engine: GoogleCalendarEngine
    var onAddToPortal: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showComposer = false
    @State private var draftTitle = ""
    @State private var draftStart = Date().addingTimeInterval(3600)
    @State private var draftDurationHours = 1
    @State private var isSendingToPortal = false

    var body: some View {
        NavigationStack {
            ZStack {
                CalendarTheme.canvas.ignoresSafeArea(.container)
                if account.isSignedIn {
                    agendaScreen
                } else {
                    signInPane
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await engine.restoreIfNeeded()
            }
            .sheet(isPresented: $showComposer) {
                composeSheet
            }
        }
    }

    private var agendaScreen: some View {
        VStack(spacing: 0) {
            topBar {
                Button("Close") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button {
                    draftTitle = ""
                    draftStart = Date().addingTimeInterval(3600)
                    draftDurationHours = 1
                    showComposer = true
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                }
                Menu {
                    Button {
                        Task { await engine.refresh() }
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    Button(role: .destructive, action: account.signOut) {
                        Label("Sign Out", systemImage: "rectangle.portrait.and.arrow.right")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 32, height: 32)
                }
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Calendar")
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)
                    Text(engine.statusText)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                    if let errorMessage = engine.errorMessage {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red.opacity(0.9))
                            Button {
                                Task { await engine.refresh() }
                            } label: {
                                Text("Try again")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(.white)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 42)
                                    .background(CalendarTheme.action, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            }
                            Button {
                                Task {
                                    account.signOut()
                                    await account.signIn()
                                    await engine.refresh()
                                }
                            } label: {
                                Text("Sign in again for Calendar")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(CalendarTheme.accent)
                            }
                        }
                    } else if engine.events.isEmpty, engine.isBusy {
                        ProgressView().tint(.white).padding(.top, 20)
                    } else if engine.events.isEmpty {
                        emptyCard
                    } else {
                        ForEach(groupedEvents, id: \.day) { group in
                            Text(group.day)
                                .font(.system(size: 11, weight: .bold, design: .rounded))
                                .tracking(1.8)
                                .foregroundStyle(CalendarTheme.accent)
                                .padding(.top, 6)
                            ForEach(group.items) { event in
                                Button {
                                    engine.selectedID = event.id
                                } label: {
                                    eventRow(event)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    if engine.selectedEvent != nil {
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
                            .background(CalendarTheme.action, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                    }
                    Text("NVIDIA Nemotron on Nebius Token Factory")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white.opacity(0.38))
                        .frame(maxWidth: .infinity)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 36)
            }
            .refreshable {
                await engine.refresh()
            }
        }
    }

    private var groupedEvents: [(day: String, items: [CalendarEventItem])] {
        var seen: [String] = []
        var buckets: [String: [CalendarEventItem]] = [:]
        for event in engine.events {
            if buckets[event.dayLabel] == nil {
                seen.append(event.dayLabel)
            }
            buckets[event.dayLabel, default: []].append(event)
        }
        return seen.map { day in (day, buckets[day] ?? []) }
    }

    private func eventRow(_ event: CalendarEventItem) -> some View {
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(engine.selectedID == event.id ? CalendarTheme.accent : Color.white.opacity(0.22))
                .frame(width: 4, height: 44)
            VStack(alignment: .leading, spacing: 4) {
                Text(event.title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Text(event.timeLabel)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                if !event.location.isEmpty {
                    Text(event.location)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(CalendarTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(engine.selectedID == event.id ? CalendarTheme.accent.opacity(0.7) : Color.clear, lineWidth: 1)
        )
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Nothing on the primary calendar for the next two weeks.")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
            Text("Add an event, or ask Insight to put something on the calendar.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(CalendarTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var signInPane: some View {
        VStack(spacing: 0) {
            topBar {
                Button("Close") { dismiss() }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
            }
            VStack(spacing: 22) {
                Spacer()
                Text("Connect Calendar")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                Text("Same Google account as Mail. Token Factory briefs the week and can draft events you confirm.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button {
                    Task { await account.signIn() }
                } label: {
                    HStack {
                        if account.isBusy {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: "calendar")
                        }
                        Text(account.isBusy ? "Opening Google..." : "Sign in with Google")
                            .font(.system(size: 16, weight: .semibold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(CalendarTheme.action, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(account.isBusy)
                .padding(.horizontal, 28)
                if let errorMessage = account.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .padding(.horizontal, 28)
                }
                Spacer()
            }
        }
    }

    private var composeSheet: some View {
        NavigationStack {
            Form {
                TextField("Event title", text: $draftTitle)
                DatePicker("Starts", selection: $draftStart)
                Stepper("\(draftDurationHours) hour\(draftDurationHours == 1 ? "" : "s")", value: $draftDurationHours, in: 1...8)
            }
            .navigationTitle("New event")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showComposer = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        Task {
                            let end = draftStart.addingTimeInterval(TimeInterval(draftDurationHours * 3600))
                            do {
                                _ = try await engine.createEvent(
                                    title: draftTitle,
                                    start: draftStart,
                                    end: end,
                                    location: nil
                                )
                                showComposer = false
                            } catch {
                                engine.errorMessage = error.localizedDescription
                            }
                        }
                    }
                    .disabled(draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func topBar<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.06, green: 0.07, blue: 0.13))
    }
}
