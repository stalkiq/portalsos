import Foundation

enum NebiusServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyContent
    case timedOut
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing NEBIUS_API_KEY."
        case .invalidResponse:
            return "Nebius returned an invalid response."
        case .emptyContent:
            return "Nebius returned an empty reply."
        case .timedOut:
            return "The request timed out."
        case .serverMessage(let message):
            return message
        }
    }
}

struct AutopilotActionPayload {
    let title: String
    let detail: String
    let symbol: String
}

struct MailChatIntent {
    enum Action: String {
        case insight
        case sendEmail = "send_email"
        case saveNote = "save_note"
    }

    var action: Action
    var message: String
    var to: String?
    var subject: String?
    var body: String?
    var noteTitle: String?
    var noteBody: String?
    var matchSender: String?
    var matchSubject: String?
}

struct CalendarBrief {
    var hero: String
    var detail: String
    var nextLabel: String
    var nextDetail: String
    var riskLabel: String
    var riskDetail: String
    var freeLabel: String
    var freeDetail: String
    var bufferTitle: String?
    var bufferStart: String?
    var bufferEnd: String?

    var canAddBuffer: Bool {
        bufferTitle != nil && bufferStart != nil
    }

    /// True when there is a real conflict or tight connection to watch.
    var hasRisk: Bool {
        let d = riskDetail.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if d.isEmpty { return false }
        if d == "no conflicts" || d == "none" || d == "clear" || d == "all clear" { return false }
        if d.contains("no conflict") || d.contains("nothing tight") || d.contains("no overlap") { return false }
        return true
    }

    var displayRiskLabel: String {
        hasRisk ? (riskLabel.isEmpty ? "Watch" : riskLabel) : "Clear"
    }

    var displayRiskDetail: String {
        hasRisk ? riskDetail : (riskDetail.isEmpty || riskDetail.lowercased().contains("no conflict") ? "Schedule looks open — no overlaps." : riskDetail)
    }

    var noteBody: String {
        var lines = [hero]
        if !detail.isEmpty { lines.append(detail) }
        lines.append("Next: \(nextDetail)")
        lines.append("\(displayRiskLabel): \(displayRiskDetail)")
        lines.append("Free: \(freeDetail)")
        return lines.filter { !$0.isEmpty }.joined(separator: "\n")
    }
}

struct CalendarChatIntent {
    enum Action: String {
        case insight
        case createEvent = "create_event"
        case saveNote = "save_note"
    }

    var action: Action
    var message: String
    var title: String?
    var start: String?
    var end: String?
    var location: String?
    var noteTitle: String?
    var noteBody: String?
}

struct AutopilotWatchIntent {
    enum Action: String {
        case idle
        case draft
        case note
    }

    var action: Action
    var summary: String
    var reason: String?
    var messageId: String?
    var matchSender: String?
    var matchSubject: String?
    var noteTitle: String?
    var noteBody: String?
    var draftInstruction: String?
}

struct NebiusService {
    private let defaultTextModels = [
        "nvidia/Nemotron-3_5-Lightning",
        "nvidia/NVIDIA-Nemotron-3-Nano-30B-A3B"
    ]
    private let defaultVisionModels = [
        "nvidia/Nemotron-3-Nano-Omni",
        "Qwen/Qwen2.5-VL-72B-Instruct"
    ]
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 90
        configuration.timeoutIntervalForResource = 120
        configuration.waitsForConnectivity = true
        return URLSession(configuration: configuration)
    }()

    func generateInsight(
        for appName: String?,
        contextHint: String?,
        userPrompt: String?,
        imageJPEG: Data? = nil,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        if imageJPEG == nil, onPartial == nil, let backend = backendURL(path: "/v1/insight") {
            let body = BackendInsightRequest(appName: appName, contextHint: contextHint, userPrompt: userPrompt, mode: "insight")
            let data = try await postJSON(to: backend, body: body, requiresDirectKey: false)
            let decoded = try JSONDecoder().decode(BackendInsightResponse.self, from: data)
            guard let text = decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw NebiusServiceError.emptyContent
            }
            return text
        }

        let user = userMessage(
            appName: appName,
            contextHint: contextHint,
            userPrompt: userPrompt,
            limit: (appName == "Mail" || appName == "Calendar") ? 8000 : 4500
        )
        if let imageJPEG {
            return try await completeVisionChat(
                system: """
                You are PortalOS Camera Insight running on Nebius Token Factory vision models (NVIDIA Nemotron-3-Nano-Omni and Qwen2.5-VL).
                Read the photo like a person holding a phone up to the world.
                - Sign or label: transcribe every readable word.
                - Receipt: merchant, date, totals, and line items you can see.
                - Whiteboard or handwriting: transcribe it and list action items.
                - Product: name, brand, visible price/specs, and one useful next step.
                Lead with the extracted text. Then give 1-2 practical next actions. Keep the whole reply under 8 short sentences.
                Never write a thinking process.
                """,
                user: user,
                imageJPEG: imageJPEG,
                maxTokens: 320
            )
        }

        let system: String
        if appName == "Mail" {
            system = """
            You are PortalOS Mail Insight. You triage the live Gmail inbox on this phone.
            Use only the inbox list you were given. Never invent senders or subjects.
            Default job: a phone-sized inbox briefing. If the user asked about one email, lead with that, then still triage the rest.

            Reply with exactly these headings:

            INBOX
            One sentence: count, unread, overall temperature.

            ACT ON
            2-4 emails that need a human now (reply, pay, confirm, deadline). Sender, subject, why.

            NOISE
            Mail that can wait: newsletters, FYIs, automated updates.

            DELETE
            Safe trash recommendations only: promos, leftover receipts, duplicate alerts, obvious junk. Sender, subject, why. If nothing is safe to delete, say so. Never claim you deleted anything.

            Short bullets. No thinking process. No recap of the prompt.
            Never include Gmail ids, id=, hex ids, or parentheses full of message ids. Refer to mail by sender and subject only.
            """
        } else if appName == "Calendar" {
            system = """
            You are PortalOS Calendar Insight on Nebius Token Factory (NVIDIA Nemotron).
            Use only the Google Calendar events you were given. Never invent meetings.
            Lead with what is next, then what matters today, then real conflicts only.
            Plain English. No event ids. 3-6 short sentences. No thinking process.
            """
        } else if appName == "Weather" {
            system = """
            You are PortalOS Weather Insight on Nebius Token Factory (NVIDIA Nemotron).
            Use only the Open-Meteo forecast you were given. Do not invent temperatures.
            Give a phone-sized brief: what it feels like now, what to wear, umbrella or not, and the one day that changes plans.
            3-6 short sentences. No thinking process. No recap of the prompt.
            """
        } else if appName == "Maps" {
            system = """
            You are PortalOS Maps Insight on Nebius Token Factory (NVIDIA Nemotron).
            Use only the Google Places / Routes context you were given. Never invent places, ETAs, or addresses.
            Give a phone-sized trip brief: where they are going, leave-by time if ETA is known, Drive vs Walk tradeoffs, and one watch-out (traffic, walking safety, tight connection).
            If weather context is present, factor it in briefly. 3-6 short sentences. No thinking process. No place ids.
            """
        } else {
            system = """
            You are PortalOS Insight, a phone assistant.
            Reply in 2-4 short sentences the user can act on. Start with the takeaway.
            Never write a thinking process. Never analyze App context, System context, or User request.
            """
        }

        return try await completeChat(
            system: system,
            user: user + "\n/no_think",
            maxTokens: (appName == "Mail" || appName == "Calendar") ? 420 : ((appName == "Weather" || appName == "Maps") ? 220 : 160),
            onPartial: onPartial
        )
    }

    func generateCalendarBrief(contextHint: String?, userPrompt: String?) async throws -> CalendarBrief {
        let system = """
        You are PortalOS Calendar Insight on Nebius Token Factory (NVIDIA Nemotron).
        Brief a phone home screen. Use only the events you were given. Never invent meetings or flights.

        Priority order (do not skip #1):
        1) What is next — the SOONEST EVENT, in plain language a human would say aloud.
        2) What the rest of today/tomorrow looks like — meetings, travel, deadlines that matter.
        3) Only then mention a flight layover if one exists (as supporting detail, not the headline unless travel is the whole day).

        Bad briefs (never do these):
        - Hero is only a layover like "Charlotte then Fort Myers, 2h50 layover" when a meeting is sooner.
        - Awkward phrasing like "Pro between Slashy and Al" — say "Pro with Slashy and Al Moreau at 11:00 AM".
        - Treating empty multi-day gaps as risk. Treating a normal 2–4h layover as crisis.
        - Putting "No conflicts" under a Risk label without making riskLabel "Clear".

        Field rules:
        - hero: max 8 words. Day takeaway first (example: "Meeting at 11, then fly south"). If the day is travel-only, a trip headline is OK.
        - detail: 1–2 short sentences, chronological, useful. Include times.
        - nextDetail: MUST describe SOONEST EVENT with title + time (+ who/where if known). Plain English.
        - nextLabel: "Next"
        - riskDetail: only real OVERLAP or flight connection under 75 minutes. Otherwise "No conflicts".
        - riskLabel: "Watch" if riskDetail is a real problem, else "Clear".
        - freeDetail: one concrete open block (e.g. "Tonight after 8 PM" or "Tue morning before 11"). Never empty.
        - freeLabel: "Free"
        - bufferTitle/start/end: only when risk is a real tight connection/overlap; else leave empty.

        Reply with ONLY compact JSON:
        {"hero":"","detail":"","nextLabel":"Next","nextDetail":"","riskLabel":"Clear","riskDetail":"No conflicts","freeLabel":"Free","freeDetail":"","bufferTitle":"","bufferStart":"","bufferEnd":""}
        Never write a thinking process. Never wrap JSON in markdown. Never include event ids.
        """
        let user = userMessage(
            appName: "Calendar",
            contextHint: contextHint,
            userPrompt: userPrompt ?? "Brief my calendar for the phone: what is next, what matters today, any real conflicts, and when I am free.",
            limit: 12000
        ) + "\n/no_think"
        let raw = try await completeChat(system: system, user: user, maxTokens: 380)
        return Self.parseCalendarBrief(from: raw)
    }

    func interpretCalendarChat(contextHint: String?, userPrompt: String) async throws -> CalendarChatIntent {
        let system = """
        You are PortalOS Calendar actions on Nebius Token Factory.
        Read the live Google Calendar and the user's request. Choose exactly one action.
        - insight: answer only. Use for questions like where they are going, what is next, or what a gap means.
        - create_event: the user asked to add, schedule, create, or put something on the calendar — including "add an event", "a flight to X", or a date like "the 12th". Fill title and start. start MUST be ISO-8601 local YYYY-MM-DDTHH:MM:SS. If they omit a clock time, pick a free slot that day that does not OVERLAP existing events (use COMPUTED GAPS). Default duration 2 hours for flights, 1 hour otherwise. end optional. location optional (city or airport). Never invent a meeting that already exists unless they asked to copy it.
        - save_note: the user asked to save the agenda to Notes.

        For create_event, message MUST confirm what you added: title, date, and time. Example: "Added Flight to Miami on Sep 12 at 10:00 AM."
        Reply with ONLY compact JSON:
        {"action":"insight","message":"...","title":"","start":"","end":"","location":"","noteTitle":"","noteBody":""}
        Never write a thinking process. Never wrap the JSON in markdown.
        Never answer a create request with a layover recap. That is the wrong action.
        """
        let user = userMessage(
            appName: "Calendar",
            contextHint: contextHint,
            userPrompt: userPrompt,
            limit: 12000
        ) + "\n/no_think"
        let raw = try await completeChat(system: system, user: user, maxTokens: 420)
        return Self.parseCalendarIntent(from: raw)
    }

    func interpretMailChat(contextHint: String?, userPrompt: String) async throws -> MailChatIntent {
        let system = """
        You are PortalOS Mail actions on Nebius Token Factory.
        Read the live inbox and the user's request. Choose exactly one action.
        - insight: answer only. Use for triage, questions, and when a recipient is unclear.
        - send_email: the user asked you to send, reply, or email someone. Fill to, subject, body. to MUST be a real address from the inbox or the user request. Never invent an address.
        - save_note: the user asked to save, copy, or send email details to Notes. Fill noteTitle and noteBody with the real sender, subject, and the important points.

        Reply with ONLY compact JSON:
        {"action":"insight","message":"...","to":"","subject":"","body":"","noteTitle":"","noteBody":"","matchSender":"","matchSubject":""}
        message is the short chat reply shown on the phone.
        matchSender/matchSubject identify which inbox thread to reply to when sending.
        Never write a thinking process. Never wrap the JSON in markdown.
        """
        let user = userMessage(
            appName: "Mail",
            contextHint: contextHint,
            userPrompt: userPrompt,
            limit: 8000
        ) + "\n/no_think"
        let raw = try await completeChat(system: system, user: user, maxTokens: 520)
        return Self.parseMailIntent(from: raw)
    }

    func generateAgentPlan(horizon: AgentPlanHorizon, contextHint: String?, userPrompt: String?) async throws -> String {
        let system = """
        You are the PortalOS Agent living in Agent Channel on Nebius Token Factory (NVIDIA Nemotron).
        You help the user run their life using live phone context: Mail, Calendar, Notes, Weather, and Maps.
        Horizon: \(horizon.title).

        Write a practical plan a busy person can use:
        - Lead with the 3–5 most important moves for this \(horizon.title.lowercased()).
        - Use real senders, subjects, event titles, and times from context. Never invent them.
        - If a source is missing, say what you need (e.g. sign into Calendar) instead of guessing.
        - Include Focus / Commitments / Watch-outs / Free capacity when useful.
        - Keep it phone-sized: short bullets, no essay, no thinking process, no message ids.

        For Year: stay high-level (themes and seasons). For Week: be concrete with days/times when known.
        """
        let user = userMessage(
            appName: "Agent",
            contextHint: contextHint,
            userPrompt: userPrompt ?? horizon.prompt,
            limit: 14000
        ) + "\n/no_think"
        return try await completeChat(system: system, user: user, maxTokens: 700)
    }

    func agentChannelReply(contextHint: String?, history: String?, userPrompt: String) async throws -> String {
        let system = """
        You are the PortalOS Agent in Agent Channel on Nebius Token Factory (NVIDIA Nemotron).
        Answer using Mail, Calendar, Notes, Weather, and Maps context. Be concrete and actionable.
        If the user asks about week/month/year, shape the answer to that horizon.
        Never invent inbox or calendar items. No thinking process. No message ids. Keep replies under ~12 short sentences or tight bullets.
        """
        var hint = contextHint ?? ""
        if let history, !history.isEmpty {
            hint += "\n\nRecent Agent Channel chat:\n\(history)"
        }
        let user = userMessage(
            appName: "Agent",
            contextHint: hint,
            userPrompt: userPrompt,
            limit: 14000
        ) + "\n/no_think"
        return try await completeChat(system: system, user: user, maxTokens: 520)
    }

    func generateAutopilotAction() async throws -> AutopilotActionPayload {
        if let backend = backendURL(path: "/v1/autopilot") {
            let data = try await postJSON(to: backend, body: BackendInsightRequest(appName: nil, contextHint: nil, userPrompt: nil, mode: "autopilot"), requiresDirectKey: false)
            let decoded = try JSONDecoder().decode(BackendAutopilotResponse.self, from: data)
            return AutopilotActionPayload(
                title: decoded.title ?? "Autopilot update",
                detail: decoded.detail ?? "Nebius completed a background action.",
                symbol: decoded.symbol ?? "bolt.fill"
            )
        }

        let raw = try await completeChat(
            system: "You are PortalOS Autopilot. Invent one plausible autonomous action the OS just completed in Browser, Camera, Notes, or Mail. Reply with ONLY compact JSON: {\"title\":\"...\",\"detail\":\"...\",\"symbol\":\"safari.fill\"}. symbol must be safari.fill, camera.fill, note.text, or envelope.fill.",
            user: "Generate the next live Autopilot action now.",
            maxTokens: 80
        )
        return parseAutopilot(from: raw)
    }

    func watchInbox(contextHint: String?, skipDraftIDs: [String], skipNoteIDs: [String]) async throws -> AutopilotWatchIntent {
        let system = """
        You are PortalOS Autopilot watching a live Gmail inbox.
        Choose exactly one action for this cycle. Use only senders, subjects, and ids from the inbox. Never invent mail.
        - draft: one unread personal/important message that needs a human reply. Not promo, social, or newsletters.
        - note: one important FYI worth keeping (deadline, recruiting, money, confirmation) that is not a reply you should draft this cycle.
        - idle: nothing new, only noise, or every candidate is in the skip lists.

        Reply with ONLY compact JSON:
        {"action":"idle","summary":"...","reason":"","messageId":"","matchSender":"","matchSubject":"","noteTitle":"","noteBody":"","draftInstruction":""}
        messageId must copy an id= value from the inbox when action is draft or note.
        draftInstruction is a short direction for the reply. noteBody is the note to save.
        summary is one sentence for the Autopilot card.
        Never write a thinking process. Never wrap JSON in markdown.
        """
        var extra = "Autopilot skip lists:\n"
        extra += "Already drafted (do not draft again): \(skipDraftIDs.isEmpty ? "none" : skipDraftIDs.joined(separator: ", "))\n"
        extra += "Already saved to Notes (do not save again): \(skipNoteIDs.isEmpty ? "none" : skipNoteIDs.joined(separator: ", "))\n"
        extra += "Prefer UNREAD. One action only."
        let user = userMessage(
            appName: "Mail",
            contextHint: [contextHint, extra].compactMap { $0 }.joined(separator: "\n"),
            userPrompt: "Watch the inbox and pick the next real Autopilot action.",
            limit: 8000
        ) + "\n/no_think"
        let raw = try await completeChat(system: system, user: user, maxTokens: 420)
        return Self.parseWatchIntent(from: raw)
    }

    func generateMailDraft(
        to: String,
        subject: String,
        originalBody: String?,
        instruction: String?,
        isReply: Bool,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        let system = """
        You are PortalOS Mail writing with NVIDIA Nemotron on Nebius Token Factory.
        Write a complete email body the user can send.
        Output only the email body. No subject line, no greeting labels, no thinking process, no markdown fences.
        Keep it concise and natural. 1-3 short paragraphs.
        """
        var user = isReply ? "Write a reply.\n" : "Write a new email.\n"
        user += "To: \(to)\nSubject: \(subject)\n"
        if let originalBody, !originalBody.isEmpty {
            user += "Incoming email:\n\(String(originalBody.prefix(1800)))\n"
        }
        if let instruction, !instruction.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            user += "User direction: \(instruction)\n"
        } else {
            user += "User direction: Write a clear, polite email.\n"
        }
        user += "/no_think"
        return try await completeChat(system: system, user: user, maxTokens: 280, onPartial: onPartial)
    }

    private func completeChat(
        system: String,
        user: String,
        maxTokens: Int,
        onPartial: (@MainActor (String) -> Void)? = nil
    ) async throws -> String {
        let apiKey = resolvedAPIKey()
        guard !apiKey.isEmpty else {
            throw NebiusServiceError.missingAPIKey
        }

        var lastError: Error = NebiusServiceError.invalidResponse
        for model in resolvedTextModels() {
            let body = NebiusChatRequest(
                model: model,
                temperature: 0.3,
                maxTokens: maxTokens,
                stream: onPartial != nil,
                messages: [
                    .init(role: "system", content: .text(system)),
                    .init(role: "user", content: .text(user))
                ]
            )
            do {
                if let onPartial {
                    return try await sendChatStream(body, onPartial: onPartial)
                }
                return try await sendChat(body)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func completeVisionChat(system: String, user: String, imageJPEG: Data, maxTokens: Int) async throws -> String {
        let apiKey = resolvedAPIKey()
        guard !apiKey.isEmpty else {
            throw NebiusServiceError.missingAPIKey
        }

        let dataURL = "data:image/jpeg;base64,\(imageJPEG.base64EncodedString())"
        var lastError: Error = NebiusServiceError.invalidResponse
        for model in resolvedVisionModels() {
            let body = NebiusChatRequest(
                model: model,
                temperature: 0.2,
                maxTokens: maxTokens,
                stream: false,
                messages: [
                    .init(role: "system", content: .text(system)),
                    .init(
                        role: "user",
                        content: .parts([
                            .init(type: "text", text: user, imageURL: nil),
                            .init(type: "image_url", text: nil, imageURL: .init(url: dataURL))
                        ])
                    )
                ]
            )
            do {
                return try await sendChat(body)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    private func sendChat(_ body: NebiusChatRequest) async throws -> String {
        let apiKey = resolvedAPIKey()
        guard !apiKey.isEmpty else {
            throw NebiusServiceError.missingAPIKey
        }

        var request = URLRequest(url: tokenFactoryURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        var lastError: Error = NebiusServiceError.invalidResponse
        for attempt in 1...2 {
            do {
                let (data, response) = try await Self.session.data(for: request)
                try validate(response: response, data: data)
                let decoded = try JSONDecoder().decode(NebiusChatResponse.self, from: data)
                let text = Self.visibleText(decoded.choices.first?.message.content ?? "")
                guard !text.isEmpty else {
                    throw NebiusServiceError.emptyContent
                }
                return text
            } catch {
                lastError = error
                if attempt == 1, Self.isTimeout(error) {
                    continue
                }
                throw Self.mapped(error)
            }
        }
        throw Self.mapped(lastError)
    }

    private func sendChatStream(
        _ body: NebiusChatRequest,
        onPartial: @MainActor (String) -> Void
    ) async throws -> String {
        let apiKey = resolvedAPIKey()
        guard !apiKey.isEmpty else {
            throw NebiusServiceError.missingAPIKey
        }

        var request = URLRequest(url: tokenFactoryURL())
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (bytes, response) = try await Self.session.bytes(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw NebiusServiceError.invalidResponse
        }
        if !(200...299).contains(http.statusCode) {
            var data = Data()
            for try await chunk in bytes {
                data.append(contentsOf: [chunk])
            }
            if let message = decodedError(from: data) {
                throw NebiusServiceError.serverMessage(message)
            }
            throw NebiusServiceError.invalidResponse
        }

        var assembled = ""
        for try await line in bytes.lines {
            let payload: String
            if line.hasPrefix("data: ") {
                payload = String(line.dropFirst(6))
            } else if line.hasPrefix("data:") {
                payload = String(line.dropFirst(5)).trimmingCharacters(in: .whitespaces)
            } else {
                continue
            }
            if payload == "[DONE]" {
                break
            }
            guard let chunkData = payload.data(using: .utf8),
                  let chunk = try? JSONDecoder().decode(NebiusStreamChunk.self, from: chunkData) else {
                continue
            }
            if let message = chunk.error?.message, !message.isEmpty {
                throw NebiusServiceError.serverMessage(message)
            }
            if let delta = chunk.choices.first?.delta?.content, !delta.isEmpty {
                assembled += delta
                let visible = Self.visibleText(assembled)
                if !visible.isEmpty {
                    await onPartial(visible)
                }
            }
        }

        let visible = Self.visibleText(assembled)
        guard !visible.isEmpty else {
            throw NebiusServiceError.emptyContent
        }
        await onPartial(visible)
        return visible
    }

    private func postJSON<T: Encodable>(to url: URL, body: T, requiresDirectKey: Bool) async throws -> Data {
        if requiresDirectKey {
            let apiKey = resolvedAPIKey()
            guard !apiKey.isEmpty else {
                throw NebiusServiceError.missingAPIKey
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        do {
            let (data, response) = try await Self.session.data(for: request)
            try validate(response: response, data: data)
            return data
        } catch {
            throw Self.mapped(error)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw NebiusServiceError.invalidResponse
        }
        guard (200...299).contains(http.statusCode) else {
            if let message = decodedError(from: data) {
                throw NebiusServiceError.serverMessage(message)
            }
            throw NebiusServiceError.invalidResponse
        }
    }

    private func backendURL(path: String) -> URL? {
        let raw = ProcessInfo.processInfo.environment["PORTALS_API_BASE_URL"]
            ?? (Bundle.main.object(forInfoDictionaryKey: "PORTALS_API_BASE_URL") as? String)
            ?? ""
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "/")) + path)
    }

    private func resolvedAPIKey() -> String {
        let candidates = [
            NebiusLocalSecrets.apiKey,
            ProcessInfo.processInfo.environment["NEBIUS_API_KEY"],
            Bundle.main.object(forInfoDictionaryKey: "NEBIUS_API_KEY") as? String,
            bundledSecret()
        ]
        for candidate in candidates {
            let trimmed = candidate?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            guard !trimmed.isEmpty, !trimmed.hasPrefix("$(") else { continue }
            return trimmed
        }
        return ""
    }

    private func bundledSecret() -> String? {
        guard let url = Bundle.main.url(forResource: "NebiusSecrets", withExtension: "plist"),
              let values = NSDictionary(contentsOf: url),
              let key = values["NEBIUS_API_KEY"] as? String else {
            return nil
        }
        return key
    }

    private func resolvedTextModels() -> [String] {
        var models: [String] = []
        if let envModel = ProcessInfo.processInfo.environment["NEBIUS_MODEL"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envModel.isEmpty {
            models.append(envModel)
        }
        for model in defaultTextModels where !models.contains(model) {
            models.append(model)
        }
        return models
    }

    private func resolvedVisionModels() -> [String] {
        var models: [String] = []
        if let envModel = ProcessInfo.processInfo.environment["NEBIUS_VISION_MODEL"], !envModel.isEmpty {
            models.append(envModel)
        }
        for model in defaultVisionModels where !models.contains(model) {
            models.append(model)
        }
        return models
    }

    private func resolvedProjectID() -> String? {
        if let envProject = ProcessInfo.processInfo.environment["NEBIUS_AI_PROJECT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines),
           !envProject.isEmpty {
            return envProject
        }
        return nil
    }

    private func tokenFactoryURL() -> URL {
        var components = URLComponents(string: "https://api.tokenfactory.nebius.com/v1/chat/completions")!
        if let projectID = resolvedProjectID() {
            components.queryItems = [
                URLQueryItem(name: "ai_project_id", value: projectID)
            ]
        }
        return components.url!
    }

    private func userMessage(appName: String?, contextHint: String?, userPrompt: String?, limit: Int = 4500) -> String {
        var prompt = ""
        if let appName, !appName.isEmpty {
            prompt += "Open app: \(appName).\n"
        }
        if let contextHint, !contextHint.isEmpty {
            prompt += "What is on screen:\n\(contextHint)\n"
        }
        if let userPrompt, !userPrompt.isEmpty {
            prompt += "The user wants: \(userPrompt)\n"
        }
        prompt += "Write the user-facing insight now. Do not analyze this prompt."
        if prompt.count > limit {
            return String(prompt.prefix(limit))
        }
        return prompt
    }

    private func parseAutopilot(from text: String) -> AutopilotActionPayload {
        if let data = text.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(BackendAutopilotResponse.self, from: data) {
            return AutopilotActionPayload(
                title: decoded.title ?? "Autopilot update",
                detail: decoded.detail ?? text,
                symbol: decoded.symbol ?? "bolt.fill"
            )
        }
        if let start = text.firstIndex(of: "{"),
           let end = text.lastIndex(of: "}"),
           let data = String(text[start...end]).data(using: .utf8),
           let decoded = try? JSONDecoder().decode(BackendAutopilotResponse.self, from: data) {
            return AutopilotActionPayload(
                title: decoded.title ?? "Autopilot update",
                detail: decoded.detail ?? text,
                symbol: decoded.symbol ?? "bolt.fill"
            )
        }
        return AutopilotActionPayload(title: "Autopilot update", detail: text, symbol: "bolt.fill")
    }

    private static func parseWatchIntent(from text: String) -> AutopilotWatchIntent {
        let payload = decodeWatchIntent(from: text)
        let action = AutopilotWatchIntent.Action(rawValue: payload?.action ?? "") ?? .idle
        let summary = (payload?.summary ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return AutopilotWatchIntent(
            action: action,
            summary: summary.isEmpty ? "Watching inbox." : summary,
            reason: emptyToNil(payload?.reason),
            messageId: emptyToNil(payload?.messageId),
            matchSender: emptyToNil(payload?.matchSender),
            matchSubject: emptyToNil(payload?.matchSubject),
            noteTitle: emptyToNil(payload?.noteTitle),
            noteBody: emptyToNil(payload?.noteBody),
            draftInstruction: emptyToNil(payload?.draftInstruction)
        )
    }

    private static func decodeWatchIntent(from text: String) -> AutopilotWatchDTO? {
        let candidates = [text, jsonObject(in: text)].compactMap { $0 }
        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(AutopilotWatchDTO.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    private static func parseCalendarBrief(from text: String) -> CalendarBrief {
        let payload = decodeCalendarBrief(from: text)
        let hero = (payload?.hero ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        var brief = CalendarBrief(
            hero: hero.isEmpty ? visibleText(text) : hero,
            detail: emptyToNil(payload?.detail) ?? "",
            nextLabel: emptyToNil(payload?.nextLabel) ?? "Next",
            nextDetail: emptyToNil(payload?.nextDetail) ?? "",
            riskLabel: emptyToNil(payload?.riskLabel) ?? "Risk",
            riskDetail: emptyToNil(payload?.riskDetail) ?? "",
            freeLabel: emptyToNil(payload?.freeLabel) ?? "Free",
            freeDetail: emptyToNil(payload?.freeDetail) ?? "",
            bufferTitle: emptyToNil(payload?.bufferTitle),
            bufferStart: emptyToNil(payload?.bufferStart),
            bufferEnd: emptyToNil(payload?.bufferEnd)
        )
        // Normalize confusing "Risk: No conflicts" into Clear.
        if !brief.hasRisk {
            brief.riskLabel = "Clear"
            if brief.riskDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || brief.riskDetail.lowercased().contains("no conflict") {
                brief.riskDetail = "No overlaps or tight connections."
            }
            brief.bufferTitle = nil
            brief.bufferStart = nil
            brief.bufferEnd = nil
        } else if brief.riskLabel.lowercased() == "risk" || brief.riskLabel.isEmpty {
            brief.riskLabel = "Watch"
        }
        if brief.freeDetail.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            brief.freeDetail = "Check open gaps between events."
        }
        return brief
    }

    private static func decodeCalendarBrief(from text: String) -> CalendarBriefDTO? {
        let candidates = [text, jsonObject(in: text)].compactMap { $0 }
        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(CalendarBriefDTO.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    private static func parseCalendarIntent(from text: String) -> CalendarChatIntent {
        let payload = decodeCalendarIntent(from: text)
        let action = CalendarChatIntent.Action(rawValue: payload?.action ?? "") ?? .insight
        let message = (payload?.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return CalendarChatIntent(
            action: action,
            message: message.isEmpty ? visibleText(text) : message,
            title: emptyToNil(payload?.title),
            start: emptyToNil(payload?.start),
            end: emptyToNil(payload?.end),
            location: emptyToNil(payload?.location),
            noteTitle: emptyToNil(payload?.noteTitle),
            noteBody: emptyToNil(payload?.noteBody)
        )
    }

    private static func decodeCalendarIntent(from text: String) -> CalendarChatIntentDTO? {
        let candidates = [text, jsonObject(in: text)].compactMap { $0 }
        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(CalendarChatIntentDTO.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    private static func parseMailIntent(from text: String) -> MailChatIntent {
        let payload = decodeMailIntent(from: text)
        let action = MailChatIntent.Action(rawValue: payload?.action ?? "") ?? .insight
        let message = (payload?.message ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        return MailChatIntent(
            action: action,
            message: message.isEmpty ? visibleText(text) : message,
            to: emptyToNil(payload?.to),
            subject: emptyToNil(payload?.subject),
            body: emptyToNil(payload?.body),
            noteTitle: emptyToNil(payload?.noteTitle),
            noteBody: emptyToNil(payload?.noteBody),
            matchSender: emptyToNil(payload?.matchSender),
            matchSubject: emptyToNil(payload?.matchSubject)
        )
    }

    private static func decodeMailIntent(from text: String) -> MailChatIntentDTO? {
        let candidates = [text, jsonObject(in: text)].compactMap { $0 }
        for candidate in candidates {
            if let data = candidate.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(MailChatIntentDTO.self, from: data) {
                return decoded
            }
        }
        return nil
    }

    private static func jsonObject(in text: String) -> String? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            return nil
        }
        return String(text[start...end])
    }

    private static func emptyToNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func isTimeout(_ error: Error) -> Bool {
        if (error as? URLError)?.code == .timedOut {
            return true
        }
        if (error as NSError).code == NSURLErrorTimedOut {
            return true
        }
        return false
    }

    private static func mapped(_ error: Error) -> Error {
        if isTimeout(error) {
            return NebiusServiceError.timedOut
        }
        return error
    }

    private static func visibleText(_ raw: String) -> String {
        var text = raw
        text = text.replacingOccurrences(of: "(?is)<think>.*?</think>", with: "", options: .regularExpression)
        text = text.replacingOccurrences(of: "(?is)<reasoning>.*?</reasoning>", with: "", options: .regularExpression)
        if let range = text.range(of: "<think>", options: .caseInsensitive)
            ?? text.range(of: "<reasoning>", options: .caseInsensitive) {
            text = String(text[..<range.lowerBound])
        }

        let answerMarkers = [
            "Final answer:",
            "Final Answer:",
            "**Final answer:**",
            "Insight:",
            "User-facing insight:"
        ]
        for marker in answerMarkers {
            if let range = text.range(of: marker, options: .caseInsensitive) {
                text = String(text[range.upperBound...])
                break
            }
        }

        if looksLikeThinking(text) {
            text = stripThinkingProse(text)
        }

        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeThinking(_ text: String) -> Bool {
        let lowered = text.lowercased()
        return lowered.contains("thinking process")
            || lowered.contains("analyze user input")
            || lowered.contains("**app context:**")
            || lowered.contains("**system context:**")
    }

    private static func stripThinkingProse(_ raw: String) -> String {
        let skipped = [
            "here's a thinking process",
            "here is a thinking process",
            "thinking process",
            "analyze user input",
            "app context:",
            "system context:",
            "selected message:",
            "recent inbox:",
            "user request:"
        ]
        let kept = raw.components(separatedBy: .newlines).compactMap { line -> String? in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { return nil }
            let lowered = trimmed.lowercased().replacingOccurrences(of: "*", with: "")
            if skipped.contains(where: { lowered.contains($0) }) {
                return nil
            }
            if lowered.hasPrefix("1.") || lowered.hasPrefix("- ") || lowered.hasPrefix("* ") {
                return nil
            }
            return trimmed
        }
        return kept.joined(separator: " ")
    }

    private func decodedError(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(NebiusErrorResponse.self, from: data),
           let message = payload.error?.message, !message.isEmpty {
            return message
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct AutopilotWatchDTO: Decodable {
    let action: String?
    let summary: String?
    let reason: String?
    let messageId: String?
    let matchSender: String?
    let matchSubject: String?
    let noteTitle: String?
    let noteBody: String?
    let draftInstruction: String?
}

private struct CalendarBriefDTO: Decodable {
    let hero: String?
    let detail: String?
    let nextLabel: String?
    let nextDetail: String?
    let riskLabel: String?
    let riskDetail: String?
    let freeLabel: String?
    let freeDetail: String?
    let bufferTitle: String?
    let bufferStart: String?
    let bufferEnd: String?
}

private struct CalendarChatIntentDTO: Decodable {
    let action: String?
    let message: String?
    let title: String?
    let start: String?
    let end: String?
    let location: String?
    let noteTitle: String?
    let noteBody: String?
}

private struct MailChatIntentDTO: Decodable {
    let action: String?
    let message: String?
    let to: String?
    let subject: String?
    let body: String?
    let noteTitle: String?
    let noteBody: String?
    let matchSender: String?
    let matchSubject: String?
}

private struct BackendInsightRequest: Encodable {
    let appName: String?
    let contextHint: String?
    let userPrompt: String?
    let mode: String
}

private struct BackendInsightResponse: Decodable {
    let text: String?
}

private struct BackendAutopilotResponse: Decodable {
    let title: String?
    let detail: String?
    let symbol: String?
}

private struct NebiusChatRequest: Encodable {
    let model: String
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    let messages: [NebiusOutgoingMessage]
    let chatTemplateKwargs: ChatTemplateKwargs

    init(model: String, temperature: Double, maxTokens: Int, stream: Bool, messages: [NebiusOutgoingMessage]) {
        self.model = model
        self.temperature = temperature
        self.maxTokens = maxTokens
        self.stream = stream
        self.messages = messages
        self.chatTemplateKwargs = ChatTemplateKwargs(enableThinking: false)
    }

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case maxTokens = "max_tokens"
        case stream
        case messages
        case chatTemplateKwargs = "chat_template_kwargs"
    }
}

private struct ChatTemplateKwargs: Encodable {
    let enableThinking: Bool

    enum CodingKeys: String, CodingKey {
        case enableThinking = "enable_thinking"
    }
}

private struct NebiusOutgoingMessage: Encodable {
    let role: String
    let content: Content

    enum Content: Encodable {
        case text(String)
        case parts([NebiusContentPart])

        func encode(to encoder: Encoder) throws {
            var container = encoder.singleValueContainer()
            switch self {
            case .text(let text):
                try container.encode(text)
            case .parts(let parts):
                try container.encode(parts)
            }
        }
    }
}

private struct NebiusContentPart: Encodable {
    let type: String
    let text: String?
    let imageURL: ImageURLPayload?

    enum CodingKeys: String, CodingKey {
        case type
        case text
        case imageURL = "image_url"
    }
}

private struct ImageURLPayload: Encodable {
    let url: String
}

private struct NebiusMessage: Decodable {
    let role: String
    let content: String?
}

private struct NebiusChatResponse: Decodable {
    let choices: [NebiusChoice]
}

private struct NebiusChoice: Decodable {
    let message: NebiusMessage
}

private struct NebiusStreamChunk: Decodable {
    let choices: [Choice]
    let error: NebiusErrorBody?

    struct Choice: Decodable {
        let delta: Delta?
    }

    struct Delta: Decodable {
        let content: String?
        let reasoningContent: String?

        enum CodingKeys: String, CodingKey {
            case content
            case reasoningContent = "reasoning_content"
        }
    }
}

private struct NebiusErrorResponse: Decodable {
    let error: NebiusErrorBody?
}

private struct NebiusErrorBody: Decodable {
    let message: String?
}
