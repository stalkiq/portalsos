import Foundation

enum NebiusServiceError: LocalizedError {
    case missingAPIKey
    case invalidResponse
    case emptyContent
    case serverMessage(String)

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "Missing NEBIUS_API_KEY."
        case .invalidResponse:
            return "Nebius returned an invalid response."
        case .emptyContent:
            return "Nebius returned an empty reply."
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

struct NebiusService {
    private let defaultModel = "meta-llama/Llama-3.3-70B-Instruct"

    func generateInsight(for appName: String?, contextHint: String?, userPrompt: String?) async throws -> String {
        if let backend = backendURL(path: "/v1/insight") {
            let body = BackendInsightRequest(appName: appName, contextHint: contextHint, userPrompt: userPrompt, mode: "insight")
            let data = try await postJSON(to: backend, body: body, requiresDirectKey: false)
            let decoded = try JSONDecoder().decode(BackendInsightResponse.self, from: data)
            guard let text = decoded.text?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty else {
                throw NebiusServiceError.emptyContent
            }
            return text
        }

        return try await completeChat(
            system: "You are the on-device assistant for PortalsOS, a smartphone operating system. Provide concise, actionable insight in 2-4 short sentences. Keep the tone practical and helpful.",
            user: userMessage(appName: appName, contextHint: contextHint, userPrompt: userPrompt),
            maxTokens: 220
        )
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
            system: "You are PortalsOS Autopilot. Invent one plausible autonomous action the OS just completed across Messages, Mail, Phone, Calendar, or Browser. Reply with ONLY compact JSON: {\"title\":\"...\",\"detail\":\"...\",\"symbol\":\"message.fill\"}. symbol must be an SF Symbol like message.fill, envelope.fill, phone.fill, calendar, or safari.fill.",
            user: "Generate the next live Autopilot action now.",
            maxTokens: 120
        )
        return parseAutopilot(from: raw)
    }

    private func completeChat(system: String, user: String, maxTokens: Int) async throws -> String {
        let apiKey = resolvedAPIKey()
        guard !apiKey.isEmpty else {
            throw NebiusServiceError.missingAPIKey
        }

        let body = NebiusChatRequest(
            model: resolvedModel(),
            temperature: 0.4,
            maxTokens: maxTokens,
            messages: [
                .init(role: "system", content: system),
                .init(role: "user", content: user)
            ]
        )

        var request = URLRequest(url: tokenFactoryURL())
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        let decoded = try JSONDecoder().decode(NebiusChatResponse.self, from: data)
        guard let text = decoded.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else {
            throw NebiusServiceError.emptyContent
        }
        return text
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
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response, data: data)
        return data
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
        if let envKey = ProcessInfo.processInfo.environment["NEBIUS_API_KEY"], !envKey.isEmpty {
            return envKey
        }
        if let plistKey = Bundle.main.object(forInfoDictionaryKey: "NEBIUS_API_KEY") as? String, !plistKey.isEmpty {
            return plistKey
        }
        return ""
    }

    private func resolvedModel() -> String {
        if let envModel = ProcessInfo.processInfo.environment["NEBIUS_MODEL"], !envModel.isEmpty {
            return envModel
        }
        return defaultModel
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

    private func userMessage(appName: String?, contextHint: String?, userPrompt: String?) -> String {
        var prompt = ""
        if let appName, !appName.isEmpty {
            prompt += "App context: \(appName).\n"
        }
        if let contextHint, !contextHint.isEmpty {
            prompt += "System context: \(contextHint)\n"
        }
        if let userPrompt, !userPrompt.isEmpty {
            prompt += "User request: \(userPrompt)"
        } else {
            prompt += "User request: Provide useful next actions based on current context."
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

    private func decodedError(from data: Data) -> String? {
        if let payload = try? JSONDecoder().decode(NebiusErrorResponse.self, from: data),
           let message = payload.error?.message, !message.isEmpty {
            return message
        }
        return String(data: data, encoding: .utf8)
    }
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
    let messages: [NebiusMessage]

    enum CodingKeys: String, CodingKey {
        case model
        case temperature
        case maxTokens = "max_tokens"
        case messages
    }
}

private struct NebiusMessage: Encodable, Decodable {
    let role: String
    let content: String?
}

private struct NebiusChatResponse: Decodable {
    let choices: [NebiusChoice]
}

private struct NebiusChoice: Decodable {
    let message: NebiusMessage
}

private struct NebiusErrorResponse: Decodable {
    let error: NebiusErrorBody?
}

private struct NebiusErrorBody: Decodable {
    let message: String?
}
