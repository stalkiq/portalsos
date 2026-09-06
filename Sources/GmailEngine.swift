import AuthenticationServices
import Combine
import CryptoKit
import Foundation
import Security
import UIKit

enum GoogleOAuth {
    static let clientID = "456235441470-m6as6qb2a67g6svri1vcsa4l5f93i9u7.apps.googleusercontent.com"
    static let callbackScheme = "com.googleusercontent.apps.456235441470-m6as6qb2a67g6svri1vcsa4l5f93i9u7"
    static let redirectURI = "\(callbackScheme):/oauthredirect"
    static let scopes = [
        "openid",
        "email",
        "profile",
        "https://www.googleapis.com/auth/gmail.modify",
        "https://www.googleapis.com/auth/calendar.events"
    ].joined(separator: " ")
}

struct GmailMessage: Identifiable, Equatable {
    let id: String
    let threadId: String
    let from: String
    let to: String
    let subject: String
    let date: String
    let snippet: String
    let rfcMessageID: String?
    var isUnread: Bool
    var labelIds: [String]
    var body: String?

    var replySubject: String {
        let trimmed = subject.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased().hasPrefix("re:") {
            return trimmed
        }
        return "Re: \(trimmed.isEmpty ? "(no subject)" : trimmed)"
    }

    var senderEmail: String {
        Self.email(from: from)
    }

    var triageLine: String {
        let tags = Self.triageTags(isUnread: isUnread, labelIds: labelIds)
        let who = Self.clip(from, 42)
        let title = Self.clip(subject, 72)
        let preview = Self.clip(snippet, 110)
        return "[\(tags)] \(who) | \(title) | \(preview)"
    }

    private static func clip(_ raw: String, _ limit: Int) -> String {
        let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit))
    }

    private static func triageTags(isUnread: Bool, labelIds: [String]) -> String {
        var tags: [String] = []
        if isUnread { tags.append("UNREAD") }
        if labelIds.contains("STARRED") { tags.append("STARRED") }
        if labelIds.contains("IMPORTANT") { tags.append("IMPORTANT") }
        if labelIds.contains("CATEGORY_PROMOTIONS") { tags.append("PROMO") }
        else if labelIds.contains("CATEGORY_SOCIAL") { tags.append("SOCIAL") }
        else if labelIds.contains("CATEGORY_UPDATES") { tags.append("UPDATES") }
        else if labelIds.contains("CATEGORY_FORUMS") { tags.append("FORUMS") }
        else if labelIds.contains("CATEGORY_PERSONAL") { tags.append("PERSONAL") }
        return tags.isEmpty ? "MAIL" : tags.joined(separator: " ")
    }

    static func email(from raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if let start = trimmed.firstIndex(of: "<"), let end = trimmed.firstIndex(of: ">"), start < end {
            return String(trimmed[trimmed.index(after: start)..<end]).trimmingCharacters(in: .whitespaces)
        }
        return trimmed
    }
}

@MainActor
final class GmailEngine: NSObject, ObservableObject {
    @Published var isSignedIn = false
    @Published var email = ""
    @Published var messages: [GmailMessage] = []
    @Published var selectedID: String?
    @Published var isBusy = false
    @Published var statusText = "Sign in with Google to load Gmail."
    @Published var errorMessage: String?

    private var tokens: TokenSet?
    private var authSession: ASWebAuthenticationSession?
    private let presenter = AuthPresenter()

    var selectedMessage: GmailMessage? {
        messages.first(where: { $0.id == selectedID }) ?? messages.first
    }

    var insightContext: String? {
        guard isSignedIn else { return nil }
        let account = email.isEmpty ? "this Google account" : email
        if messages.isEmpty {
            return "Gmail is signed in as \(account). The inbox is empty — nothing to triage."
        }
        let unread = messages.filter(\.isUnread).count
        var parts = [
            "Live Gmail inbox for \(account).",
            "\(messages.count) recent messages, \(unread) unread. Gmail tags: UNREAD, STARRED, IMPORTANT, PROMO, SOCIAL, UPDATES, FORUMS, PERSONAL.",
            "Inbox:"
        ]
        for (index, item) in messages.enumerated() {
            parts.append("\(index + 1). id=\(item.id) \(item.triageLine)")
        }
        if let message = selectedMessage, let body = message.body, !body.isEmpty {
            parts.append("Opened message body (\(Self.compactText(message.subject, limit: 60))):\n\(Self.compactText(body, limit: 700))")
        }
        return parts.joined(separator: "\n")
    }

    override init() {
        super.init()
        if let stored = Self.loadTokens() {
            tokens = stored
            isSignedIn = true
            email = stored.email ?? ""
            statusText = email.isEmpty ? "Signed in. Loading inbox..." : "Signed in as \(email)."
        }
    }

    func googleAccessToken() async throws -> String {
        try await validAccessToken()
    }

    func restoreInboxIfNeeded() async {
        guard isSignedIn, messages.isEmpty else { return }
        await refreshInbox()
    }

    func signIn() async {
        errorMessage = nil
        isBusy = true
        statusText = "Opening Google sign-in..."
        do {
            let verifier = Self.makeCodeVerifier()
            let code = try await authorizationCode(codeVerifier: verifier)
            var next = try await exchangeCode(code, verifier: verifier)
            next.email = try await fetchEmail(accessToken: next.accessToken)
            tokens = next
            Self.saveTokens(next)
            isSignedIn = true
            email = next.email ?? ""
            statusText = email.isEmpty ? "Signed in." : "Signed in as \(email)."
            try await loadInbox()
        } catch let error as GmailEngineError where error == .canceled {
            statusText = "Sign-in canceled."
        } catch {
            errorMessage = friendlyError(error)
            statusText = "Sign-in failed."
        }
        isBusy = false
    }

    func signOut() {
        tokens = nil
        Self.deleteTokens()
        isSignedIn = false
        email = ""
        messages = []
        selectedID = nil
        errorMessage = nil
        statusText = "Sign in with Google to load Gmail."
    }

    func refreshInbox() async {
        guard isSignedIn else { return }
        errorMessage = nil
        isBusy = true
        statusText = "Loading inbox..."
        do {
            try await loadInbox()
        } catch {
            errorMessage = friendlyError(error)
            statusText = "Could not load inbox."
        }
        isBusy = false
    }

    func loadBody(for message: GmailMessage) async -> GmailMessage {
        if let body = message.body, !body.isEmpty {
            return message
        }
        do {
            let access = try await validAccessToken()
            if let full = try await fetchMessage(id: message.id, accessToken: access, format: "full"),
               let index = messages.firstIndex(where: { $0.id == message.id }) {
                var merged = full
                merged.isUnread = messages[index].isUnread
                messages[index] = merged
                return merged
            }
        } catch {
            errorMessage = friendlyError(error)
        }
        return message
    }

    func message(id: String) -> GmailMessage? {
        messages.first(where: { $0.id == id })
    }

    func openMessage(_ message: GmailMessage) async {
        selectedID = message.id
        do {
            let access = try await validAccessToken()
            if message.body == nil,
               let full = try await fetchMessage(id: message.id, accessToken: access, format: "full") {
                if let index = messages.firstIndex(where: { $0.id == message.id }) {
                    messages[index] = full
                }
            }
            try await modifyLabels(id: message.id, accessToken: access, add: nil, remove: ["UNREAD"])
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index].isUnread = false
            }
        } catch {
            errorMessage = friendlyError(error)
        }
    }

    func messageMatching(to: String?, sender: String?, subject: String?) -> GmailMessage? {
        let toNeedle = to?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let senderNeedle = sender?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""
        let subjectNeedle = subject?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() ?? ""

        func score(_ message: GmailMessage) -> Int {
            var value = 0
            let email = message.senderEmail.lowercased()
            let from = message.from.lowercased()
            let title = message.subject.lowercased()
            if !toNeedle.isEmpty, email == toNeedle || from.contains(toNeedle) {
                value += 5
            }
            if !senderNeedle.isEmpty, from.contains(senderNeedle) || email.contains(senderNeedle) {
                value += 4
            }
            if !subjectNeedle.isEmpty, title.contains(subjectNeedle) || subjectNeedle.contains(title) {
                value += 3
            }
            return value
        }

        return messages
            .map { ($0, score($0)) }
            .filter { $0.1 > 0 }
            .max { $0.1 < $1.1 }?
            .0
    }

    func sendMail(to: String, subject: String, body: String, replyTo: GmailMessage?) async throws {
        let trimmedTo = to.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedBody = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedTo.contains("@"), !trimmedBody.isEmpty else {
            throw GmailEngineError.server("Add a recipient and a message body before sending.")
        }
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        let access = try await validAccessToken()
        let raw = Self.rfc822(
            from: email,
            to: trimmedTo,
            subject: subject,
            body: trimmedBody,
            inReplyTo: replyTo?.rfcMessageID
        )
        struct SendPayload: Encodable {
            let raw: String
            let threadId: String?

            enum CodingKeys: String, CodingKey {
                case raw, threadId
            }

            func encode(to encoder: Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(raw, forKey: .raw)
                if let threadId {
                    try container.encode(threadId, forKey: .threadId)
                }
            }
        }
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/send")!
        let _: MessageResource = try await postJSON(
            url,
            accessToken: access,
            body: SendPayload(raw: raw, threadId: replyTo?.threadId)
        )
        try? await Task.sleep(nanoseconds: 500_000_000)
        do {
            try await loadInbox()
        } catch {
            statusText = "Sent. Pull down to refresh the inbox."
        }
    }

    func archiveMessage(_ message: GmailMessage) async {
        await mutate(message) { access in
            try await modifyLabels(id: message.id, accessToken: access, add: nil, remove: ["INBOX"])
        }
    }

    func trashMessage(_ message: GmailMessage) async {
        await mutate(message) { access in
            let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(message.id)/trash")!
            try await postEmpty(url, accessToken: access)
        }
    }

    private func mutate(_ message: GmailMessage, work: (String) async throws -> Void) async {
        errorMessage = nil
        isBusy = true
        do {
            let access = try await validAccessToken()
            try await work(access)
            messages.removeAll { $0.id == message.id }
            if selectedID == message.id {
                selectedID = messages.first?.id
            }
        } catch {
            errorMessage = friendlyError(error)
        }
        isBusy = false
    }

    private func loadInbox() async throws {
        let access = try await validAccessToken()
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages")!
        components.queryItems = [
            URLQueryItem(name: "maxResults", value: "15"),
            URLQueryItem(name: "labelIds", value: "INBOX")
        ]
        let list: MessageListResponse = try await getJSON(components.url!, accessToken: access)
        let ids = (list.messages ?? []).map(\.id)
        guard !ids.isEmpty else {
            messages = []
            selectedID = nil
            statusText = "Inbox is empty."
            return
        }

        var loaded: [GmailMessage] = []
        loaded.reserveCapacity(ids.count)
        try await withThrowingTaskGroup(of: GmailMessage?.self) { group in
            var iterator = ids.makeIterator()
            let limit = 3
            func enqueueNext() {
                guard let id = iterator.next() else { return }
                group.addTask {
                    try await self.fetchMessage(id: id, accessToken: access, format: "metadata")
                }
            }
            for _ in 0..<min(limit, ids.count) {
                enqueueNext()
            }
            for try await item in group {
                if let item {
                    loaded.append(item)
                }
                enqueueNext()
            }
        }

        let order = Dictionary(uniqueKeysWithValues: ids.enumerated().map { ($1, $0) })
        messages = loaded.sorted { lhs, rhs in
            (order[lhs.id] ?? 0) < (order[rhs.id] ?? 0)
        }
        if selectedID == nil || !messages.contains(where: { $0.id == selectedID }) {
            selectedID = messages.first?.id
        }
        statusText = "Inbox · \(messages.count) messages"
    }

    private func fetchMessage(id: String, accessToken: String, format: String) async throws -> GmailMessage? {
        var components = URLComponents(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)")!
        var items = [URLQueryItem(name: "format", value: format)]
        if format == "metadata" {
            items.append(URLQueryItem(name: "metadataHeaders", value: "From"))
            items.append(URLQueryItem(name: "metadataHeaders", value: "To"))
            items.append(URLQueryItem(name: "metadataHeaders", value: "Subject"))
            items.append(URLQueryItem(name: "metadataHeaders", value: "Date"))
            items.append(URLQueryItem(name: "metadataHeaders", value: "Message-ID"))
        }
        components.queryItems = items
        let payload: MessageResource = try await getJSON(components.url!, accessToken: accessToken)
        return GmailMessage(
            id: payload.id,
            threadId: payload.threadId ?? payload.id,
            from: payload.header("From") ?? "Unknown sender",
            to: payload.header("To") ?? "",
            subject: payload.header("Subject") ?? "(no subject)",
            date: payload.header("Date") ?? "",
            snippet: Self.compactText(payload.snippet ?? "", limit: 240),
            rfcMessageID: payload.header("Message-ID"),
            isUnread: payload.labelIds?.contains("UNREAD") == true,
            labelIds: payload.labelIds ?? [],
            body: format == "full" ? payload.plainTextBody().map { Self.compactText($0, limit: 1600) } : nil
        )
    }

    private func authorizationCode(codeVerifier: String) async throws -> String {
        let challenge = Self.makeCodeChallenge(from: codeVerifier)
        var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
        components.queryItems = [
            URLQueryItem(name: "client_id", value: GoogleOAuth.clientID),
            URLQueryItem(name: "redirect_uri", value: GoogleOAuth.redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: GoogleOAuth.scopes),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "include_granted_scopes", value: "true"),
            URLQueryItem(name: "prompt", value: "consent")
        ]
        guard let url = components.url else {
            throw GmailEngineError.invalidResponse
        }

        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: GoogleOAuth.callbackScheme) { callbackURL, error in
                Task { @MainActor in
                    self.authSession = nil
                    if let error {
                        let nsError = error as NSError
                        if nsError.domain == ASWebAuthenticationSessionError.errorDomain,
                           nsError.code == ASWebAuthenticationSessionError.canceledLogin.rawValue {
                            continuation.resume(throwing: GmailEngineError.canceled)
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let callbackURL else {
                        continuation.resume(throwing: GmailEngineError.invalidResponse)
                        return
                    }
                    let items = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false)?.queryItems ?? []
                    if let oauthError = items.first(where: { $0.name == "error" })?.value {
                        continuation.resume(throwing: GmailEngineError.oauth(oauthError))
                        return
                    }
                    guard let code = items.first(where: { $0.name == "code" })?.value, !code.isEmpty else {
                        continuation.resume(throwing: GmailEngineError.invalidResponse)
                        return
                    }
                    continuation.resume(returning: code)
                }
            }
            session.presentationContextProvider = self.presenter
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                continuation.resume(throwing: GmailEngineError.invalidResponse)
            }
        }
    }

    private func exchangeCode(_ code: String, verifier: String) async throws -> TokenSet {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id": GoogleOAuth.clientID,
            "code": code,
            "code_verifier": verifier,
            "grant_type": "authorization_code",
            "redirect_uri": GoogleOAuth.redirectURI
        ].map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }
        .joined(separator: "&")
        .data(using: .utf8)

        let payload: TokenResponse = try await decode(request)
        return TokenSet(
            accessToken: payload.accessToken,
            refreshToken: payload.refreshToken,
            expiry: Date().addingTimeInterval(TimeInterval(payload.expiresIn - 60)),
            email: nil
        )
    }

    private func validAccessToken() async throws -> String {
        guard var current = tokens else {
            throw GmailEngineError.signedOut
        }
        if current.expiry > Date() {
            return current.accessToken
        }
        guard let refresh = current.refreshToken, !refresh.isEmpty else {
            signOut()
            throw GmailEngineError.signedOut
        }
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = [
            "client_id": GoogleOAuth.clientID,
            "refresh_token": refresh,
            "grant_type": "refresh_token"
        ].map { key, value in
            "\(key)=\(value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? value)"
        }
        .joined(separator: "&")
        .data(using: .utf8)

        let payload: TokenResponse = try await decode(request)
        current.accessToken = payload.accessToken
        current.expiry = Date().addingTimeInterval(TimeInterval(payload.expiresIn - 60))
        if let nextRefresh = payload.refreshToken {
            current.refreshToken = nextRefresh
        }
        tokens = current
        Self.saveTokens(current)
        return current.accessToken
    }

    private func fetchEmail(accessToken: String) async throws -> String? {
        let url = URL(string: "https://openidconnect.googleapis.com/v1/userinfo")!
        let profile: UserInfoResponse = try await getJSON(url, accessToken: accessToken)
        return profile.email
    }

    private func getJSON<T: Decodable>(_ url: URL, accessToken: String) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        return try await decode(request)
    }

    private func postJSON<T: Decodable, B: Encodable>(_ url: URL, accessToken: String, body: B) async throws -> T {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        return try await decode(request)
    }

    private func postEmpty(_ url: URL, accessToken: String) async throws {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        _ = try await decodeOptional(request)
    }

    private func modifyLabels(id: String, accessToken: String, add: [String]?, remove: [String]?) async throws {
        struct ModifyPayload: Encodable {
            let addLabelIds: [String]?
            let removeLabelIds: [String]?
        }
        let url = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me/messages/\(id)/modify")!
        let _: MessageResource = try await postJSON(
            url,
            accessToken: accessToken,
            body: ModifyPayload(addLabelIds: add, removeLabelIds: remove)
        )
    }

    private func decode<T: Decodable>(_ request: URLRequest) async throws -> T {
        let data = try await decodeOptional(request)
        return try JSONDecoder().decode(T.self, from: data)
    }

    @discardableResult
    private func decodeOptional(_ request: URLRequest) async throws -> Data {
        var delay: UInt64 = 400_000_000
        var lastError: Error = GmailEngineError.invalidResponse
        for attempt in 1...4 {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            if status == 401 {
                throw GmailEngineError.signedOut
            }
            if Self.isRateLimited(status: status, data: data) {
                lastError = GmailEngineError.server("Gmail is busy. Wait a second and try again.")
                if attempt < 4 {
                    try await Task.sleep(nanoseconds: delay)
                    delay *= 2
                    continue
                }
                throw lastError
            }
            if status == 403 {
                throw GmailEngineError.permission
            }
            guard (200..<300).contains(status) else {
                if let message = Self.googleErrorMessage(from: data) {
                    throw GmailEngineError.server(message)
                }
                throw GmailEngineError.invalidResponse
            }
            return data
        }
        throw lastError
    }

    private static func isRateLimited(status: Int, data: Data) -> Bool {
        if status == 429 {
            return true
        }
        let message = (googleErrorMessage(from: data) ?? "").lowercased()
        return message.contains("concurrent")
            || message.contains("rate limit")
            || message.contains("ratelimit")
            || message.contains("usagerate")
    }

    private func friendlyError(_ error: Error) -> String {
        if let engineError = error as? GmailEngineError {
            return engineError.message
        }
        return error.localizedDescription
    }

    private static func makeCodeVerifier() -> String {
        var bytes = [UInt8](repeating: 0, count: 32)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        return Data(bytes).base64URLEncodedString()
    }

    private static func makeCodeChallenge(from verifier: String) -> String {
        let hash = SHA256.hash(data: Data(verifier.utf8))
        return Data(hash).base64URLEncodedString()
    }

    private static func saveTokens(_ tokens: TokenSet) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        deleteLegacyTokens()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.portalsos.app",
            kSecAttrAccount as String: "google.tokens.v3"
        ]
        SecItemDelete(query as CFDictionary)
        var add = query
        add[kSecValueData as String] = data
        SecItemAdd(add as CFDictionary, nil)
    }

    private static func loadTokens() -> TokenSet? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.portalsos.app",
            kSecAttrAccount as String: "google.tokens.v3",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(TokenSet.self, from: data)
    }

    private static func rfc822(from: String, to: String, subject: String, body: String, inReplyTo: String?) -> String {
        var lines = [
            "From: \(from)",
            "To: \(to)",
            "Subject: \(subject)",
            "MIME-Version: 1.0",
            "Content-Type: text/plain; charset=UTF-8"
        ]
        if let inReplyTo, !inReplyTo.isEmpty {
            lines.append("In-Reply-To: \(inReplyTo)")
            lines.append("References: \(inReplyTo)")
        }
        let mime = lines.joined(separator: "\r\n") + "\r\n\r\n" + body
        return Data(mime.utf8).base64URLEncodedString()
    }

    private static func deleteTokens() {
        deleteLegacyTokens()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.portalsos.app",
            kSecAttrAccount as String: "google.tokens.v3"
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func deleteLegacyTokens() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.portalsos.app",
            kSecAttrAccount as String: "gmail.tokens.v2"
        ]
        SecItemDelete(query as CFDictionary)
    }

    private static func compactText(_ raw: String, limit: Int) -> String {
        let cleaned = raw
            .strippingHTML()
            .decodingHTMLEntities()
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count > limit else { return cleaned }
        return String(cleaned.prefix(limit))
    }

    private static func googleErrorMessage(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(GoogleErrorEnvelope.self, from: data) {
            return payload.errorDescription ?? payload.error?.message
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct TokenSet: Codable {
    var accessToken: String
    var refreshToken: String?
    var expiry: Date
    var email: String?
}

private struct TokenResponse: Decodable {
    let accessToken: String
    let expiresIn: Int
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }
}

private struct UserInfoResponse: Decodable {
    let email: String?
}

private struct MessageListResponse: Decodable {
    struct Ref: Decodable {
        let id: String
    }

    let messages: [Ref]?
}

private struct MessageResource: Decodable {
    struct Header: Decodable {
        let name: String?
        let value: String?
    }

    struct Body: Decodable {
        let data: String?
    }

    struct Part: Decodable {
        let mimeType: String?
        let filename: String?
        let headers: [Header]?
        let body: Body?
        let parts: [Part]?
    }

    let id: String
    let threadId: String?
    let snippet: String?
    let labelIds: [String]?
    let payload: Part?

    func header(_ name: String) -> String? {
        payload?.headers?.first(where: { $0.name?.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    func plainTextBody() -> String? {
        if let text = payload?.firstBody(matching: "text/plain") {
            return text
        }
        if let html = payload?.firstBody(matching: "text/html") {
            return html.strippingHTML()
        }
        return snippet
    }
}

private struct GoogleErrorEnvelope: Decodable {
    struct Nested: Decodable {
        let message: String?
    }

    let error: Nested?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case error
        case errorDescription = "error_description"
    }
}

private enum GmailEngineError: Equatable, Error, LocalizedError {
    case canceled
    case signedOut
    case permission
    case invalidResponse
    case oauth(String)
    case server(String)

    var errorDescription: String? { message }

    var message: String {
        switch self {
        case .canceled:
            return "Sign-in was canceled."
        case .signedOut:
            return "Google session expired. Sign in again."
        case .permission:
            return "Google blocked Gmail or Calendar. In Auth Platform → Data Access, add Gmail modify and Google Calendar events, enable those APIs, add your account as a test user, then sign out and sign in again."
        case .invalidResponse:
            return "Google returned an unexpected sign-in response."
        case .oauth(let value):
            return "Google sign-in error: \(value)"
        case .server(let value):
            return value
        }
    }
}

private final class AuthPresenter: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        if let key = scenes.flatMap(\.windows).first(where: \.isKeyWindow) {
            return key
        }
        return scenes.flatMap(\.windows).first ?? ASPresentationAnchor()
    }
}

private extension Data {
    func base64URLEncodedString() -> String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

private extension Data {
    init?(base64URLEncoded string: String) {
        var value = string
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        while value.count % 4 != 0 {
            value.append("=")
        }
        self.init(base64Encoded: value)
    }
}

private extension MessageResource.Part {
    func firstBody(matching mimeType: String) -> String? {
        if self.mimeType?.caseInsensitiveCompare(mimeType) == .orderedSame,
           let data = body?.data,
           let decoded = Data(base64URLEncoded: data),
           let text = String(data: decoded, encoding: .utf8),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text
        }
        return parts?.compactMap { $0.firstBody(matching: mimeType) }.first
    }
}

private extension String {
    func strippingHTML() -> String {
        replacingOccurrences(of: "(?is)<(script|style)[^>]*>.*?</\\1>", with: " ", options: .regularExpression)
            .replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "</p>", with: "\n", options: .regularExpression)
            .replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
            .decodingHTMLEntities()
    }

    func decodingHTMLEntities() -> String {
        var text = self
        let named: [(String, String)] = [
            ("&nbsp;", " "),
            ("&amp;", "&"),
            ("&quot;", "\""),
            ("&apos;", "'"),
            ("&#39;", "'"),
            ("&#039;", "'"),
            ("&#x27;", "'"),
            ("&lt;", "<"),
            ("&gt;", ">"),
            ("&hellip;", "..."),
            ("&mdash;", "—"),
            ("&ndash;", "–")
        ]
        for (entity, replacement) in named {
            text = text.replacingOccurrences(of: entity, with: replacement, options: .caseInsensitive)
        }
        if let regex = try? NSRegularExpression(pattern: "&#(x?[0-9a-fA-F]+);", options: .caseInsensitive) {
            let matches = regex.matches(in: text, range: NSRange(text.startIndex..., in: text)).reversed()
            for match in matches {
                guard let fullRange = Range(match.range, in: text),
                      let valueRange = Range(match.range(at: 1), in: text) else { continue }
                let value = String(text[valueRange])
                let scalar: UInt32?
                if value.lowercased().hasPrefix("x") {
                    scalar = UInt32(value.dropFirst(), radix: 16)
                } else {
                    scalar = UInt32(value)
                }
                if let scalar, let unicode = UnicodeScalar(scalar) {
                    text.replaceSubrange(fullRange, with: String(Character(unicode)))
                }
            }
        }
        return text
    }
}
