import Foundation
import Security

/// What answers Wisp's plain-language chat. Apple's on-device model is the default; the others
/// use the owner's own API key, kept in the Keychain, and send the conversation to that service.
enum WispProvider: String, CaseIterable, Identifiable {
    case apple, claude, openAI, compatible

    static let key = "wisp.provider"
    static var current: WispProvider {
        UserDefaults.standard.string(forKey: key).flatMap(WispProvider.init(rawValue:)) ?? .apple
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        case .apple: return "Apple Intelligence"
        case .claude: return "Claude"
        case .openAI: return "OpenAI"
        case .compatible: return "Another service"
        }
    }

    /// Settings' line under the picker.
    var explanation: String {
        switch self {
        case .apple: return "Apple's on-device model. Nothing leaves this Mac."
        case .claude: return "Uses your Anthropic API key. What you ask Wisp is sent to Anthropic."
        case .openAI: return "Uses your OpenAI API key. What you ask Wisp is sent to OpenAI."
        case .compatible: return "Any service with an OpenAI-style chat API, such as Gemini, Mistral, Groq, OpenRouter or a local Ollama. What you ask Wisp is sent to the address below."
        }
    }

    var defaultModel: String {
        switch self {
        case .apple: return ""
        case .claude: return "claude-opus-5-5"
        case .openAI: return "gpt-5-mini"
        case .compatible: return ""
        }
    }

    var modelKey: String { "wisp.\(rawValue).model" }
    static let addressKey = "wisp.compatible.address"

    /// The model named in Settings, or the provider's default.
    var model: String {
        let saved = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultModel : saved
    }

    /// Chat-completions base: OpenAI's, or the address saved for another service.
    var baseURL: URL? {
        switch self {
        case .openAI: return URL(string: "https://api.openai.com/v1")
        case .compatible:
            let saved = UserDefaults.standard.string(forKey: Self.addressKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return saved.isEmpty ? nil : URL(string: saved.hasSuffix("/") ? String(saved.dropLast()) : saved)
        default: return nil
        }
    }

    /// Another service may need no key (a local Ollama); Claude and OpenAI always do.
    var needsKey: Bool { self == .claude || self == .openAI }

    /// Why chat can't reach this provider yet, or nil when it's set up.
    var setupProblem: String? {
        switch self {
        case .apple: return nil
        case .claude, .openAI:
            return WispKeys.has(self) ? nil : "Add your \(title) API key in Settings › Apps › Wisp."
        case .compatible:
            if baseURL == nil { return "Add the service's address in Settings › Apps › Wisp." }
            if model.isEmpty { return "Name the model to use in Settings › Apps › Wisp." }
            return nil
        }
    }

    var engine: WispEngine {
        let name = self == .compatible ? model : title
        if let setupProblem { return .offline(setupProblem) }
        let maker = self == .compatible ? (baseURL?.host ?? "that service") : (self == .claude ? "Anthropic" : "OpenAI")
        return WispEngine(name: name, detail: "\(model) answers with your API key. What you ask is sent to \(maker).",
                          isModel: true, symbol: "key.horizontal")
    }
}

/// API keys for Wisp's providers, one Keychain item each, readable only by MacSpaces on this Mac.
enum WispKeys {
    private static let service = "dev.opensource.MacSpaces.wisp"

    private static func query(_ provider: WispProvider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: provider.rawValue]
    }

    static func get(_ provider: WispProvider) -> String? {
        var query = query(provider)
        query[kSecReturnData as String] = true
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func has(_ provider: WispProvider) -> Bool { !(get(provider) ?? "").isEmpty }

    @discardableResult
    static func set(_ key: String, for provider: WispProvider) -> Bool {
        let value = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return remove(provider) }
        let data = Data(value.utf8)
        let updated = SecItemUpdate(query(provider) as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updated == errSecSuccess { return true }
        var add = query(provider)
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    @discardableResult
    static func remove(_ provider: WispProvider) -> Bool {
        let status = SecItemDelete(query(provider) as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}

/// A plain sentence for the chat when a provider fails.
struct WispCloudError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

/// Chat with a model behind the owner's API key. It can't call Wisp's tools directly, so it
/// asks for actions with `DO:` lines (`WispReply`) that Wisp runs through its plain requests.
@MainActor
final class WispCloudBrain {
    let provider: WispProvider
    private var history: [(role: String, text: String)] = []

    init(provider: WispProvider) {
        self.provider = provider
    }

    /// The model's raw reply; the user's message joins the history once it's answered.
    func respond(to prompt: String) async throws -> String {
        if let problem = provider.setupProblem { throw WispCloudError(message: problem) }
        let turns = history + [(role: "user", text: prompt)]
        let reply = try await provider == .claude ? askClaude(turns) : askChat(turns)
        history.append((role: "user", text: prompt))
        return reply
    }

    /// What Wisp said in the end, actions included, so the model knows what happened.
    func record(_ reply: String) {
        history.append((role: "assistant", text: reply))
        if history.count > 24 { history.removeFirst(history.count - 24) }
    }

    private var instructions: String {
        let now = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
        return """
            You are Wisp, a small, cheerful assistant living in the notch of the user's Mac, inside MacSpaces.
            Reply in one or two short sentences of plain text, no lists or markdown.
            You can act on the Mac. To do something, add a line of its own starting with "DO:" and one plain request:
            DO: remind me to call Sam tomorrow at 9am
            DO: check off call Sam
            DO: note: the door code is 4411
            DO: focus
            DO: stop focus
            DO: tea timer 4 minutes
            DO: my day
            Wisp carries out each line and tells the user if one fails, so never say something is done without one.
            "DO: my day" shows the user's calendar and reminders for today.
            If a request is unclear, ask one short question. It is now \(now).
            """
    }

    private func askClaude(_ turns: [(role: String, text: String)]) async throws -> String {
        guard let key = WispKeys.get(.claude) else { throw WispCloudError(message: WispProvider.claude.setupProblem ?? "") }
        var body: [String: Any] = [
            "model": provider.model,
            "max_tokens": 8000,
            "system": instructions,
            "messages": turns.map { ["role": $0.role, "content": $0.text] },
        ]
        // Effort exists on the 5-series models; older ones reject it.
        if provider.model.range(of: #"^claude-(opus|sonnet|haiku|fable)-5"#, options: .regularExpression) != nil {
            body["output_config"] = ["effort": "low"]
        }
        let json = try await post(URL(string: "https://api.anthropic.com/v1/messages")!, body: body, headers: [
            "x-api-key": key, "anthropic-version": "2026-10-21"])
        let blocks = json["content"] as? [[String: Any]] ?? []
        let text = blocks.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined()
        if text.isEmpty, json["stop_reason"] as? String == "refusal" { return "I can't help with that one." }
        return text
    }

    private func askChat(_ turns: [(role: String, text: String)]) async throws -> String {
        guard let base = provider.baseURL else { throw WispCloudError(message: provider.setupProblem ?? "") }
        var headers: [String: String] = [:]
        if let key = WispKeys.get(provider), !key.isEmpty { headers["Authorization"] = "Bearer \(key)" }
        let body: [String: Any] = [
            "model": provider.model,
            "messages": [["role": "system", "content": instructions]] + turns.map { ["role": $0.role, "content": $0.text] },
        ]
        let json = try await post(base.appendingPathComponent("chat/completions"), body: body, headers: headers)
        let choice = (json["choices"] as? [[String: Any]])?.first
        return (choice?["message"] as? [String: Any])?["content"] as? String ?? ""
    }

    private func post(_ url: URL, body: [String: Any], headers: [String: String]) async throws -> [String: Any] {
        var request = URLRequest(url: url, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let data: Data, response: URLResponse
        do { (data, response) = try await URLSession.shared.data(for: request) }
        catch { throw WispCloudError(message: "I couldn't reach \(provider.title). Check your connection.") }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            let detail = (json["error"] as? [String: Any])?["message"] as? String
            switch status {
            case 401, 403: throw WispCloudError(message: "\(provider.title) didn't accept the API key. Check it in Settings › Apps › Wisp.")
            case 429: throw WispCloudError(message: "\(provider.title) is busy or the key is out of credit. Try again in a moment.")
            default: throw WispCloudError(message: "\(provider.title) said: \(detail ?? "error \(status)")")
            }
        }
        return json
    }
}
