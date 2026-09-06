import SwiftUI

private enum MailTheme {
    // Match PortalOS home: slate canvas + cool blue accents (not the old green “signals” look).
    static let canvas = Color(red: 0.06, green: 0.07, blue: 0.11)
    static let card = Color(red: 0.12, green: 0.13, blue: 0.18)
    static let accent = Color(red: 0.48, green: 0.62, blue: 1.0)
    static let bar = Color(red: 0.08, green: 0.09, blue: 0.14)
    static let action = Color(red: 0.27, green: 0.47, blue: 0.98)
    static let hairline = Color.white.opacity(0.12)
}

private struct MailComposeState {
    var to: String
    var subject: String
    var body: String
    var hint: String
    var replyTo: GmailMessage?
    var isDrafting = false
    var isSending = false
    var error: String?
}

private enum ComposeField: Hashable {
    case to, subject, hint, body
}

struct MailAppView: View {
    @ObservedObject var engine: GmailEngine
    var onAddToPortal: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var previewID: String?
    @State private var isSendingToPortal = false
    @State private var compose: MailComposeState?
    @State private var keyboardOverlap: CGFloat = 0
    @FocusState private var composeFocus: ComposeField?

    private let nebius = NebiusService()

    private var previewMessage: GmailMessage? {
        guard let previewID else { return nil }
        return engine.messages.first(where: { $0.id == previewID })
    }

    var body: some View {
        NavigationStack {
            ZStack {
                MailTheme.canvas.ignoresSafeArea(.container)

                if compose != nil {
                    composeScreen
                } else if engine.isSignedIn, previewMessage != nil {
                    messageReader
                } else if engine.isSignedIn {
                    inboxScreen
                } else {
                    signInPane
                }
            }
            .keyboardDoneButton()
            .readsKeyboardOverlap($keyboardOverlap)
            .toolbar(.hidden, for: .navigationBar)
            .task {
                await engine.restoreInboxIfNeeded()
            }
        }
    }

    private var inboxScreen: some View {
        ZStack {
            RadialGradient(
                colors: [
                    Color(red: 0.26, green: 0.30, blue: 0.52).opacity(0.40),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 20,
                endRadius: 280
            )
            .ignoresSafeArea(.container)

            VStack(spacing: 0) {
                topBar {
                    Button("Close") { dismiss() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white)
                    Spacer()
                    Button {
                        compose = MailComposeState(to: "", subject: "", body: "", hint: "", replyTo: nil)
                    } label: {
                        Image(systemName: "square.and.pencil")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 34, height: 34)
                    }
                    Menu {
                        Button {
                            Task { await engine.refreshInbox() }
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                        Button(role: .destructive, action: engine.signOut) {
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
                    VStack(alignment: .leading, spacing: 22) {
                        inboxTitleRow
                        if let errorMessage = engine.errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.red.opacity(0.9))
                        }
                        if engine.messages.isEmpty, engine.isBusy {
                            skeletonCards
                        } else if engine.messages.isEmpty {
                            emptyCard
                        } else {
                            if let latest = engine.messages.first {
                                Button {
                                    open(latest)
                                } label: {
                                    latestDrop(latest)
                                }
                                .buttonStyle(.plain)
                            }
                            if engine.messages.count > 1 {
                                Text("Earlier")
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .tracking(2.4)
                                    .foregroundStyle(.white.opacity(0.45))
                                timeline
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 20)
                    .padding(.bottom, 40)
                }
                .refreshable {
                    await engine.refreshInbox()
                }
            }
        }
    }

    private func topBar<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        HStack {
            content()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(MailTheme.bar)
    }

    private var inboxTitleRow: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text("Mail")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(MailTheme.accent)
                        .frame(width: 7, height: 7)
                    Text("LIVE")
                        .font(.system(size: 11, weight: .heavy, design: .rounded))
                        .tracking(1.4)
                        .foregroundStyle(MailTheme.accent)
                }
            }
            Text(engine.email.isEmpty ? "\(engine.messages.count) messages" : "\(engine.messages.count) messages  ·  \(engine.email)")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .lineLimit(1)
            poweredByNebius
        }
    }

    private func latestDrop(_ message: GmailMessage) -> some View {
        ZStack(alignment: .topTrailing) {
            Text(senderInitial(message.from))
                .font(.system(size: 88, weight: .bold, design: .rounded))
                .foregroundStyle(MailTheme.accent.opacity(0.12))
                .offset(x: 12, y: -18)

            VStack(alignment: .leading, spacing: 12) {
                Text("NOW")
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .tracking(3)
                    .foregroundStyle(MailTheme.accent)
                Text(message.subject)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                Text(message.snippet)
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
                HStack {
                    Text(senderName(message.from).uppercased())
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                        .tracking(1.1)
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                    Spacer()
                    Text(shortDate(message.date))
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(MailTheme.accent.opacity(0.9))
                }
            }
            .padding(20)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.14, green: 0.16, blue: 0.24),
                            Color(red: 0.10, green: 0.11, blue: 0.16)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(engine.messages.dropFirst())) { message in
                Button {
                    open(message)
                } label: {
                    HStack(alignment: .top, spacing: 14) {
                        VStack(spacing: 0) {
                            Circle()
                                .fill(MailTheme.accent)
                                .frame(width: 8, height: 8)
                                .padding(.top, 6)
                            Rectangle()
                                .fill(MailTheme.accent.opacity(0.25))
                                .frame(width: 1)
                                .frame(maxHeight: .infinity)
                        }
                        .frame(width: 8)

                        VStack(alignment: .leading, spacing: 4) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(senderName(message.from))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                                Spacer()
                                Text(shortDate(message.date))
                                    .font(.system(size: 11, weight: .medium, design: .rounded))
                                    .foregroundStyle(.white.opacity(0.35))
                            }
                            Text(message.subject)
                                .font(.system(size: 16, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                        }
                        .padding(.bottom, 18)
                    }
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var emptyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("INBOX")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .tracking(2.6)
                .foregroundStyle(MailTheme.accent)
            Text("Inbox is quiet.")
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
            Text("Compose, or pull down to refresh.")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(.white.opacity(0.45))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 28)
    }

    private var skeletonCards: some View {
        VStack(alignment: .leading, spacing: 16) {
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(MailTheme.card)
                .frame(height: 180)
            ForEach(0..<4, id: \.self) { _ in
                HStack(spacing: 14) {
                    Circle().fill(MailTheme.accent.opacity(0.3)).frame(width: 8, height: 8)
                    VStack(alignment: .leading, spacing: 8) {
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.08)).frame(width: 80, height: 8)
                        RoundedRectangle(cornerRadius: 4).fill(Color.white.opacity(0.12)).frame(height: 14)
                    }
                }
            }
        }
    }

    private func open(_ message: GmailMessage) {
        previewID = message.id
        Task { await engine.openMessage(message) }
    }

    private var messageReader: some View {
        VStack(spacing: 0) {
            topBar {
                Button {
                    previewID = nil
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                        Text("Inbox")
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                }
                Spacer()
            }

            if let message = previewMessage {
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text("MESSAGE")
                            .font(.system(size: 11, weight: .bold, design: .rounded))
                            .tracking(2.4)
                            .foregroundStyle(MailTheme.accent)
                        Text(message.subject)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack(spacing: 8) {
                            Text(senderName(message.from))
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 6)
                                .background(MailTheme.card, in: Capsule())
                            Text(shortDate(message.date))
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                        Rectangle()
                            .fill(MailTheme.hairline)
                            .frame(height: 1)
                        if message.body == nil, engine.isBusy {
                            ProgressView().tint(MailTheme.accent)
                        } else {
                            Text(message.body ?? message.snippet)
                                .font(.system(size: 17, weight: .regular))
                                .foregroundStyle(.white.opacity(0.86))
                                .lineSpacing(6)
                        }
                    }
                    .padding(20)
                }

                VStack(spacing: 10) {
                    HStack(spacing: 8) {
                        readerAction("Reply", symbol: "arrowshape.turn.up.left") {
                            openReply(to: message)
                        }
                        readerAction("Archive", symbol: "archivebox") {
                            Task {
                                await engine.archiveMessage(message)
                                previewID = nil
                            }
                        }
                        readerAction("Trash", symbol: "trash") {
                            Task {
                                await engine.trashMessage(message)
                                previewID = nil
                            }
                        }
                    }
                    Button(action: addPreviewToPortal) {
                        HStack(spacing: 8) {
                            if isSendingToPortal {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "sparkles")
                            }
                            Text("Add to Portal")
                                .font(.system(size: 16, weight: .semibold))
                        }
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(MailTheme.action.opacity(isSendingToPortal ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }
                    .disabled(isSendingToPortal)
                    poweredByNebius
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 18)
                .background(MailTheme.canvas)
            }
        }
    }

    private func readerAction(_ title: String, symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 58)
            .background(MailTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }

    private var composeScreen: some View {
        VStack(spacing: 0) {
            topBar {
                Button("Cancel") {
                    composeFocus = nil
                    Keyboard.dismiss()
                    compose = nil
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                Spacer()
                Text(compose?.replyTo == nil ? "New Message" : "Reply")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.white)
                Spacer()
                Button("Send") {
                    composeFocus = nil
                    Keyboard.dismiss()
                    Task { await sendCompose() }
                }
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(MailTheme.accent)
                .disabled(compose?.isSending == true || compose?.isDrafting == true)
            }

            if let compose {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 14) {
                            composeField("To", text: composeBinding(\.to), field: .to, next: .subject)
                            composeField("Subject", text: composeBinding(\.subject), field: .subject, next: .hint)
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Direction for Token Factory")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.5))
                                TextField("Optional: keep it short, decline politely...", text: composeBinding(\.hint))
                                    .textInputAutocapitalization(.sentences)
                                    .foregroundStyle(.white)
                                    .focused($composeFocus, equals: .hint)
                                    .submitLabel(.next)
                                    .onSubmit { composeFocus = .body }
                            }
                            .id(ComposeField.hint)
                            .padding(12)
                            .background(MailTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                            Button {
                                composeFocus = nil
                                Keyboard.dismiss()
                                Task { await draftWithNebius() }
                            } label: {
                                HStack {
                                    if compose.isDrafting {
                                        ProgressView().tint(.white)
                                    } else {
                                        Image(systemName: "sparkles")
                                    }
                                    Text(compose.isDrafting ? "Nemotron is writing..." : "Write with Token Factory")
                                        .font(.system(size: 15, weight: .semibold))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 48)
                                .background(MailTheme.action.opacity(compose.isDrafting ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .disabled(compose.isDrafting || compose.isSending)

                            Text("Body")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(.white.opacity(0.5))
                            TextEditor(text: composeBinding(\.body))
                                .scrollContentBackground(.hidden)
                                .foregroundStyle(.white)
                                .focused($composeFocus, equals: .body)
                                .frame(minHeight: 180)
                                .padding(10)
                                .background(MailTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .id(ComposeField.body)

                            if let error = compose.error {
                                Text(error)
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(.red.opacity(0.9))
                            }
                            poweredByNebius
                        }
                        .padding(18)
                        .padding(.bottom, max(24, keyboardOverlap))
                    }
                    .dismissesKeyboardOnScroll()
                    .onChange(of: composeFocus) { _, field in
                        guard let field else { return }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                            withAnimation {
                                proxy.scrollTo(field, anchor: .center)
                            }
                        }
                    }
                }
            }
        }
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
                Text("Connect Gmail")
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                Text("Read, reply, archive, and draft with Nebius Token Factory.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.55))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)

                if let errorMessage = engine.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.red.opacity(0.9))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }

                Button {
                    Task { await engine.signIn() }
                } label: {
                    Text(engine.isBusy ? "Connecting..." : "Sign in with Google")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 54)
                        .background(MailTheme.action.opacity(engine.isBusy ? 0.5 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .disabled(engine.isBusy)
                .padding(.horizontal, 28)

                poweredByNebius
                Spacer()
            }
        }
    }

    private var poweredByNebius: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(MailTheme.accent)
                .frame(width: 6, height: 6)
            Text("Powered by Nebius")
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(.white.opacity(0.45))
        }
    }

    private func composeField(
        _ title: String,
        text: Binding<String>,
        field: ComposeField,
        next: ComposeField?
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white.opacity(0.5))
            TextField(title, text: text)
                .textInputAutocapitalization(.never)
                .keyboardType(title == "To" ? .emailAddress : .default)
                .foregroundStyle(.white)
                .focused($composeFocus, equals: field)
                .submitLabel(next == nil ? .done : .next)
                .onSubmit {
                    if let next {
                        composeFocus = next
                    } else {
                        Keyboard.dismiss()
                    }
                }
        }
        .id(field)
        .padding(12)
        .background(MailTheme.card, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func composeBinding(_ keyPath: WritableKeyPath<MailComposeState, String>) -> Binding<String> {
        Binding(
            get: { compose?[keyPath: keyPath] ?? "" },
            set: { compose?[keyPath: keyPath] = $0 }
        )
    }

    private func openReply(to message: GmailMessage) {
        compose = MailComposeState(
            to: message.senderEmail,
            subject: message.replySubject,
            body: "",
            hint: "",
            replyTo: message
        )
    }

    private func draftWithNebius() async {
        guard var current = compose else { return }
        current.isDrafting = true
        current.error = nil
        compose = current
        do {
            let draft = try await nebius.generateMailDraft(
                to: current.to,
                subject: current.subject,
                originalBody: current.replyTo?.body ?? current.replyTo?.snippet,
                instruction: current.hint,
                isReply: current.replyTo != nil
            ) { partial in
                compose?.body = partial
            }
            compose?.body = draft
        } catch {
            compose?.error = error.localizedDescription
        }
        compose?.isDrafting = false
    }

    private func sendCompose() async {
        guard let current = compose else { return }
        compose?.isSending = true
        compose?.error = nil
        do {
            try await engine.sendMail(
                to: current.to,
                subject: current.subject,
                body: current.body,
                replyTo: current.replyTo
            )
            compose = nil
            previewID = nil
        } catch {
            compose?.error = error.localizedDescription
            compose?.isSending = false
        }
    }

    private func addPreviewToPortal() {
        guard let message = previewMessage else { return }
        isSendingToPortal = true
        Task {
            await engine.openMessage(message)
            isSendingToPortal = false
            previewID = nil
            dismiss()
            onAddToPortal()
        }
    }

    private func senderName(_ from: String) -> String {
        let trimmed = from.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "<") {
            let name = trimmed[..<start]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .replacingOccurrences(of: "\"", with: "")
            if !name.isEmpty {
                return name
            }
        }
        if let at = trimmed.firstIndex(of: "@") {
            return String(trimmed[..<at])
        }
        return trimmed.isEmpty ? "Unknown" : trimmed
    }

    private func senderInitial(_ from: String) -> String {
        let name = senderName(from)
        return String(name.prefix(1)).uppercased()
    }

    private func shortDate(_ raw: String) -> String {
        let cleaned = raw.replacingOccurrences(of: "\\s+\\([^)]+\\)$", with: "", options: .regularExpression)
        let parser = DateFormatter()
        parser.locale = Locale(identifier: "en_US_POSIX")
        let formats = [
            "EEE, dd MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "dd MMM yyyy HH:mm:ss Z"
        ]
        for format in formats {
            parser.dateFormat = format
            if let date = parser.date(from: cleaned) {
                if Calendar.current.isDateInToday(date) {
                    let output = DateFormatter()
                    output.dateFormat = "h:mm a"
                    return output.string(from: date)
                }
                let output = DateFormatter()
                output.dateFormat = "MMM d"
                return output.string(from: date)
            }
        }
        return ""
    }
}
