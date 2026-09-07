import SwiftUI

struct HomeScreenPrototypeView: View {
    private let nebiusService = NebiusService()
    private let apps: [AppShortcut] = [
        .init(name: "Browser", symbol: "safari.fill"),
        .init(name: "Camera", symbol: "camera.fill"),
        .init(name: "Notes", symbol: "note.text"),
        .init(name: "Mail", symbol: "envelope.fill")
    ]
    private let moreApps: [AppShortcut] = [
        .init(name: "Agent", symbol: "sparkles"),
        .init(name: "Calendar", symbol: "calendar"),
        .init(name: "Weather", symbol: "cloud.sun.fill"),
        .init(name: "Maps", symbol: "map.fill")
    ]
    @State private var droppedApp: AppShortcut?
    @State private var isChatDropTargeted = false
    @State private var activeDragAppID: String?
    @State private var activeDragTranslation: CGSize = .zero
    @State private var openedApp: AppShortcut?
    @State private var isSystemOn = false
    @State private var insightInput = ""
    @State private var activityFeed: [AIActivityEvent] = [
        .init(title: "AI system ready", detail: "Waiting for app context drop.", symbol: "sparkles")
    ]
    @State private var autopilotFeed: [AutopilotActionEvent] = [
        .init(title: "Autopilot standby", detail: "Turn ON to watch Gmail, draft replies, and save important mail to Notes.", symbol: "power")
    ]
    @State private var autopilotActionIndex = 0
    @State private var autopilotDraftedIDs: Set<String> = []
    @State private var autopilotNotedIDs: Set<String> = []
    @State private var generatedInsight: String?
    @State private var isGeneratingInsight = false
    @State private var insightErrorMessage: String?
    @State private var didAddCameraInsightToNotes = false
    @StateObject private var browserEngine = BrowserEngine()
    @StateObject private var cameraEngine = CameraEngine()
    @StateObject private var notesStore = NotesStore()
    @StateObject private var mailEngine: GmailEngine
    @StateObject private var calendarEngine: GoogleCalendarEngine
    @StateObject private var weatherEngine = WeatherEngine()
    @StateObject private var mapsEngine = MapsEngine()
    @State private var didAddWeatherInsightToNotes = false
    @State private var didAddMapsInsightToNotes = false
    @State private var didAddCalendarInsightToNotes = false
    @State private var calendarBrief: CalendarBrief?
    @State private var didAddCalendarBuffer = false
    @State private var isAddingCalendarBuffer = false

    init() {
        let mail = GmailEngine()
        _mailEngine = StateObject(wrappedValue: mail)
        _calendarEngine = StateObject(wrappedValue: GoogleCalendarEngine(account: mail))
    }
    @State private var keyboardOverlap: CGFloat = 0
    @State private var isInsightComposerOpen = false
    @FocusState private var insightFieldFocused: Bool
    @State private var insightTurns: [InsightTurn] = []
    @State private var isAppDrawerExpanded = false
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

            Text("PortalOS")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.38))
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
                .padding(.top, 4)
                .padding(.trailing, 14)
                .ignoresSafeArea(edges: .top)
                .allowsHitTesting(false)

            GeometryReader { geometry in
                let horizontalInset: CGFloat = 12
                let width = min(geometry.size.width - (horizontalInset * 2), 402)
                let height = width * 2.05
                let drawerRevealProgress: CGFloat = isSystemOn ? 0 : drawerProgress
                let drawerHeight = 76 * drawerRevealProgress
                let headerBlock: CGFloat = 96
                let dateLine: CGFloat = isSystemOn ? 0 : 28
                let slack: CGFloat = 22
                let chatHeight = max(260, height - headerBlock - slack - drawerHeight - dateLine)
                let insightWidth = width * 0.92

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
                    .frame(width: width, height: height)
                    .shadow(color: Color.black.opacity(0.55), radius: 28, x: 0, y: 18)
                    .overlay {
                        homeCardContent(
                            width: width,
                            insightWidth: insightWidth,
                            chatHeight: chatHeight,
                            drawerHeight: drawerHeight,
                            drawerProgress: drawerRevealProgress
                        )
                    }
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
                    .opacity(isInsightComposerOpen ? 0.38 : 1)
            }
            .padding(.vertical, 16)
            .allowsHitTesting(!isInsightComposerOpen)

            if isInsightComposerOpen, !isSystemOn, openedApp == nil {
                insightComposerOverlay
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .ignoresSafeArea(.keyboard)
        .animation(.spring(response: 0.32, dampingFraction: 0.86), value: isAppDrawerExpanded)
        .readsKeyboardOverlap($keyboardOverlap)
        .onChange(of: isSystemOn) { _, isOn in
            if isOn {
                closeInsightComposer()
                isAppDrawerExpanded = false
            }
        }
        .onChange(of: openedApp?.id) { _, id in
            if id != nil {
                closeInsightComposer()
            }
        }
        .fullScreenCover(item: $openedApp) { app in
            switch app.id {
            case "Camera":
                CameraAppView(engine: cameraEngine) {
                    guard let camera = appNamed("Camera") else { return }
                    droppedApp = camera
                    insightTurns = []
                    addActivity(for: camera)
                    generatedInsight = nil
                    insightErrorMessage = nil
                    Task {
                        await requestNebiusInsight(app: camera, userPrompt: "Read this photo now.")
                    }
                }
            case "Notes":
                NotesAppView(store: notesStore)
            case "Mail":
                MailAppView(engine: mailEngine) {
                    guard let mail = appNamed("Mail") else { return }
                    droppedApp = mail
                    insightTurns = []
                    addActivity(for: mail)
                    generatedInsight = nil
                    insightErrorMessage = nil
                    Task {
                        await requestNebiusInsight(
                            app: mail,
                            userPrompt: "Read this email and suggest what I should do next."
                        )
                    }
                }
            case "Calendar":
                CalendarAppView(account: mailEngine, engine: calendarEngine) {
                    guard let calendar = appNamed("Calendar") else { return }
                    droppedApp = calendar
                    insightTurns = []
                    addActivity(for: calendar)
                    generatedInsight = nil
                    insightErrorMessage = nil
                    Task {
                        await requestNebiusInsight(
                            app: calendar,
                            userPrompt: "Brief this Google Calendar. Lead with what is next, then today, then real conflicts and free time."
                        )
                    }
                }
            case "Weather":
                WeatherAppView(engine: weatherEngine) {
                    guard let weather = appNamed("Weather") else { return }
                    droppedApp = weather
                    insightTurns = []
                    addActivity(for: weather)
                    generatedInsight = nil
                    insightErrorMessage = nil
                    Task {
                        await requestNebiusInsight(
                            app: weather,
                            userPrompt: "Brief this Open-Meteo forecast. What to wear, umbrella or not, and the day that changes plans."
                        )
                    }
                }
            case "Maps":
                MapsAppView(engine: mapsEngine) {
                    guard let maps = appNamed("Maps") else { return }
                    droppedApp = maps
                    insightTurns = []
                    addActivity(for: maps)
                    generatedInsight = nil
                    insightErrorMessage = nil
                    didAddMapsInsightToNotes = false
                    Task {
                        await requestNebiusInsight(
                            app: maps,
                            userPrompt: "Brief this Google Maps place and route. Leave-by time, how to go, and what to watch for."
                        )
                    }
                }
            case "Agent":
                AgentChannelAppView(
                    mail: mailEngine,
                    calendar: calendarEngine,
                    notes: notesStore,
                    weather: weatherEngine,
                    maps: mapsEngine
                ) {
                    guard let agent = appNamed("Agent") else { return }
                    droppedApp = agent
                    insightTurns = []
                    addActivity(for: agent)
                    generatedInsight = nil
                    insightErrorMessage = nil
                    calendarBrief = nil
                    Task {
                        await requestNebiusInsight(
                            app: agent,
                            userPrompt: AgentPlanHorizon.week.prompt
                        )
                    }
                }
            default:
                BrowserAppView(engine: browserEngine)
            }
        }
        .task(id: isSystemOn) {
            guard isSystemOn else { return }
            await runAutopilotCycle()
            while !Task.isCancelled && isSystemOn {
                try? await Task.sleep(nanoseconds: 18_000_000_000)
                guard !Task.isCancelled, isSystemOn else { break }
                await runAutopilotCycle()
            }
        }
    }

    private func homeCardContent(
        width: CGFloat,
        insightWidth: CGFloat,
        chatHeight: CGFloat,
        drawerHeight: CGFloat,
        drawerProgress: CGFloat
    ) -> some View {
        VStack(spacing: 12) {
            appDock(width: width, allowsDrag: !isSystemOn)
                .padding(.top, 18)
                .frame(maxWidth: .infinity)
                .zIndex(30)

            if !isSystemOn {
                homeDateLabel
                    .padding(.top, 2)
                    .zIndex(5)

                extraAppsRow(width: width, allowsDrag: true)
                    .frame(minHeight: drawerHeight, alignment: .top)
                    .frame(height: isDraggingDrawerApp ? nil : drawerHeight, alignment: .top)
                    .modifier(ClipIfNeeded(enabled: !isDraggingDrawerApp))
                    .opacity(drawerProgress)
                    .allowsHitTesting(drawerProgress > 0.55)
                    .zIndex(30)

                insightSheet(
                    width: insightWidth,
                    height: chatHeight,
                    drawerProgress: drawerProgress
                )
                .zIndex(1)
            } else {
                autopilotWorkspace(width: insightWidth, height: chatHeight)
            }

            Spacer(minLength: 0)
        }
    }

    private var drawerProgress: CGFloat {
        let base: CGFloat = isAppDrawerExpanded ? 1 : 0
        return min(max(base + (drawerDragOffset / 90), 0), 1)
    }

    private var isDraggingDrawerApp: Bool {
        moreApps.contains(where: { $0.id == activeDragAppID })
    }

    private func appNamed(_ name: String) -> AppShortcut? {
        (apps + moreApps).first(where: { $0.id == name })
    }

    private func appDrawerHandle(progress: CGFloat) -> some View {
        VStack(spacing: 3.5) {
            Capsule()
                .fill(Color.white.opacity(0.42 + (0.18 * progress)))
                .frame(width: 42, height: 3)
            Capsule()
                .fill(Color.white.opacity(0.26 + (0.14 * progress)))
                .frame(width: 30, height: 2.2)
            Capsule()
                .fill(Color.white.opacity(0.14 + (0.12 * progress)))
                .frame(width: 18, height: 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .accessibilityLabel(isAppDrawerExpanded ? "Hide more apps" : "Show more apps")
        .accessibilityAddTraits(.isButton)
    }

    private func insightSheet(width: CGFloat, height: CGFloat, drawerProgress: CGFloat) -> some View {
        VStack(spacing: 0) {
            appDrawerHandle(progress: drawerProgress)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .contentShape(Rectangle())
                .highPriorityGesture(drawerHandleGesture)

            chatBoxContent
        }
        .frame(width: width, height: height, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: 34, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(isChatDropTargeted ? 0.20 : 0.11),
                            Color.white.opacity(isChatDropTargeted ? 0.09 : 0.045)
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 34, style: .continuous)
                        .stroke(Color.white.opacity(isChatDropTargeted ? 0.42 : 0.14), lineWidth: 1.1)
                )
        )
        .shadow(color: Color.black.opacity(0.30), radius: 12, x: 0, y: 8)
        .clipShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var drawerHandleGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .updating($drawerDragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let travel = value.translation.height
                let flick = value.predictedEndTranslation.height
                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                    if abs(travel) < 10, abs(value.translation.width) < 10 {
                        isAppDrawerExpanded.toggle()
                    } else if travel > 22 || flick > 70 {
                        isAppDrawerExpanded = true
                    } else if travel < -18 || flick < -70 {
                        isAppDrawerExpanded = false
                    }
                }
            }
    }

    private var homeDateLabel: some View {
        TimelineView(.periodic(from: .now, by: 60)) { context in
            Text(context.date.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white.opacity(0.42))
                .frame(maxWidth: .infinity)
        }
    }

    private func appDock(width: CGFloat, allowsDrag: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(apps) { app in
                appIcon(for: app, width: width, allowsDrag: allowsDrag)
            }
            Spacer(minLength: 6)
            powerButton
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(width: width * 0.92)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color.white.opacity(0.07))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
    }

    private func extraAppsRow(width: CGFloat, allowsDrag: Bool) -> some View {
        HStack(spacing: 8) {
            ForEach(moreApps) { app in
                appIcon(for: app, width: width, allowsDrag: allowsDrag)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .frame(width: width * 0.92, alignment: .leading)
        .frame(maxWidth: .infinity)
    }

    private func appIcon(for app: AppShortcut, width: CGFloat, allowsDrag: Bool) -> some View {
        let tile = appTile(for: app)
            .scaleEffect(activeDragAppID == app.id ? 1.05 : 1)
            .offset(activeDragAppID == app.id ? activeDragTranslation : .zero)
            .zIndex(activeDragAppID == app.id ? 10 : 0)
            .onTapGesture {
                openedApp = app
            }

        return Group {
            if allowsDrag {
                tile.highPriorityGesture(
                    DragGesture(minimumDistance: 8)
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
                                    insightTurns = []
                                    addActivity(for: app)
                                    generatedInsight = nil
                                    insightErrorMessage = nil
                                    Task {
                                        await requestNebiusInsight(
                                            app: app,
                                            userPrompt: dropPrompt(for: app)
                                        )
                                    }
                                }
                                activeDragAppID = nil
                                activeDragTranslation = .zero
                                isChatDropTargeted = false
                            }
                        }
                )
            } else {
                tile
            }
        }
        .zIndex(activeDragAppID == app.id ? 40 : 0)
    }

    private func isInChatDropZone(translation: CGSize, panelWidth: CGFloat) -> Bool {
        let verticalMin: CGFloat = 48
        let verticalMax: CGFloat = panelWidth * 1.1
        let horizontalTolerance: CGFloat = panelWidth * 0.48

        return translation.height > verticalMin &&
            translation.height < verticalMax &&
            abs(translation.width) < horizontalTolerance
    }

    private func insightHint(for app: AppShortcut?) -> String? {
        switch app?.id {
        case "Browser":
            return browserEngine.insightContext ?? app?.chatInsight
        case "Camera":
            return cameraEngine.insightContext ?? app?.chatInsight
        case "Notes":
            return notesStore.insightContext ?? app?.chatInsight
        case "Mail":
            return mailEngine.insightContext ?? app?.chatInsight
        case "Calendar":
            return calendarEngine.insightContext ?? app?.chatInsight
        case "Weather":
            return weatherEngine.insightContext ?? app?.chatInsight
        case "Maps":
            return mapsEngine.insightContext ?? app?.chatInsight
        case "Agent":
            return agentContextBundle()
        default:
            return app?.chatInsight
        }
    }

    private func agentContextBundle() -> String {
        var parts: [String] = [
            "PortalOS Agent Channel context. Use only what is listed. If a source is missing, say so and plan with what you have."
        ]
        if let mailContext = mailEngine.insightContext {
            parts.append("MAIL:\n\(mailContext)")
        } else {
            parts.append("MAIL: not signed in or empty.")
        }
        if let calendarContext = calendarEngine.insightContext {
            parts.append("CALENDAR:\n\(calendarContext)")
        } else {
            parts.append("CALENDAR: not signed in or empty.")
        }
        if let notesContext = notesStore.agentContext {
            parts.append("NOTES:\n\(notesContext)")
        } else {
            parts.append("NOTES: none.")
        }
        if let weatherContext = weatherEngine.insightContext {
            parts.append("WEATHER:\n\(weatherContext)")
        } else {
            parts.append("WEATHER: no forecast loaded.")
        }
        if let mapsContext = mapsEngine.insightContext {
            parts.append("MAPS:\n\(mapsContext)")
        } else {
            parts.append("MAPS: no place or route loaded.")
        }
        return parts.joined(separator: "\n\n")
    }

    private func agentHorizon(from prompt: String?) -> AgentPlanHorizon {
        let lower = (prompt ?? "").lowercased()
        if lower.contains("year") { return .year }
        if lower.contains("month") { return .month }
        return .week
    }

    private func dropPrompt(for app: AppShortcut) -> String? {
        switch app.id {
        case "Mail":
            return "Triage this live inbox. What is important, what is not, and what is safe to delete. Use the real senders and subjects."
        case "Calendar":
            return "Brief this Google Calendar. Lead with what is next, then today, then real conflicts and free time."
        case "Weather":
            return "Brief this Open-Meteo forecast. What to wear, umbrella or not, and the day that changes plans."
        case "Maps":
            return "Brief this Google Maps place and route. Leave-by time, how to go, and what to watch for."
        case "Agent":
            return AgentPlanHorizon.week.prompt
        default:
            return nil
        }
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
        if app?.id == "Camera" {
            didAddCameraInsightToNotes = false
        }
        if app?.id == "Weather" {
            didAddWeatherInsightToNotes = false
        }
        if app?.id == "Calendar" {
            didAddCalendarInsightToNotes = false
            didAddCalendarBuffer = false
            calendarBrief = nil
        }
        if app?.id == "Mail" {
            if !mailEngine.isSignedIn {
                let text = "Open Mail and sign in with Google, then drop it here. Insight will brief the inbox: what to act on, what to ignore, and what is safe to delete."
                generatedInsight = text
                appendAssistantTurn(text)
                isGeneratingInsight = false
                return
            }
            await mailEngine.restoreInboxIfNeeded()
        }
        if app?.id == "Calendar" {
            if !mailEngine.isSignedIn {
                let text = "Open Calendar or Mail and sign in with Google, then drop Calendar here. Token Factory will brief the next two weeks."
                generatedInsight = text
                appendAssistantTurn(text)
                isGeneratingInsight = false
                return
            }
            await calendarEngine.refresh()
        }
        if app?.id == "Weather", weatherEngine.snapshot == nil {
            let text = "Open Weather, search a city or tap location, then drop it here. Open-Meteo loads the forecast; Token Factory tells you what to do with it."
            generatedInsight = text
            appendAssistantTurn(text)
            isGeneratingInsight = false
            return
        }
        if app?.id == "Maps", mapsEngine.selectedPlace == nil, mapsEngine.insightContext == nil {
            let text = "Open Maps, search a place, pick a pin, then drop it here. Google Places/Routes provide the data; Token Factory briefs the trip."
            generatedInsight = text
            appendAssistantTurn(text)
            isGeneratingInsight = false
            return
        }
        if app?.id == "Maps" {
            didAddMapsInsightToNotes = false
        }
        if app?.id == "Agent" {
            await mailEngine.restoreInboxIfNeeded()
            await calendarEngine.restoreIfNeeded()
        }
        do {
            if app?.id == "Agent" {
                generatedInsight = nil
                calendarBrief = nil
                let horizon = agentHorizon(from: userPrompt)
                let isPlanAsk: Bool = {
                    let lower = (userPrompt ?? "").lowercased()
                    return lower.contains("plan my")
                        || lower.contains("plan the")
                        || lower.isEmpty
                }()
                let response: String
                if isPlanAsk {
                    response = try await nebiusService.generateAgentPlan(
                        horizon: horizon,
                        contextHint: agentContextBundle(),
                        userPrompt: userPrompt ?? horizon.prompt
                    )
                } else {
                    let history = insightTurns.suffix(8).map { turn in
                        "\(turn.role == .user ? "User" : "Agent"): \(turn.text)"
                    }.joined(separator: "\n")
                    response = try await nebiusService.agentChannelReply(
                        contextHint: agentContextBundle(),
                        history: history,
                        userPrompt: userPrompt ?? "What should I focus on next?"
                    )
                }
                let clean = scrubInsightIDs(response)
                generatedInsight = clean
                upsertAssistantTurn(clean)
            } else if app?.id == "Mail", let userPrompt, !userPrompt.isEmpty {
                let intent = try await nebiusService.interpretMailChat(
                    contextHint: insightHint(for: app),
                    userPrompt: userPrompt
                )
                await applyMailIntent(intent)
            } else if app?.id == "Calendar", shouldGenerateCalendarBrief(userPrompt) {
                generatedInsight = nil
                let brief = try await nebiusService.generateCalendarBrief(
                    contextHint: insightHint(for: app),
                    userPrompt: userPrompt
                )
                calendarBrief = brief
                generatedInsight = brief.noteBody
                upsertAssistantTurn(brief.hero)
            } else if app?.id == "Calendar", let userPrompt, !userPrompt.isEmpty {
                let intent = try await nebiusService.interpretCalendarChat(
                    contextHint: insightHint(for: app),
                    userPrompt: userPrompt
                )
                await applyCalendarIntent(intent)
            } else {
                generatedInsight = nil
                let response = try await nebiusService.generateInsight(
                    for: app?.name,
                    contextHint: insightHint(for: app),
                    userPrompt: userPrompt,
                    imageJPEG: app?.id == "Camera" ? cameraEngine.jpegData : nil
                ) { partial in
                    let clean = scrubInsightIDs(partial)
                    generatedInsight = clean
                    upsertAssistantTurn(clean)
                }
                let clean = scrubInsightIDs(response)
                generatedInsight = clean
                upsertAssistantTurn(clean)
            }
        } catch NebiusServiceError.missingAPIKey {
            let text = "Nebius is not configured yet. Rebuild PortalOS from Xcode after backend/.env has NEBIUS_API_KEY."
            generatedInsight = nil
            insightErrorMessage = text
            upsertAssistantTurn(text)
        } catch NebiusServiceError.timedOut {
            let text = "Nebius timed out. Drop the app into Insight again — Token Factory can take a moment on the first request."
            generatedInsight = nil
            insightErrorMessage = text
            upsertAssistantTurn(text)
        } catch NebiusServiceError.serverMessage(let message) {
            let text = "Nebius request failed. \(message)"
            generatedInsight = nil
            insightErrorMessage = text
            upsertAssistantTurn(text)
        } catch {
            let text = "Nebius request failed. \(error.localizedDescription)"
            generatedInsight = nil
            insightErrorMessage = text
            upsertAssistantTurn(text)
        }
        isGeneratingInsight = false
    }

    private func addCameraInsightToNotes() {
        guard !didAddCameraInsightToNotes,
              let image = cameraEngine.lastImage,
              let insight = generatedInsight else {
            return
        }
        notesStore.addNote(fromCameraImage: image, insight: insight)
        didAddCameraInsightToNotes = true
        activityFeed.insert(
            AIActivityEvent(
                title: "Saved to Notes",
                detail: notesStore.selectedNote?.title ?? "Camera note",
                symbol: "note.text"
            ),
            at: 0
        )
        if activityFeed.count > 5 {
            activityFeed = Array(activityFeed.prefix(5))
        }
    }

    private func canSaveInsightToNotes(_ app: AppShortcut) -> Bool {
        switch app.id {
        case "Camera":
            return cameraEngine.lastImage != nil
        case "Weather", "Maps":
            return generatedInsight != nil
        default:
            return false
        }
    }

    private func didSaveInsight(for app: AppShortcut) -> Bool {
        switch app.id {
        case "Camera":
            return didAddCameraInsightToNotes
        case "Weather":
            return didAddWeatherInsightToNotes
        case "Maps":
            return didAddMapsInsightToNotes
        case "Calendar":
            return didAddCalendarInsightToNotes
        default:
            return false
        }
    }

    private func saveInsightToNotes(for app: AppShortcut) {
        if app.id == "Camera" {
            addCameraInsightToNotes()
            return
        }
        guard let insight = generatedInsight, !insight.isEmpty else { return }
        if app.id == "Weather" {
            guard !didAddWeatherInsightToNotes else { return }
            notesStore.addNote(title: weatherEngine.snapshot?.placeName ?? "Weather", body: insight)
            didAddWeatherInsightToNotes = true
        } else if app.id == "Maps" {
            guard !didAddMapsInsightToNotes else { return }
            notesStore.addNote(title: mapsEngine.selectedPlace?.name ?? "Maps brief", body: insight)
            didAddMapsInsightToNotes = true
        } else if app.id == "Calendar" {
            guard !didAddCalendarInsightToNotes else { return }
            notesStore.addNote(title: calendarBrief?.hero ?? "Calendar brief", body: insight)
            didAddCalendarInsightToNotes = true
        } else {
            return
        }
        activityFeed.insert(
            AIActivityEvent(title: "Saved to Notes", detail: notesStore.selectedNote?.title ?? app.name, symbol: "note.text"),
            at: 0
        )
        if activityFeed.count > 5 {
            activityFeed = Array(activityFeed.prefix(5))
        }
    }

    private func insightBusyLabel(for app: AppShortcut) -> String {
        switch app.id {
        case "Camera":
            return "Token Factory vision is reading the photo..."
        case "Mail":
            return "Nemotron is triaging your inbox..."
        case "Calendar":
            return "Token Factory is reading Google Calendar..."
        case "Weather":
            return "Nemotron is reading the Open-Meteo forecast..."
        case "Maps":
            return "Token Factory is briefing your Google Maps route..."
        case "Agent":
            return "Token Factory agent is planning from your apps..."
        default:
            return "Nemotron is generating insight..."
        }
    }

    private func calendarBriefView(_ brief: CalendarBrief) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text(brief.hero)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(.white)
                    .fixedSize(horizontal: false, vertical: true)
                if !brief.detail.isEmpty {
                    Text(brief.detail)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.62))
                        .fixedSize(horizontal: false, vertical: true)
                }
                VStack(spacing: 8) {
                    calendarChip(
                        title: brief.nextLabel,
                        detail: brief.nextDetail,
                        symbol: "clock.fill",
                        tint: Color(red: 0.55, green: 0.62, blue: 0.98)
                    )
                    calendarChip(
                        title: brief.displayRiskLabel,
                        detail: brief.displayRiskDetail,
                        symbol: brief.hasRisk ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        tint: brief.hasRisk
                            ? Color(red: 0.98, green: 0.62, blue: 0.38)
                            : Color(red: 0.45, green: 0.82, blue: 0.58)
                    )
                    calendarChip(
                        title: brief.freeLabel,
                        detail: brief.freeDetail,
                        symbol: "moon.stars.fill",
                        tint: Color(red: 0.52, green: 0.82, blue: 0.72)
                    )
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 4)
        }
    }

    private func calendarChip(title: String, detail: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 18)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .tracking(1.1)
                    .foregroundStyle(tint)
                Text(detail.isEmpty ? "—" : detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.88))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(tint.opacity(0.28), lineWidth: 1)
        )
    }

    private func calendarBriefActions(_ brief: CalendarBrief) -> some View {
        Group {
            if brief.canAddBuffer {
                Button {
                    Task { await addCalendarBuffer(from: brief) }
                } label: {
                    HStack(spacing: 8) {
                        if isAddingCalendarBuffer {
                            ProgressView().tint(.white)
                        } else {
                            Image(systemName: didAddCalendarBuffer ? "checkmark.circle.fill" : "plus.circle.fill")
                        }
                        Text(didAddCalendarBuffer ? "Buffer added" : "Add \(brief.bufferTitle ?? "travel buffer")")
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(
                        Color(red: 0.98, green: 0.52, blue: 0.28).opacity(didAddCalendarBuffer ? 0.45 : 0.92),
                        in: Capsule()
                    )
                }
                .disabled(didAddCalendarBuffer || isAddingCalendarBuffer)
            }
        }
    }

    @MainActor
    private func addCalendarBuffer(from brief: CalendarBrief) async {
        guard !didAddCalendarBuffer, let start = Self.parseCalendarDate(brief.bufferStart) else { return }
        isAddingCalendarBuffer = true
        defer { isAddingCalendarBuffer = false }
        let end = Self.parseCalendarDate(brief.bufferEnd) ?? start.addingTimeInterval(90 * 60)
        do {
            let created = try await calendarEngine.createEvent(
                title: brief.bufferTitle ?? "Travel buffer",
                start: start,
                end: end,
                location: nil
            )
            didAddCalendarBuffer = true
            activityFeed.insert(
                AIActivityEvent(title: "Calendar buffer", detail: created.title, symbol: "calendar.badge.plus"),
                at: 0
            )
        } catch {
            insightErrorMessage = error.localizedDescription
        }
    }

    private func shouldGenerateCalendarBrief(_ prompt: String?) -> Bool {
        guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return true
        }
        return prompt.hasPrefix("Brief this Google Calendar")
    }

    private var powerButton: some View {
        Button {
            withAnimation(.spring(response: 0.24, dampingFraction: 0.85)) {
                isSystemOn.toggle()
                if isSystemOn {
                    autopilotFeed = [
                        .init(title: "Watching Gmail", detail: "Autopilot will triage new mail, draft replies, and save important threads to Notes. Drafts are not sent until you tap Send.", symbol: "bolt.fill")
                    ]
                } else {
                    autopilotFeed = [
                        .init(title: "Autopilot standby", detail: "Turn ON to watch Gmail, draft replies, and save important mail to Notes.", symbol: "power")
                    ]
                }
            }
        } label: {
            Circle()
                .fill(
                    isSystemOn
                        ? Color(red: 0.24, green: 0.81, blue: 0.42)
                        : Color(red: 0.89, green: 0.29, blue: 0.29)
                )
                .frame(width: 28, height: 28)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(isSystemOn ? "Autopilot on" : "Autopilot off")
        .accessibilityAddTraits(.isButton)
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
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.95))
                    Text(app.name)
                        .font(.system(size: 9, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                        .lineLimit(1)
                }
                .padding(.horizontal, 2)
            }
            .frame(width: 62, height: 62)
            .shadow(color: Color.black.opacity(0.16), radius: 4, x: 0, y: 2)
    }

    @MainActor
    private func runAutopilotCycle() async {
        guard isSystemOn else { return }
        if !mailEngine.isSignedIn {
            pushAutopilot(
                title: "Gmail needed",
                detail: "Open Mail and sign in. Autopilot only acts on your live inbox.",
                symbol: "envelope.badge"
            )
            return
        }

        await mailEngine.refreshInbox()

        do {
            let intent = try await nebiusService.watchInbox(
                contextHint: mailEngine.insightContext,
                skipDraftIDs: Array(autopilotDraftedIDs),
                skipNoteIDs: Array(autopilotNotedIDs)
            )
            await applyAutopilotWatch(intent)
        } catch {
            pushAutopilot(
                title: "Autopilot waiting on Nebius",
                detail: error.localizedDescription,
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }

    @MainActor
    private func applyAutopilotWatch(_ intent: AutopilotWatchIntent) async {
        let target = resolveAutopilotMessage(intent)
        switch intent.action {
        case .idle:
            pushAutopilot(
                title: "Inbox watch",
                detail: intent.summary,
                symbol: "envelope.fill",
                replaceMatchingTitle: "Inbox watch"
            )
        case .draft:
            guard let target, !autopilotDraftedIDs.contains(target.id) else {
                pushAutopilot(title: "Inbox watch", detail: intent.summary, symbol: "envelope.fill", replaceMatchingTitle: "Inbox watch")
                return
            }
            let full = await mailEngine.loadBody(for: target)
            do {
                let body = try await nebiusService.generateMailDraft(
                    to: full.senderEmail,
                    subject: full.replySubject,
                    originalBody: full.body ?? full.snippet,
                    instruction: intent.draftInstruction ?? "Write a short, specific reply the user can send.",
                    isReply: true
                )
                autopilotDraftedIDs.insert(full.id)
                let draft = AutopilotMailDraft(
                    id: full.id,
                    to: full.senderEmail,
                    subject: full.replySubject,
                    body: body
                )
                let reason = intent.reason ?? intent.summary
                pushAutopilot(
                    title: "Draft ready",
                    detail: "\(reason)\n\nTo \(full.senderEmail): \(body)",
                    symbol: "square.and.pencil",
                    draft: draft
                )
            } catch {
                pushAutopilot(
                    title: "Could not draft",
                    detail: error.localizedDescription,
                    symbol: "exclamationmark.triangle.fill"
                )
            }
        case .note:
            guard let target, !autopilotNotedIDs.contains(target.id) else {
                pushAutopilot(title: "Inbox watch", detail: intent.summary, symbol: "envelope.fill", replaceMatchingTitle: "Inbox watch")
                return
            }
            let full = await mailEngine.loadBody(for: target)
            let title = intent.noteTitle ?? full.subject
            let body = intent.noteBody ?? """
            From: \(full.from)
            Subject: \(full.subject)

            \(full.body ?? full.snippet)
            """
            let note = notesStore.addNote(title: title, body: body)
            autopilotNotedIDs.insert(full.id)
            pushAutopilot(
                title: "Saved to Notes",
                detail: "“\(note.title)” — \(intent.reason ?? intent.summary)",
                symbol: "note.text"
            )
        }
    }

    private func resolveAutopilotMessage(_ intent: AutopilotWatchIntent) -> GmailMessage? {
        if let id = intent.messageId, let message = mailEngine.message(id: id) {
            return message
        }
        return mailEngine.messageMatching(
            to: nil,
            sender: intent.matchSender,
            subject: intent.matchSubject
        )
    }

    private func pushAutopilot(
        title: String,
        detail: String,
        symbol: String,
        draft: AutopilotMailDraft? = nil,
        replaceMatchingTitle: String? = nil
    ) {
        autopilotActionIndex += 1
        withAnimation(.easeInOut(duration: 0.2)) {
            if let replaceMatchingTitle,
               let index = autopilotFeed.firstIndex(where: { $0.title == replaceMatchingTitle && $0.draft == nil }) {
                autopilotFeed[index] = AutopilotActionEvent(
                    title: title,
                    detail: detail,
                    symbol: symbol,
                    draft: draft
                )
            } else {
                autopilotFeed.insert(
                    AutopilotActionEvent(title: title, detail: detail, symbol: symbol, draft: draft),
                    at: 0
                )
            }
            if autopilotFeed.count > 6 {
                autopilotFeed = Array(autopilotFeed.prefix(6))
            }
        }
    }

    @MainActor
    private func sendAutopilotDraft(_ event: AutopilotActionEvent) async {
        guard let draft = event.draft, !event.didSend else { return }
        do {
            try await mailEngine.sendMail(
                to: draft.to,
                subject: draft.subject,
                body: draft.body,
                replyTo: mailEngine.message(id: draft.id)
            )
            if let index = autopilotFeed.firstIndex(where: { $0.id == event.id }) {
                autopilotFeed[index].didSend = true
                autopilotFeed[index].detail = "Sent to \(draft.to)."
            }
        } catch {
            pushAutopilot(
                title: "Send failed",
                detail: error.localizedDescription,
                symbol: "exclamationmark.triangle.fill"
            )
        }
    }

    private func autopilotWorkspace(width: CGFloat, height: CGFloat) -> some View {
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
                        Text("PortalOS Autopilot")
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

                    Text("Watching Gmail. Replies are drafted, not sent. Important mail is saved to Notes.")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white.opacity(0.72))

                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            ForEach(autopilotFeed.prefix(4)) { event in
                                VStack(alignment: .leading, spacing: 8) {
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
                                                .lineLimit(event.draft == nil ? 3 : 6)
                                        }
                                        Spacer(minLength: 0)
                                    }
                                    if let draft = event.draft, !event.didSend {
                                        Button {
                                            Task { await sendAutopilotDraft(event) }
                                        } label: {
                                            Text("Send to \(draft.to)")
                                                .font(.system(size: 12, weight: .semibold))
                                                .foregroundStyle(.white)
                                                .frame(maxWidth: .infinity)
                                                .frame(height: 34)
                                                .background(Color.green.opacity(0.72), in: Capsule())
                                        }
                                        .buttonStyle(.plain)
                                    } else if event.didSend {
                                        Text("Sent")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(.green.opacity(0.9))
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(16)
            }
            .frame(width: width, height: height)
            .shadow(color: Color.black.opacity(0.30), radius: 18, x: 0, y: 10)
    }

    private var chatBoxContent: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let app = droppedApp {
                Text("Analyzing: \(app.name)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                if app.id == "Browser", browserEngine.hasLoadedPage {
                    Text(browserEngine.title)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                } else if app.id == "Camera", cameraEngine.lastImage != nil {
                    Text("Photo captured")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                } else if app.id == "Notes", let note = notesStore.selectedNote {
                    Text(note.title.isEmpty ? "Untitled note" : note.title)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                } else if app.id == "Mail", mailEngine.isSignedIn {
                    let unread = mailEngine.messages.filter(\.isUnread).count
                    Text("\(mailEngine.messages.count) messages · \(unread) unread")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                } else if app.id == "Calendar", mailEngine.isSignedIn {
                    Text("\(calendarEngine.events.count) upcoming events")
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                } else if app.id == "Weather", let place = weatherEngine.snapshot?.placeName {
                    Text(place)
                        .font(.system(size: 11, weight: .regular))
                        .foregroundStyle(.white.opacity(0.62))
                        .lineLimit(1)
                }
                if app.id == "Calendar", let brief = calendarBrief {
                    calendarBriefView(brief)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                    if isGeneratingInsight {
                        Text("Nemotron is writing...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if !isGeneratingInsight, brief.canAddBuffer {
                        calendarBriefActions(brief)
                    }
                } else if let generatedInsight, !generatedInsight.isEmpty {
                    ScrollView {
                        Text(generatedInsight)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.white.opacity(0.86))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    if isGeneratingInsight {
                        Text("Nemotron is writing...")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.white.opacity(0.5))
                    }
                    if !isGeneratingInsight, canSaveInsightToNotes(app) {
                        Button(action: { saveInsightToNotes(for: app) }) {
                            HStack(spacing: 8) {
                                Image(systemName: didSaveInsight(for: app) ? "checkmark.circle.fill" : "square.and.pencil")
                                Text(didSaveInsight(for: app) ? "Saved to Notes" : "Add to Notes")
                                    .font(.system(size: 13, weight: .semibold))
                            }
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .frame(height: 38)
                            .background(
                                Color(red: 0.28, green: 0.42, blue: 0.95).opacity(didSaveInsight(for: app) ? 0.45 : 0.92),
                                in: Capsule()
                            )
                        }
                        .disabled(didSaveInsight(for: app))
                    }
                } else if isGeneratingInsight {
                    Text(insightBusyLabel(for: app))
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.78))
                } else if let insightErrorMessage {
                    ScrollView {
                        Text(insightErrorMessage)
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.red.opacity(0.85))
                            .lineSpacing(4)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                } else {
                    Text(app.chatInsight)
                        .font(.system(size: 13, weight: .regular))
                        .foregroundStyle(.white.opacity(0.8))
                        .lineSpacing(4)
                }
            } else {
                Text("Drag an app in Portal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.white.opacity(0.28))
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 8)
            }

            Spacer(minLength: droppedApp == nil ? 8 : 10)

            Button {
                isInsightComposerOpen = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "message.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                    Text(insightInput.isEmpty ? insightPlaceholder : insightInput)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(insightInput.isEmpty ? .white.opacity(0.42) : .white)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.28))
                }
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Color.white.opacity(0.10), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .padding(.bottom, 2)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .padding(.top, 4)
    }

    private var insightComposerOverlay: some View {
        ZStack(alignment: .bottom) {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture {
                    closeInsightComposer()
                }

            insightComposerDock
                .padding(.horizontal, 12)
                .padding(.bottom, max(keyboardOverlap, 10))
                .onAppear {
                    DispatchQueue.main.async {
                        insightFieldFocused = true
                    }
                }
        }
    }

    private var insightComposerDock: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.white)
                Text(insightContextChip)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Button(action: closeInsightComposer) {
                    Image(systemName: "keyboard.chevron.compact.down")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.9))
                        .frame(width: 34, height: 34)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            Rectangle()
                .fill(Color.white.opacity(0.08))
                .frame(height: 1)

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(insightTurns) { turn in
                            insightBubble(for: turn)
                                .id(turn.id)
                        }
                        if isGeneratingInsight, insightTurns.last?.role != .assistant {
                            Text(droppedApp?.id == "Mail" ? "Nemotron is working..." : "Nemotron is writing...")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                                .id("typing")
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                .frame(minHeight: 88, maxHeight: 240)
                .dismissesKeyboardOnScroll()
                .onChange(of: generatedInsight) { _, _ in
                    scrollComposer(proxy)
                }
                .onChange(of: insightTurns.count) { _, _ in
                    scrollComposer(proxy)
                }
            }

            HStack(alignment: .bottom, spacing: 10) {
                TextField(
                    "",
                    text: $insightInput,
                    prompt: Text(insightPlaceholder).foregroundStyle(.white.opacity(0.38)),
                    axis: .vertical
                )
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.sentences)
                .submitLabel(.send)
                .lineLimit(1...4)
                .focused($insightFieldFocused)
                .onSubmit {
                    submitInsightQuestion()
                }

                Button(action: submitInsightQuestion) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(
                            Circle().fill(canSendInsight ? Color(red: 0.27, green: 0.52, blue: 0.98) : Color.white.opacity(0.16))
                        )
                }
                .disabled(!canSendInsight)
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(red: 0.07, green: 0.09, blue: 0.14))
        }
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.10, green: 0.12, blue: 0.18))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )
        )
        .shadow(color: .black.opacity(0.5), radius: 24, y: 10)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    private func insightBubble(for turn: InsightTurn) -> some View {
        HStack {
            if turn.role == .user {
                Spacer(minLength: 40)
            }
            Text(turn.text)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(.white.opacity(turn.role == .user ? 0.98 : 0.88))
                .lineSpacing(3)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(turn.role == .user ? Color(red: 0.22, green: 0.40, blue: 0.82) : Color.white.opacity(0.08))
                )
            if turn.role != .user {
                Spacer(minLength: 28)
            }
        }
    }

    private func scrollComposer(_ proxy: ScrollViewProxy) {
        let target = insightTurns.last?.id.uuidString ?? "typing"
        DispatchQueue.main.async {
            withAnimation(.easeOut(duration: 0.15)) {
                if let last = insightTurns.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                } else {
                    proxy.scrollTo(target, anchor: .bottom)
                }
            }
        }
    }

    private var insightPlaceholder: String {
        switch droppedApp?.id {
        case "Mail":
            return "Send a reply, or save an email to Notes…"
        case "Camera":
            return "Ask about this photo…"
        case "Notes":
            return "Ask about this note…"
        case "Browser":
            return "Ask about this page…"
        case "Calendar":
            return "Add an event, or ask about this week…"
        case "Weather":
            return "Ask about this forecast…"
        case "Maps":
            return "Ask about this place or route…"
        case "Agent":
            return "Plan my week, month, or year…"
        default:
            return "Ask PortalOS…"
        }
    }

    private var insightContextChip: String {
        guard let app = droppedApp else {
            return "Insight"
        }
        if app.id == "Mail", mailEngine.isSignedIn {
            let unread = mailEngine.messages.filter(\.isUnread).count
            return "Mail · \(mailEngine.messages.count) messages · \(unread) unread"
        }
        if app.id == "Calendar", mailEngine.isSignedIn {
            return "Calendar · \(calendarEngine.events.count) events"
        }
        if app.id == "Weather", let place = weatherEngine.snapshot?.placeName {
            return "Weather · \(place)"
        }
        if app.id == "Maps", let place = mapsEngine.selectedPlace {
            return "Maps · \(place.name)"
        }
        if app.id == "Agent" {
            var bits: [String] = ["Agent"]
            if mailEngine.isSignedIn { bits.append("Mail") }
            if calendarEngine.isSignedIn { bits.append("Cal") }
            if !notesStore.notes.isEmpty { bits.append("Notes") }
            if weatherEngine.snapshot != nil { bits.append("Weather") }
            if mapsEngine.selectedPlace != nil { bits.append("Maps") }
            return bits.joined(separator: " · ")
        }
        return "Analyzing \(app.name)"
    }

    private var canSendInsight: Bool {
        !insightInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func closeInsightComposer() {
        insightFieldFocused = false
        isInsightComposerOpen = false
        Keyboard.dismiss()
    }

    private func submitInsightQuestion() {
        let trimmed = insightInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        insightTurns.append(InsightTurn(role: .user, text: trimmed))
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

    private func upsertAssistantTurn(_ text: String) {
        let trimmed = scrubInsightIDs(text)
        guard !trimmed.isEmpty else { return }
        if insightTurns.last?.role == .assistant {
            insightTurns[insightTurns.count - 1].text = trimmed
        } else {
            insightTurns.append(InsightTurn(role: .assistant, text: trimmed))
        }
    }

    /// Hide Gmail/machine ids from phone-sized Insight copy.
    private func scrubInsightIDs(_ text: String) -> String {
        var out = text
        let patterns = [
            #"\s*\(id=[^)\s]+\)"#,
            #"\bid=[A-Za-z0-9._\-]+\b"#,
            #"\s*\([0-9a-fA-F]{10,}\)"#
        ]
        for pattern in patterns {
            out = out.replacingOccurrences(of: pattern, with: "", options: .regularExpression)
        }
        out = out.replacingOccurrences(of: #" {2,}"#, with: " ", options: .regularExpression)
        out = out.replacingOccurrences(of: #"\n{3,}"#, with: "\n\n", options: .regularExpression)
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func appendAssistantTurn(_ text: String) {
        upsertAssistantTurn(text)
    }

    @MainActor
    private func applyMailIntent(_ intent: MailChatIntent) async {
        var lines: [String] = []
        if !intent.message.isEmpty {
            lines.append(intent.message)
        }
        switch intent.action {
        case .insight:
            break
        case .sendEmail:
            guard mailEngine.isSignedIn else {
                lines.append("Sign in to Gmail first, then ask me to send it.")
                break
            }
            guard let to = intent.to, to.contains("@"), let body = intent.body, !body.isEmpty else {
                lines.append("Tell me who to send it to — a name from the inbox, or an email address.")
                break
            }
            let replyTo = mailEngine.messageMatching(
                to: intent.to,
                sender: intent.matchSender,
                subject: intent.matchSubject ?? intent.subject
            )
            do {
                try await mailEngine.sendMail(
                    to: to,
                    subject: intent.subject ?? replyTo?.replySubject ?? "Hello",
                    body: body,
                    replyTo: replyTo
                )
                lines.append("Sent to \(to).")
                activityFeed.insert(
                    AIActivityEvent(title: "Sent mail", detail: intent.subject ?? to, symbol: "paperplane.fill"),
                    at: 0
                )
            } catch {
                lines.append("Could not send: \(error.localizedDescription)")
            }
        case .saveNote:
            let body = intent.noteBody ?? intent.message
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                lines.append("I didn't have enough email detail to save.")
                break
            }
            let note = notesStore.addNote(title: intent.noteTitle ?? "Mail note", body: body)
            lines.append("Saved to Notes as “\(note.title)”.")
            activityFeed.insert(
                AIActivityEvent(title: "Saved to Notes", detail: note.title, symbol: "note.text"),
                at: 0
            )
        }
        let text = lines.joined(separator: "\n\n")
        generatedInsight = text
        upsertAssistantTurn(text)
    }

    @MainActor
    private func applyCalendarIntent(_ intent: CalendarChatIntent) async {
        var lines: [String] = []
        if !intent.message.isEmpty {
            lines.append(intent.message)
        }
        switch intent.action {
        case .insight:
            break
        case .createEvent:
            guard mailEngine.isSignedIn else {
                lines.append("Sign in with Google first, then ask me to add it.")
                break
            }
            guard let title = intent.title, !title.isEmpty, let start = Self.parseCalendarDate(intent.start) else {
                lines.append("Tell me the event title and when — for example “lunch with Sam Thursday at 1”.")
                break
            }
            do {
                let created = try await calendarEngine.createEvent(
                    title: title,
                    start: start,
                    end: Self.parseCalendarDate(intent.end),
                    location: intent.location
                )
                lines.append("Added to Google Calendar: \(created.title), \(created.timeLabel).")
                activityFeed.insert(
                    AIActivityEvent(title: "Calendar event", detail: created.title, symbol: "calendar"),
                    at: 0
                )
            } catch {
                lines.append("Could not add the event: \(error.localizedDescription)")
            }
        case .saveNote:
            let body = intent.noteBody ?? intent.message
            guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                lines.append("I didn't have enough calendar detail to save.")
                break
            }
            let note = notesStore.addNote(title: intent.noteTitle ?? "Calendar note", body: body)
            didAddCalendarInsightToNotes = true
            lines.append("Saved to Notes as “\(note.title)”.")
            activityFeed.insert(
                AIActivityEvent(title: "Saved to Notes", detail: note.title, symbol: "note.text"),
                at: 0
            )
        }
        let text = lines.joined(separator: "\n\n")
        generatedInsight = text
        upsertAssistantTurn(text)
    }

    private static func parseCalendarDate(_ raw: String?) -> Date? {
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        guard !trimmed.isEmpty else { return nil }
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = isoFractional.date(from: trimmed) { return date }
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: trimmed) { return date }
        let formats = [
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy-MM-dd HH:mm",
            "yyyy-MM-dd"
        ]
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in formats {
            formatter.dateFormat = format
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }
}

private struct InsightTurn: Identifiable {
    enum Role {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    var text: String
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
        case "Camera":
            return "No photo yet. Open Camera, shoot a sign, receipt, whiteboard, or product, then tap Read with Insight."
        case "Notes":
            return "No note selected. Open Notes, write something, then drop it here."
        case "Mail":
            return "Not signed in. Open Mail, sign in with Google, then drop it here for an inbox triage: what matters, what to ignore, and what to delete."
        case "Calendar":
            return "Not signed in. Open Calendar, sign in with Google, then drop it here. Token Factory will brief the next two weeks."
        case "Weather":
            return "No forecast yet. Open Weather, search a city, then drop it here. Open-Meteo loads the numbers; Token Factory tells you what to do."
        case "Maps":
            return "No place yet. Open Maps, search with Google Places, pick a pin, then drop it here for a Token Factory trip brief."
        case "Agent":
            return "Your Token Factory agent. Open Agent Channel, or drop it here to plan the week from Mail, Calendar, Notes, Weather, and Maps."
        default:
            return "No live page yet. Open Browser, visit a site, then drop it here — PortalOS will summarize that page."
        }
    }

    var activitySummary: String {
        switch id {
        case "Camera":
            return "Read visible text from the photo and suggested next actions."
        case "Notes":
            return "Summarized the open note into useful next steps."
        case "Mail":
            return "Triaged the Gmail inbox: what to act on, what to ignore, and what is safe to delete."
        case "Calendar":
            return "Briefed Google Calendar: next event, what matters today, conflicts, and free time."
        case "Weather":
            return "Read the Open-Meteo forecast and suggested what to wear."
        case "Maps":
            return "Briefed a Google Maps place and route with leave-by guidance from Token Factory."
        case "Agent":
            return "Planned from Mail, Calendar, Notes, Weather, and Maps using Nebius Token Factory."
        default:
            return "Summarized the open page into a short action list."
        }
    }
}

private struct ClipIfNeeded: ViewModifier {
    let enabled: Bool

    func body(content: Content) -> some View {
        Group {
            if enabled {
                content.clipped()
            } else {
                content
            }
        }
    }
}

private struct AIActivityEvent: Identifiable {
    let id = UUID()
    let title: String
    let detail: String
    let symbol: String
}

private struct AutopilotMailDraft: Equatable {
    let id: String
    let to: String
    let subject: String
    let body: String
}

private struct AutopilotActionEvent: Identifiable {
    let id = UUID()
    var title: String
    var detail: String
    var symbol: String
    var draft: AutopilotMailDraft? = nil
    var didSend = false
}

#Preview {
    HomeScreenPrototypeView()
}
