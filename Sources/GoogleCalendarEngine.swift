import Combine
import Foundation

struct CalendarEventItem: Identifiable, Equatable {
    let id: String
    let title: String
    let start: Date
    let end: Date
    let isAllDay: Bool
    let location: String
    let notes: String
    let htmlLink: String?

    var dayLabel: String {
        if Calendar.current.isDateInToday(start) { return "Today" }
        if Calendar.current.isDateInTomorrow(start) { return "Tomorrow" }
        return start.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
    }

    var timeLabel: String {
        if isAllDay { return "All day" }
        let startText = start.formatted(date: .omitted, time: .shortened)
        let endText = end.formatted(date: .omitted, time: .shortened)
        return "\(startText) – \(endText)"
    }

    var durationLabel: String {
        if isAllDay { return "all day" }
        let minutes = max(Int(end.timeIntervalSince(start) / 60), 0)
        let hours = minutes / 60
        let remain = minutes % 60
        if hours == 0 { return "\(remain) min" }
        if remain == 0 { return "\(hours)h" }
        return "\(hours)h \(remain)m"
    }

    var isLikelyFlight: Bool {
        let blob = "\(title) \(location) \(notes)".lowercased()
        if blob.contains("flight") || blob.contains("depart") || blob.contains("arrival")
            || blob.contains("layover") || blob.contains("connecting") || blob.contains("airport") {
            return true
        }
        let codes = [" aa ", " ua ", " dl ", " wn ", " b6 ", " as ", " nk ", " f9 "]
        let padded = " \(blob) "
        return codes.contains(where: { padded.contains($0) })
    }

    func clockStamp() -> String {
        if isAllDay {
            return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()) + " all day"
        }
        return start.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
            + " → "
            + end.formatted(date: .omitted, time: .shortened)
    }

    var insightLine: String {
        var parts = ["id=\(id)", clockStamp(), "(\(durationLabel))", title]
        if !location.isEmpty { parts.append("loc=\(location)") }
        return parts.joined(separator: " · ")
    }
}

@MainActor
final class GoogleCalendarEngine: ObservableObject {
    @Published var events: [CalendarEventItem] = []
    @Published var selectedID: String?
    @Published var isBusy = false
    @Published var statusText = "Sign in with Google to load Calendar."
    @Published var errorMessage: String?

    private let account: GmailEngine

    init(account: GmailEngine) {
        self.account = account
    }

    var isSignedIn: Bool { account.isSignedIn }
    var email: String { account.email }

    var selectedEvent: CalendarEventItem? {
        events.first(where: { $0.id == selectedID }) ?? events.first
    }

    var insightContext: String? {
        guard isSignedIn else { return nil }
        let accountName = email.isEmpty ? "this Google account" : email
        if events.isEmpty {
            return "Google Calendar is signed in as \(accountName). No events in the next 21 days."
        }
        let zone = TimeZone.current.identifier
        var parts = [
            "Live Google Calendar for \(accountName). Times are in \(zone).",
            "\(events.count) upcoming events."
        ]
        if let soonest = events.first {
            parts.append("SOONEST EVENT (this is Next, copy it): \(soonest.insightLine)")
        }
        let facts = Self.gapFacts(for: Array(events.prefix(30)))
        if !facts.isEmpty {
            parts.append("TIGHT/TRAVEL GAPS only (ignore multi-day empty calendar; those are not a briefing):")
            parts.append(contentsOf: facts)
        } else {
            parts.append("No same-day conflicts or flight connections under 8 hours.")
        }
        parts.append("EVENTS:")
        for (index, item) in events.prefix(30).enumerated() {
            parts.append("\(index + 1). \(item.insightLine)")
            let notes = Self.compactNotes(item.notes, limit: 500)
            if !notes.isEmpty {
                parts.append("   notes: \(notes)")
            }
        }
        return parts.joined(separator: "\n")
    }

    func restoreIfNeeded() async {
        guard isSignedIn, events.isEmpty else { return }
        await refresh()
    }

    func refresh() async {
        guard isSignedIn else { return }
        errorMessage = nil
        isBusy = true
        statusText = "Loading calendar..."
        do {
            events = try await fetchEvents()
            if selectedID == nil {
                selectedID = events.first?.id
            }
            statusText = events.isEmpty
                ? "No events in the next 21 days."
                : "\(events.count) upcoming events."
        } catch {
            errorMessage = friendlyError(error)
            statusText = "Could not load calendar."
        }
        isBusy = false
    }

    func createEvent(title: String, start: Date, end: Date?, location: String?) async throws -> CalendarEventItem {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CalendarEngineError.server("Give the event a title.")
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let access = try await account.googleAccessToken()
        let finish = end ?? start.addingTimeInterval(3600)
        let timeZone = TimeZone.current.identifier
        let payload = EventWritePayload(
            summary: trimmed,
            location: emptyToNil(location),
            start: .dateTime(start, timeZone: timeZone),
            end: .dateTime(finish, timeZone: timeZone)
        )
        var request = URLRequest(url: URL(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        let resource: EventResource = try await decode(request)
        let created = resource.asItem() ?? CalendarEventItem(
            id: resource.id ?? UUID().uuidString,
            title: trimmed,
            start: start,
            end: finish,
            isAllDay: false,
            location: location ?? "",
            notes: "",
            htmlLink: resource.htmlLink
        )
        events = (events + [created]).sorted { $0.start < $1.start }
        selectedID = created.id
        statusText = "Added \(created.title)."
        return created
    }

    private func fetchEvents() async throws -> [CalendarEventItem] {
        let access = try await account.googleAccessToken()
        let now = Date()
        let later = Calendar.current.date(byAdding: .day, value: 21, to: now) ?? now.addingTimeInterval(21 * 86400)
        var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/calendars/primary/events")!
        components.queryItems = [
            URLQueryItem(name: "singleEvents", value: "true"),
            URLQueryItem(name: "orderBy", value: "startTime"),
            URLQueryItem(name: "maxResults", value: "50"),
            URLQueryItem(name: "timeMin", value: Self.rfc3339.string(from: now)),
            URLQueryItem(name: "timeMax", value: Self.rfc3339.string(from: later))
        ]
        guard let url = components.url else { throw CalendarEngineError.invalidResponse }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(access)", forHTTPHeaderField: "Authorization")
        let list: EventListResponse = try await decode(request)
        return (list.items ?? []).compactMap { $0.asItem() }
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 401 {
            throw CalendarEngineError.signedOut
        }
        if status == 403 {
            let message = Self.googleError(from: data)?.lowercased() ?? ""
            if message.contains("has not been used") || message.contains("is disabled") {
                throw CalendarEngineError.apiDisabled
            }
            if message.contains("insufficient") || message.contains("access_denied") || message.contains("insufficient authentication") {
                throw CalendarEngineError.needsRescope
            }
            throw CalendarEngineError.needsRescope
        }
        guard (200..<300).contains(status) else {
            throw CalendarEngineError.server(Self.googleError(from: data) ?? "Google Calendar request failed.")
        }
        return try JSONDecoder().decode(T.self, from: data)
    }

    private func friendlyError(_ error: Error) -> String {
        if let engineError = error as? CalendarEngineError {
            return engineError.message
        }
        return error.localizedDescription
    }

    private func emptyToNil(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func compactNotes(_ raw: String, limit: Int) -> String {
        let cleaned = raw
            .replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit))
    }

    private static func gapFacts(for events: [CalendarEventItem]) -> [String] {
        guard events.count > 1 else { return [] }
        var facts: [String] = []
        for index in 0..<(events.count - 1) {
            let current = events[index]
            let next = events[index + 1]
            if current.isAllDay || next.isAllDay { continue }
            let minutes = Int(next.start.timeIntervalSince(current.end) / 60)
            let bothFlights = current.isLikelyFlight && next.isLikelyFlight
            let sameDay = Calendar.current.isDate(current.end, inSameDayAs: next.start)
            if minutes >= 0, !bothFlights, minutes > 8 * 60 { continue }
            if minutes >= 0, bothFlights, minutes > 10 * 60 { continue }
            if minutes >= 12 * 60, !sameDay, !bothFlights { continue }
            let pair = "after \"\(current.title)\" ends \(current.end.formatted(date: .omitted, time: .shortened)) until \"\(next.title)\" starts \(next.start.formatted(date: .abbreviated, time: .shortened))"
            if minutes < 0 {
                facts.append("OVERLAP \(abs(minutes)) min: \(pair). These conflict.")
            } else if minutes == 0 {
                facts.append("ZERO GAP: \(pair). Back-to-back.")
            } else {
                let hours = minutes / 60
                let remain = minutes % 60
                let wait = hours > 0 ? "\(hours)h \(remain)m" : "\(remain) min"
                if current.isLikelyFlight && next.isLikelyFlight {
                    if minutes < 75 {
                        facts.append("TIGHT CONNECTION \(wait): \(pair). This wait IS a layover, just short. Never say there is no layover.")
                    } else {
                        facts.append("LAYOVER \(wait): \(pair). This wait IS the layover/connection. Never say there is no layover.")
                    }
                } else {
                    facts.append("GAP \(wait): \(pair).")
                }
            }
        }
        return facts
    }

    private static let rfc3339: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static func googleError(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(GoogleAPIError.self, from: data) {
            return payload.error?.message
        }
        return String(data: data, encoding: .utf8)
    }
}

enum CalendarEngineError: Error, LocalizedError {
    case signedOut
    case needsRescope
    case apiDisabled
    case invalidResponse
    case server(String)

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .signedOut:
            return "Google session expired. Sign in again."
        case .needsRescope:
            return "Calendar needs a new Google permission. Open Mail or Calendar, sign out, then sign in again and accept Calendar."
        case .apiDisabled:
            return "Enable Google Calendar API on the PortalsOS GCP project, add the Calendar events scope in Data Access, then sign in again."
        case .invalidResponse:
            return "Google Calendar returned an unexpected response."
        case .server(let value):
            return value
        }
    }
}

private struct EventListResponse: Decodable {
    let items: [EventResource]?
}

private struct EventResource: Decodable {
    let id: String?
    let summary: String?
    let location: String?
    let description: String?
    let htmlLink: String?
    let start: EventTime?
    let end: EventTime?

    func asItem() -> CalendarEventItem? {
        guard let id, let startDate = start?.dateValue else { return nil }
        let endDate = end?.dateValue ?? startDate.addingTimeInterval(3600)
        return CalendarEventItem(
            id: id,
            title: (summary?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false) ? summary! : "(No title)",
            start: startDate,
            end: endDate,
            isAllDay: start?.date != nil,
            location: location ?? "",
            notes: description ?? "",
            htmlLink: htmlLink
        )
    }
}

private struct EventTime: Decodable {
    let dateTime: String?
    let date: String?

    var dateValue: Date? {
        if let dateTime, let parsed = Self.parseDateTime(dateTime) {
            return parsed
        }
        if let date, let parsed = Self.parseDay(date) {
            return parsed
        }
        return nil
    }

    private static func parseDateTime(_ raw: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: raw) { return date }
        let basic = ISO8601DateFormatter()
        basic.formatOptions = [.withInternetDateTime]
        return basic.date(from: raw)
    }

    private static func parseDay(_ raw: String) -> Date? {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: raw)
    }
}

private struct EventWritePayload: Encodable {
    let summary: String
    let location: String?
    let start: EventWriteTime
    let end: EventWriteTime
}

private struct EventWriteTime: Encodable {
    let dateTime: String
    let timeZone: String

    static func dateTime(_ date: Date, timeZone: String) -> EventWriteTime {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZone) ?? .current
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return EventWriteTime(dateTime: formatter.string(from: date), timeZone: timeZone)
    }
}

private struct GoogleAPIError: Decodable {
    struct Nested: Decodable {
        let message: String?
    }

    let error: Nested?
}
