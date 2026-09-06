import SwiftUI

private enum AgentTheme {
    static let canvas = Color(red: 0.06, green: 0.07, blue: 0.11)
    static let card = Color(red: 0.12, green: 0.13, blue: 0.18)
    static let accent = Color(red: 0.48, green: 0.62, blue: 1.0)
    static let action = Color(red: 0.27, green: 0.47, blue: 0.98)
    static let bar = Color(red: 0.08, green: 0.09, blue: 0.14)
}

enum AgentPlanHorizon: String, CaseIterable, Identifiable {
    case week
    case month
    case year

    var id: String { rawValue }

    var title: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .year: return "Year"
        }
    }

    var prompt: String {
        switch self {
        case .week:
            return "Plan my week. Prioritize what to do in the next 7 days using my calendar, mail, notes, and weather."
        case .month:
            return "Plan my month. Spot deadlines, travel, and focus themes for the next 30 days from my apps."
        case .year:
            return "Plan my year at a high level. Themes, seasons, and big commitments implied by my calendar, mail, and notes — be honest when data is thin."
        }
    }
}

private struct AgentMessage: Identifiable, Equatable {
    let id = UUID()
    let role: Role
    let text: String

    enum Role {
        case user
        case agent
    }
}

struct AgentChannelAppView: View {
    @ObservedObject var mail: GmailEngine
    @ObservedObject var calendar: GoogleCalendarEngine
    @ObservedObject var notes: NotesStore
    @ObservedObject var weather: WeatherEngine
    var onAddToPortal: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var horizon: AgentPlanHorizon = .week
    @State private var messages: [AgentMessage] = []
    @State private var draft = ""
    @State private var isBusy = false
    @State private var errorText: String?
    @State private var keyboardOverlap: CGFloat = 0
    @FocusState private var fieldFocused: Bool

    private let nebius = NebiusService()

    var body: some View {
        NavigationStack {
            ZStack {
                AgentTheme.canvas.ignoresSafeArea(.container)
                RadialGradient(
                    colors: [
                        Color(red: 0.26, green: 0.30, blue: 0.52).opacity(0.42),
                        .clear
                    ],
                    center: .topTrailing,
                    startRadius: 20,
                    endRadius: 300
                )
                .ignoresSafeArea(.container)

                VStack(spacing: 0) {
                    topBar
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                header
                                sourceStrip
                                horizonRow
                                planButton
                                if let errorText {
                                    Text(errorText)
                                        .font(.system(size: 13, weight: .medium))
                                        .foregroundStyle(.red.opacity(0.9))
                                }
                                if messages.isEmpty, !isBusy {
                                    emptyCard
                                }
                                ForEach(messages) { message in
                                    bubble(message)
                                        .id(message.id)
                                }
                                if isBusy {
                                    HStack(spacing: 8) {
                                        ProgressView().tint(AgentTheme.accent)
                                        Text("Nemotron is planning…")
                                            .font(.system(size: 13, weight: .medium))
                                            .foregroundStyle(.white.opacity(0.55))
                                    }
                                    .id("busy")
                                }
                            }
                            .padding(18)
                            .padding(.bottom, max(24, keyboardOverlap + 8))
                        }
                        .dismissesKeyboardOnScroll()
                        .onChange(of: messages.count) { _, _ in
                            scrollToBottom(proxy)
                        }
                        .onChange(of: isBusy) { _, busy in
                            if busy { scrollToBottom(proxy) }
                        }
                    }
                    composer
                }
            }
            .toolbar(.hidden, for: .navigationBar)
            .keyboardDoneButton()
            .readsKeyboardOverlap($keyboardOverlap)
            .task {
                await calendar.restoreIfNeeded()
                await mail.restoreInboxIfNeeded()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button("Close") { dismiss() }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
            Spacer()
            Button {
                onAddToPortal()
                dismiss()
            } label: {
                Image(systemName: "sparkles")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
            }
            .accessibilityLabel("Drop Agent into Insight")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(AgentTheme.bar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Agent Channel")
                .font(.system(size: 32, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Your Token Factory agent lives here. It reads Mail, Calendar, Notes, and Weather — then suggests how to run your week, month, or year.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.55))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 6) {
                Circle()
                    .fill(AgentTheme.accent)
                    .frame(width: 6, height: 6)
                Text("Powered by Nebius · NVIDIA Nemotron")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
        }
    }

    private var sourceStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                sourceChip("Mail", ok: mail.isSignedIn, detail: mail.isSignedIn ? "\(mail.messages.count)" : "Sign in")
                sourceChip("Calendar", ok: calendar.isSignedIn, detail: calendar.isSignedIn ? "\(calendar.events.count)" : "Sign in")
                sourceChip("Notes", ok: !notes.notes.isEmpty, detail: "\(notes.notes.count)")
                sourceChip("Weather", ok: weather.snapshot != nil, detail: weather.snapshot?.placeName ?? "Open app")
            }
        }
    }

    private func sourceChip(_ title: String, ok: Bool, detail: String) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(ok ? Color(red: 0.45, green: 0.82, blue: 0.58) : Color.white.opacity(0.25))
                .frame(width: 6, height: 6)
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.9))
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(AgentTheme.card, in: Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(0.10), lineWidth: 1))
    }

    private var horizonRow: some View {
        HStack(spacing: 8) {
            ForEach(AgentPlanHorizon.allCases) { item in
                Button {
                    horizon = item
                } label: {
                    Text(item.title)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(horizon == item ? .white : .white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .frame(height: 36)
                        .background(
                            horizon == item ? AgentTheme.action : AgentTheme.card,
                            in: Capsule()
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var planButton: some View {
        Button {
            fieldFocused = false
            Keyboard.dismiss()
            Task { await runPlan() }
        } label: {
            HStack(spacing: 8) {
                if isBusy {
                    ProgressView().tint(.white)
                } else {
                    Image(systemName: "wand.and.stars")
                }
                Text(isBusy ? "Planning…" : "Plan my \(horizon.title.lowercased())")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(AgentTheme.action.opacity(isBusy ? 0.55 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .disabled(isBusy)
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("READY")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2.4)
                .foregroundStyle(AgentTheme.accent)
            Text("Ask for a plan, or pick Week / Month / Year.")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Sign into Mail and Calendar for richer suggestions. Notes and Weather help when available.")
                .font(.system(size: 13, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(AgentTheme.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .stroke(Color.white.opacity(0.12), lineWidth: 1)
                )
        )
    }

    private func bubble(_ message: AgentMessage) -> some View {
        HStack {
            if message.role == .user { Spacer(minLength: 36) }
            Text(message.text)
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.92))
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(message.role == .user ? Color(red: 0.18, green: 0.28, blue: 0.55) : AgentTheme.card)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(message.role == .agent ? 0.12 : 0.08), lineWidth: 1)
                )
            if message.role == .agent { Spacer(minLength: 36) }
        }
    }

    private var composer: some View {
        HStack(spacing: 10) {
            Image(systemName: "bubble.left.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white.opacity(0.45))
            TextField("Ask your agent…", text: $draft)
                .textInputAutocapitalization(.sentences)
                .foregroundStyle(.white)
                .focused($fieldFocused)
                .submitLabel(.send)
                .onSubmit {
                    Task { await sendChat() }
                }
            Button {
                Task { await sendChat() }
            } label: {
                Image(systemName: "arrow.up")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 34, height: 34)
                    .background(AgentTheme.action.opacity(canSend ? 1 : 0.4), in: Circle())
            }
            .disabled(!canSend)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AgentTheme.bar)
    }

    private var canSend: Bool {
        !isBusy && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy) {
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            withAnimation {
                if let last = messages.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                } else if isBusy {
                    proxy.scrollTo("busy", anchor: .bottom)
                }
            }
        }
    }

    private func contextBundle() -> String {
        var parts: [String] = [
            "PortalOS Agent Channel context. Use only what is listed. If a source is missing, say so and plan with what you have.",
            "Horizon selected: \(horizon.title)."
        ]
        if let mailContext = mail.insightContext {
            parts.append("MAIL:\n\(mailContext)")
        } else {
            parts.append("MAIL: not signed in or empty.")
        }
        if let calendarContext = calendar.insightContext {
            parts.append("CALENDAR:\n\(calendarContext)")
        } else {
            parts.append("CALENDAR: not signed in or empty.")
        }
        if let notesContext = notes.agentContext {
            parts.append("NOTES:\n\(notesContext)")
        } else {
            parts.append("NOTES: none.")
        }
        if let weatherContext = weather.insightContext {
            parts.append("WEATHER:\n\(weatherContext)")
        } else {
            parts.append("WEATHER: no forecast loaded.")
        }
        return parts.joined(separator: "\n\n")
    }

    @MainActor
    private func runPlan() async {
        guard !isBusy else { return }
        let prompt = horizon.prompt
        messages.append(AgentMessage(role: .user, text: prompt))
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        do {
            let reply = try await nebius.generateAgentPlan(
                horizon: horizon,
                contextHint: contextBundle(),
                userPrompt: prompt
            )
            messages.append(AgentMessage(role: .agent, text: reply))
        } catch {
            errorText = error.localizedDescription
            messages.append(AgentMessage(role: .agent, text: "Could not reach Token Factory. \(error.localizedDescription)"))
        }
    }

    @MainActor
    private func sendChat() async {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isBusy else { return }
        draft = ""
        fieldFocused = false
        Keyboard.dismiss()
        messages.append(AgentMessage(role: .user, text: text))
        isBusy = true
        errorText = nil
        defer { isBusy = false }
        let history = messages.suffix(10).map { msg in
            "\(msg.role == .user ? "User" : "Agent"): \(msg.text)"
        }.joined(separator: "\n")
        do {
            let reply = try await nebius.agentChannelReply(
                contextHint: contextBundle(),
                history: history,
                userPrompt: text
            )
            messages.append(AgentMessage(role: .agent, text: reply))
        } catch {
            errorText = error.localizedDescription
            messages.append(AgentMessage(role: .agent, text: "Could not reach Token Factory. \(error.localizedDescription)"))
        }
    }
}

extension NotesStore {
    /// Broader note pack for the Agent Channel (not just the selected note).
    var agentContext: String? {
        guard !notes.isEmpty else { return nil }
        var parts = ["\(notes.count) notes on this phone."]
        for note in notes.prefix(8) {
            let title = note.title.isEmpty ? "Untitled" : note.title
            let body = note.body.trimmingCharacters(in: .whitespacesAndNewlines)
            let clip = body.isEmpty ? "(empty)" : String(body.prefix(280))
            parts.append("- \(title): \(clip)")
        }
        return parts.joined(separator: "\n")
    }
}
