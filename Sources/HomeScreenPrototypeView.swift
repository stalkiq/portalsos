import SwiftUI

struct HomeScreenPrototypeView: View {
    private let nebiusService = NebiusService()
    private let apps: [AppShortcut] = [
        .init(name: "Phone", symbol: "phone.fill"),
        .init(name: "Messages", symbol: "message.fill"),
        .init(name: "Camera", symbol: "camera.fill"),
        .init(name: "Browser", symbol: "safari.fill")
    ]
    private let moreApps: [AppShortcut] = [
        .init(name: "Mail", symbol: "envelope.fill"),
        .init(name: "Maps", symbol: "map.fill"),
        .init(name: "Music", symbol: "music.note"),
        .init(name: "Notes", symbol: "note.text"),
        .init(name: "Calendar", symbol: "calendar"),
        .init(name: "Weather", symbol: "cloud.sun.fill"),
        .init(name: "Files", symbol: "folder.fill"),
        .init(name: "Health", symbol: "heart.fill"),
        .init(name: "Wallet", symbol: "creditcard.fill"),
        .init(name: "Clock", symbol: "clock.fill"),
        .init(name: "Tasks", symbol: "checkmark.circle.fill"),
        .init(name: "Photos", symbol: "photo.fill.on.rectangle.fill"),
        .init(name: "Settings", symbol: "gearshape.fill"),
        .init(name: "Podcasts", symbol: "mic.fill"),
        .init(name: "News", symbol: "newspaper.fill"),
        .init(name: "Store", symbol: "bag.fill")
    ]
    @State private var droppedApp: AppShortcut?
    @State private var isChatDropTargeted = false
    @State private var activeDragAppID: String?
    @State private var activeDragTranslation: CGSize = .zero
    @State private var openedApp: AppShortcut?
    @State private var isAppDrawerExpanded = false
    @State private var isSystemOn = false
    @State private var insightInput = ""
    @State private var activityFeed: [AIActivityEvent] = [
        .init(title: "AI system ready", detail: "Waiting for app context drop.", symbol: "sparkles")
    ]
    @State private var autopilotFeed: [AutopilotActionEvent] = [
        .init(title: "Autopilot standby", detail: "Turn ON to start proactive actions.", symbol: "power")
    ]
    @State private var autopilotActionIndex = 0
    @State private var generatedInsight: String?
    @State private var isGeneratingInsight = false
    @State private var insightErrorMessage: String?
    @GestureState private var drawerDragOffset: CGFloat = 0

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.06, green: 0.07, blue: 0.11),
                    Color(red: 0.08, green: 0.09, blue: 0.15),
                    Color(red: 0.04, green: 0.05, blue: 0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            RadialGradient(
                colors: [
                    Color(red: 0.26, green: 0.30, blue: 0.52).opacity(0.45),
                    .clear
                ],
                center: .topTrailing,
                startRadius: 40,
                endRadius: 320
            )
            .ignoresSafeArea()

            GeometryReader { geometry in
                let horizontalInset: CGFloat = 12
                let width = min(geometry.size.width - (horizontalInset * 2), 402)
                let height = width * 2.05
                let drawerRevealProgress = drawerProgress
                let drawerHeight = 316 * drawerRevealProgress
                let chatHeight = width * (0.90 - (0.26 * drawerRevealProgress))
                let feedHeight = max(0, 116 - (110 * drawerRevealProgress))
                let minimizedHeight: CGFloat = 200
                let panelHeight = isSystemOn ? minimizedHeight : height
                let panelY = isSystemOn ? geometry.size.height - (panelHeight / 2) - 20 : geometry.size.height / 2

                if isSystemOn {
                    VStack(spacing: 0) {
                        autopilotWorkspace(width: width)
                            .padding(.top, 80)
                        Spacer(minLength: 0)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
                }

                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(red: 0.12, green: 0.13, blue: 0.18),
                                Color(red: 0.09, green: 0.10, blue: 0.14)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 36, style: .continuous)
                            .stroke(
                                LinearGradient(
                                    colors: [
                                        Color.white.opacity(0.22),
                                        Color.white.opacity(0.05)
                                    ],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ),
                                lineWidth: 1.5
                            )
                    )
                    .frame(width: width, height: panelHeight)
                    .shadow(color: Color.black.opacity(0.55), radius: 28, x: 0, y: 18)
                    .overlay {
                        if isSystemOn {
                            minimizedCardContent(width: width)
                        } else {
                            fullCardContent(
                                width: width,
                                drawerRevealProgress: drawerRevealProgress,
                                drawerHeight: drawerHeight,
                                chatHeight: chatHeight,
                                feedHeight: feedHeight
                            )
                        }
                    }
                    .position(x: geometry.size.width / 2, y: panelY)
            }
            .padding(.vertical, 16)
        }
        .fullScreenCover(item: $openedApp) { app in
            PrototypeAppDetailView(app: app)
        }
        .task(id: isSystemOn) {
            guard isSystemOn else { return }
            await requestNebiusAutopilotAction()
            while !Task.isCancelled && isSystemOn {
                try? await Task.sleep(nanoseconds: 8_000_000_000)
                guard !Task.isCancelled, isSystemOn else { break }
                await requestNebiusAutopilotAction()
            }
        }
    }

    private var drawerProgress: CGFloat {
        let baseProgress: CGFloat = isAppDrawerExpanded ? 1 : 0
        let progress = baseProgress + (drawerDragOffset / 140)
        return min(max(progress, 0), 1)
    }

    private func fullCardContent(
        width: CGFloat,
        drawerRevealProgress: CGFloat,
        drawerHeight: CGFloat,
        chatHeight: CGFloat,
        feedHeight: CGFloat
    ) -> some View {
        VStack(spacing: 18) {
            HStack {
                powerSlider
                Spacer()
            }
            .frame(width: width * 0.84)
            .padding(.top, 24)

            HStack(spacing: 12) {
                ForEach(apps) { app in
                    appTile(for: app)
                        .scaleEffect(activeDragAppID == app.id ? 1.05 : 1)
                        .offset(activeDragAppID == app.id ? activeDragTranslation : .zero)
                        .zIndex(activeDragAppID == app.id ? 10 : 0)
                        .onTapGesture {
                            openedApp = app
                        }
                        .gesture(
                            DragGesture(minimumDistance: 12)
                                .onChanged { value in
                                    activeDragAppID = app.id
                                    activeDragTranslation = value.translation
                                    isChatDropTargeted = isInChatDropZone(
                                        translation: value.translation,
                                        panelWidth: width
                                    )
                                }
                                .onEnded { value in
                                    let didDropIntoChat = isInChatDropZone(
                                        translation: value.translation,
                                        panelWidth: width
                                    )

                                    withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                        if didDropIntoChat {
                                            droppedApp = app
                                            addActivity(for: app)
                                            generatedInsight = nil
                                            insightErrorMessage = nil
                                            Task {
                                                await requestNebiusInsight(app: app, userPrompt: nil)
                                            }
                                        }
                                        activeDragAppID = nil
                                        activeDragTranslation = .zero
                                        isChatDropTargeted = false
                                    }
                                }
                        )
                }
            }
            .padding(.top, 4)

            appDrawerHandle(progress: drawerRevealProgress)
                .gesture(
                    DragGesture(minimumDistance: 2)
                        .updating($drawerDragOffset) { value, state, _ in
                            state = value.translation.height
                        }
                        .onEnded { value in
                            let progressFromGesture = (isAppDrawerExpanded ? 1.0 : 0.0) + (value.translation.height / 140)
                            withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                                isAppDrawerExpanded = progressFromGesture > 0.52
                            }
                        }
                )
                .onTapGesture {
                    withAnimation(.spring(response: 0.34, dampingFraction: 0.88)) {
                        isAppDrawerExpanded.toggle()
                    }
                }

            if drawerHeight > 1 {
                LazyVGrid(
                    columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 4),
                    spacing: 10
                ) {
                    ForEach(moreApps) { app in
                        appTile(for: app)
                            .onTapGesture {
                                openedApp = app
                            }
                    }
                }
                .frame(width: width * 0.84, height: drawerHeight, alignment: .top)
                .opacity(drawerRevealProgress)
                .clipped()
            }

            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isChatDropTargeted ? 0.20 : 0.10),
                            Color.white.opacity(isChatDropTargeted ? 0.09 : 0.04)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(isChatDropTargeted ? 0.42 : 0.14), lineWidth: 1.1)
                )
                .frame(width: width * 0.78, height: chatHeight)
                .shadow(color: Color.black.opacity(0.30), radius: 12, x: 0, y: 8)
                .overlay {
                    chatBoxContent
                }

            if feedHeight > 8 {
                liveActivityFeed
                    .frame(width: width * 0.78, height: feedHeight)
                    .transition(.opacity)
            }

            Spacer(minLength: 0)
        }
    }

    private func minimizedCardContent(width: CGFloat) -> some View {
        VStack(spacing: 12) {
            HStack {
                powerSlider
                Spacer()
            }
            .frame(width: width * 0.84)
            .padding(.top, 20)

            HStack(spacing: 12) {
                ForEach(apps) { app in
                    appTile(for: app)
                        .onTapGesture {
                            openedApp = app
                        }
                }
            }

            Text("Autopilot running")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))

            Spacer(minLength: 0)
        }
    }

    private func isInChatDropZone(translation: CGSize, panelWidth: CGFloat) -> Bool {
        let verticalMin: CGFloat = 88
        let verticalMax: CGFloat = panelWidth * 1.1
        let horizontalTolerance: CGFloat = panelWidth * 0.30

        return translation.height > verticalMin &&
            translation.height < verticalMax &&
            abs(translation.width) < horizontalTolerance
    }

    private func addActivity(for app: AppShortcut) {
        let event = AIActivityEvent(
            title: "Processed \(app.name)",
            detail: app.activitySummary,
            symbol: app.symbol
        )
        activityFeed.insert(event, at: 0)
        if activityFeed.count > 5 {
            activityFeed = Array(activityFeed.prefix(5))
        }
    }

    @MainActor
    private func requestNebiusInsight(app: AppShortcut?, userPrompt: String?) async {
        isGeneratingInsight = true
        insightErrorMessage = nil
        do {
            let response = try await nebiusService.generateInsight(for: app?.name, contextHint: app?.chatInsight, userPrompt: userPrompt)
            generatedInsight = response
        } catch NebiusServiceError.missingAPIKey {
            generatedInsight = nil
            insightErrorMessage = "Nebius is not configured yet. Add NEBIUS_API_KEY in Edit Scheme → Run → Arguments."
        } catch NebiusServiceError.serverMessage(let message) {
            generatedInsight = nil
            insightErrorMessage = "Nebius request failed. \(message)"
        } catch {
            generatedInsight = nil
            insightErrorMessage = "Nebius request failed. \(error.localizedDescription)"
        }
        isGeneratingInsight = false
    }

    private func appDrawerHandle(progress: CGFloat) -> some View {
        VStack(spacing: 4) {
            Capsule()
                .fill(Color.white.opacity(0.30))
                .frame(width: 34, height: 2.4)
            Capsule()
                .fill(Color.white.opacity(0.24))
                .frame(width: 24, height: 2.2)
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 14, height: 2)
        }
        .padding(.vertical, 2)
        .opacity(0.55 + (0.30 * progress))
        .shadow(color: Color(red: 0.42, green: 0.50, blue: 0.95).opacity(0.20 + (0.20 * progress)), radius: 6, x: 0, y: 2)
    }

    private var powerSlider: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                isSystemOn.toggle()
                if isSystemOn {
                    isAppDrawerExpanded = false
                    autopilotFeed = [
                        .init(title: "Autopilot engaged", detail: "Background agent is now handling routine tasks.", symbol: "bolt.fill")
                    ]
                } else {
                    autopilotFeed = [
                        .init(title: "Autopilot standby", detail: "Turn ON to start proactive actions.", symbol: "power")
                    ]
                }
            }
        } label: {
            ZStack(alignment: isSystemOn ? .trailing : .leading) {
                Capsule(style: .continuous)
                    .fill(isSystemOn ? Color.green.opacity(0.82) : Color.red.opacity(0.82))
                    .frame(width: 54, height: 30)
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color.white.opacity(0.16), lineWidth: 1)
                    )

                Circle()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 24, height: 24)
                    .padding(3)
                    .shadow(color: Color.black.opacity(0.28), radius: 2, x: 0, y: 1)
            }
            .overlay {
                Text(isSystemOn ? "ON" : "OFF")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .offset(x: isSystemOn ? -10 : 10)
            }
        }
        .buttonStyle(.plain)
    }

    private func appTile(for app: AppShortcut) -> some View {
        RoundedRectangle(cornerRadius: 18, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.16),
                        Color.white.opacity(0.06)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.white.opacity(0.20), lineWidth: 1)
            )
            .overlay {
                VStack(spacing: 6) {
                    Image(systemName: app.symbol)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(app.name)
                        .font(.system(size: 8, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(.horizontal, 4)
            }
            .frame(width: 68, height: 68)
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 5)
    }

    private var liveActivityFeed: some View {
        RoundedRectangle(cornerRadius: 20, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.08),
                        Color.white.opacity(0.03)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .stroke(Color.white.opacity(0.12), lineWidth: 1)
            )
            .overlay {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "waveform.path.ecg")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.88))
                        Text("Live AI Activity")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                    }

                    ForEach(activityFeed.prefix(2)) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: event.symbol)
                                .font(.system(size: 10, weight: .semibold))
                                .frame(width: 14)
                                .foregroundStyle(.white.opacity(0.75))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.88))
                                    .lineLimit(1)
                                Text(event.detail)
                                    .font(.system(size: 10, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.66))
                                    .lineLimit(1)
                            }
                            Spacer()
                        }
                    }

                    Spacer(minLength: 0)
                }
                .padding(12)
            }
    }

    @MainActor
    private func requestNebiusAutopilotAction() async {
        do {
            let payload = try await nebiusService.generateAutopilotAction()
            let event = AutopilotActionEvent(
                title: payload.title,
                detail: payload.detail,
                symbol: payload.symbol
            )
            autopilotActionIndex += 1
            withAnimation(.easeInOut(duration: 0.2)) {
                autopilotFeed.insert(event, at: 0)
                if autopilotFeed.count > 6 {
                    autopilotFeed = Array(autopilotFeed.prefix(6))
                }
            }
        } catch {
            let event = AutopilotActionEvent(
                title: "Autopilot waiting on Nebius",
                detail: error.localizedDescription,
                symbol: "exclamationmark.triangle.fill"
            )
            withAnimation(.easeInOut(duration: 0.2)) {
                autopilotFeed.insert(event, at: 0)
                if autopilotFeed.count > 6 {
                    autopilotFeed = Array(autopilotFeed.prefix(6))
                }
            }
        }
    }

    private func autopilotWorkspace(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 26, style: .continuous)
            .fill(
                LinearGradient(
                    colors: [
                        Color.white.opacity(0.10),
                        Color.white.opacity(0.04)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .overlay {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        Image(systemName: "bolt.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.green.opacity(0.95))
                        Text("PortalsOS Autopilot")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Spacer()
                        Text("LIVE")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white.opacity(0.85))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.34), in: Capsule())
                    }

                    Text("Autonomous actions running independently from Live AI Activity.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))

                    ForEach(autopilotFeed.prefix(4)) { event in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: event.symbol)
                                .font(.system(size: 11, weight: .semibold))
                                .frame(width: 14)
                                .foregroundStyle(.white.opacity(0.8))
                            VStack(alignment: .leading, spacing: 2) {
                                Text(event.title)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))
                                Text(event.detail)
                                    .font(.system(size: 11, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.72))
                                    .lineLimit(2)
                            }
                            Spacer(minLength: 0)
                        }
                    }
                }
                .padding(16)
            }
            .frame(width: width * 0.90, height: 330)
            .shadow(color: Color.black.opacity(0.30), radius: 18, x: 0, y: 10)
    }

    private var chatBoxContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.white.opacity(0.95))
                Text("PortalsOS Insight")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.95))
            }

            if let app = droppedApp {
                Text("Analyzing: \(app.name)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if isGeneratingInsight {
                    Text("Nebius is generating insight...")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                } else if let generatedInsight {
                    Text(generatedInsight)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.84))
                        .lineSpacing(3)
                } else if let insightErrorMessage {
                    Text(insightErrorMessage)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.red.opacity(0.85))
                        .lineSpacing(3)
                } else {
                    Text(app.chatInsight)
                        .font(.system(size: 12, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineSpacing(3)
                }
            } else {
                Text("Drag any app from the top row into this box.")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                Text("Nebius will use context from that app and suggest useful next actions.")
                    .font(.system(size: 12, weight: .regular))
                    .foregroundStyle(.white.opacity(0.75))
                    .lineSpacing(3)
            }

            Spacer(minLength: 10)

            HStack(spacing: 8) {
                Image(systemName: "message.fill")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.75))
                TextField("Ask PortalsOS about this app context...", text: $insightInput)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.92))
                    .textInputAutocapitalization(.sentences)
                    .disableAutocorrection(false)
                    .submitLabel(.send)
                    .onSubmit {
                        let trimmed = insightInput.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        let event = AIActivityEvent(
                            title: "Question queued",
                            detail: trimmed,
                            symbol: "message.fill"
                        )
                        activityFeed.insert(event, at: 0)
                        if activityFeed.count > 5 {
                            activityFeed = Array(activityFeed.prefix(5))
                        }
                        insightInput = ""
                        Task {
                            await requestNebiusInsight(app: droppedApp, userPrompt: trimmed)
                        }
                    }
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(Color.white.opacity(0.09), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.white.opacity(0.16), lineWidth: 1)
            )
            .padding(.bottom, 4)
        }
        .padding(20)
    }
}

private struct AppShortcut: Identifiable {
    let id: String
    let name: String
    let symbol: String

    init(name: String, symbol: String) {
        self.id = name
        self.name = name
        self.symbol = symbol
    }

    var chatInsight: String {
        switch id {
        case "Phone":
            return "Detected recent and frequent contacts. Suggestion: prioritize callbacks, summarize missed-call patterns, and draft quick follow-up messages."
        case "Messages":
            return "Detected active threads. Suggestion: generate smart replies, highlight unanswered messages, and summarize high-priority conversations."
        case "Camera":
            return "Detected new photos. Suggestion: auto-group scenes, extract text from images, and build memory highlights you can search instantly."
        case "Browser":
            return "Detected open web sessions. Suggestion: summarize pages, compare sources, and transform research into a short action plan."
        default:
            return "Context received. Generating additional insights."
        }
    }

    var activitySummary: String {
        switch id {
        case "Phone":
            return "Analyzed recent calls and suggested follow-up priorities."
        case "Messages":
            return "Ranked unread threads and drafted response suggestions."
        case "Camera":
            return "Extracted scenes and generated searchable visual highlights."
        case "Browser":
            return "Summarized open pages into a short action list."
        default:
            return "Processed app context and created fresh insights."
        }
    }

    var fullScreenDescription: String {
        switch id {
        case "Phone":
            return "Call history, contacts, and call tools are available here."
        case "Messages":
            return "Conversations, reply suggestions, and thread organization live here."
        case "Camera":
            return "Capture flow, media tools, and smart image analysis controls."
        case "Browser":
            return "Tabs, search, and web research assistant tools in one place."
        default:
            return "Interactive prototype app screen."
        }
    }

    var quickActions: [String] {
        switch id {
        case "Phone":
            return ["View recent calls", "Dial favorite contact", "Open voicemail summary"]
        case "Messages":
            return ["Jump to unread threads", "Generate smart reply", "Create message draft"]
        case "Camera":
            return ["Open camera roll", "Scan text from image", "Create highlight reel"]
        case "Browser":
            return ["Open last tab group", "Summarize current page", "Compare two sources"]
        default:
            return ["Open", "Inspect", "Analyze"]
        }
    }
}

private struct AIActivityEvent: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
}

private struct AutopilotActionEvent: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
}

private struct PrototypeAppDetailView: View {
    let app: AppShortcut
    @Environment(\.dismiss) private var dismiss
    @State private var input = ""

    var body: some View {
        NavigationStack {
            ZStack {
                LinearGradient(
                    colors: [
                        Color(red: 0.06, green: 0.07, blue: 0.11),
                        Color(red: 0.10, green: 0.10, blue: 0.18)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 12) {
                        Image(systemName: app.symbol)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.95))
                        Text("\(app.name) App")
                            .font(.system(size: 24, weight: .bold))
                            .foregroundStyle(.white.opacity(0.96))
                    }

                    Text(app.fullScreenDescription)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))

                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(Color.white.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .stroke(Color.white.opacity(0.16), lineWidth: 1)
                        )
                        .overlay {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Prototype Controls")
                                    .font(.system(size: 15, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.92))

                                TextField("Type a command...", text: $input)
                                    .textFieldStyle(.roundedBorder)

                                Text("User input: \(input.isEmpty ? "none" : input)")
                                    .font(.system(size: 13, weight: .regular))
                                    .foregroundStyle(.white.opacity(0.74))
                            }
                            .padding(16)
                        }
                        .frame(height: 170)

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Quick Actions")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.92))
                        ForEach(app.quickActions, id: \.self) { action in
                            Text("- \(action)")
                                .font(.system(size: 14, weight: .regular))
                                .foregroundStyle(.white.opacity(0.82))
                        }
                    }

                    Spacer()
                }
                .padding(20)
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(.white)
                }
            }
        }
    }
}

#Preview {
    HomeScreenPrototypeView()
}
