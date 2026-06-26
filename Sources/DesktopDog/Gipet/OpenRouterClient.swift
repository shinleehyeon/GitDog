// Gipet — generates commit messages from a git diff via OpenAI or OpenRouter.
//
// The API key is NEVER hardcoded (it would be extractable from the binary).
// It's read, in order, from:
//   1. the OPENROUTER_API_KEY / OPENAI_API_KEY environment variable
//   2. ~/.gipet/config.json
//        { "openrouter_key": "sk-or-...", "model": "openai/gpt-4o-mini" }   // OpenRouter
//        { "openai_key": "sk-proj-...",  "model": "gpt-4o-mini" }           // OpenAI
//        (optional "base_url" overrides the endpoint)
//
// Provider is auto-detected from the key prefix: sk-or-… → OpenRouter,
// otherwise → OpenAI.

import Foundation

enum OpenRouterClient {
    private struct Config: Decodable {
        let openrouter_key: String?
        let openai_key: String?
        let model: String?
        let base_url: String?
    }

    private static func loadConfig() -> Config? {
        let path = (NSHomeDirectory() as NSString).appendingPathComponent(".gipet/config.json")
        guard let data = FileManager.default.contents(atPath: path) else { return nil }
        return try? JSONDecoder().decode(Config.self, from: data)
    }

    static var apiKey: String? {
        let env = ProcessInfo.processInfo.environment
        if let k = env["OPENROUTER_API_KEY"], !k.isEmpty { return k }
        if let k = env["OPENAI_API_KEY"], !k.isEmpty { return k }
        let c = loadConfig()
        return c?.openrouter_key?.nonEmpty ?? c?.openai_key?.nonEmpty
    }

    /// True when the key targets OpenRouter; false → OpenAI.
    private static var usesOpenRouter: Bool {
        (apiKey ?? "").hasPrefix("sk-or-")
    }

    static var baseURL: String {
        if let b = loadConfig()?.base_url?.nonEmpty { return b }
        return usesOpenRouter
            ? "https://openrouter.ai/api/v1/chat/completions"
            : "https://api.openai.com/v1/chat/completions"
    }

    static var model: String {
        if let m = loadConfig()?.model?.nonEmpty { return m }
        return usesOpenRouter ? "openai/gpt-4o-mini" : "gpt-4o-mini"
    }

    static var isConfigured: Bool { apiKey?.isEmpty == false }

    private struct ChatResponse: Decodable {
        struct Choice: Decodable { struct Msg: Decodable { let content: String }; let message: Msg }
        let choices: [Choice]
    }

    /// Ask the model for a concise conventional-commit message for `diff`.
    /// Throws if not configured or the request fails.
    static func commitMessage(for diff: String) async throws -> String {
        let system = "You write concise git commit messages. Reply with ONE line in the Conventional Commits style (e.g. 'feat: add X', 'fix: handle Y'). No quotes, no body, max 72 chars."
        return try await chat(system: system,
                              user: "Write a commit message for this staged diff:\n\n\(diff)",
                              maxTokens: 60)
    }

    /// A short friendly Korean journal line for the streak-journal feature.
    static func journalEntry() async throws -> String {
        let system = "너는 개발자의 하루 저널을 한 줄로 써주는 도우미야. 친근한 한국어로 오늘의 TIL, 짧은 동기부여, 또는 개발 관련 한 줄 메모를 작성해. 따옴표 없이 한 문장, 최대 50자."
        return try await chat(system: system,
                              user: "오늘의 저널 한 줄 써줘.",
                              maxTokens: 80)
    }

    /// Shared chat-completion call (OpenAI / OpenRouter compatible).
    private static func chat(system: String, user: String, maxTokens: Int) async throws -> String {
        guard let key = apiKey, !key.isEmpty else {
            throw APIError.decode("AI key not configured (~/.gipet/config.json)")
        }
        guard let url = URL(string: baseURL) else { throw APIError.badURL }
        let body: [String: Any] = [
            "model": model,
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
            "max_tokens": maxTokens,
            "temperature": 0.6,
        ]

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("https://github.com/gipet", forHTTPHeaderField: "HTTP-Referer")
        req.setValue("Gipet", forHTTPHeaderField: "X-Title")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, resp) = try await URLSession.shared.data(for: req)
        if let http = resp as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            let msg = String(data: data, encoding: .utf8) ?? ""
            throw APIError.decode("AI http \(http.statusCode): \(msg.prefix(200))")
        }
        let decoded = try JSONDecoder().decode(ChatResponse.self, from: data)
        let text = decoded.choices.first?.message.content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\"", with: "") ?? ""
        guard !text.isEmpty else { throw APIError.decode("empty completion") }
        return text.split(separator: "\n").first.map(String.init) ?? text
    }
}

private extension String {
    var nonEmpty: String? { isEmpty ? nil : self }
}
