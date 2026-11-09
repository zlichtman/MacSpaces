import Foundation
import Security

/// Who the chat talks to. The on-device agent (Wisp or KemoSabe, Apple Intelligence) is the
/// default; Claude and Codex come in as themselves through the owner's signed-in Claude Code or
/// Codex (`AgentCLI`), or an API key kept in the Keychain as the fallback, and ask the on-device
/// agent for anything personal. Another service is an OpenAI-style address with a key.
enum WispProvider: String, CaseIterable, Identifiable {
    case apple, claude, openAI, compatible

    static let key = "wisp.provider"
    static var current: WispProvider {
        UserDefaults.standard.string(forKey: key).flatMap(WispProvider.init(rawValue:)) ?? .apple
    }

    var id: String { rawValue }

    var title: String {
        switch self {
        // The on-device agent, named for the face on its page.
        case .apple: return WispCharacter.current.title
        case .claude: return "Claude"
        case .openAI: return "Codex"
        case .compatible: return "Another service"
        }
    }

    /// The service as the gateway rules name it: Codex also answers to OpenAI, so "Only Claude …"
    /// and "Never tell OpenAI …" both reach it.
    var serviceName: String { self == .openAI ? "Codex (OpenAI)" : title }

    /// The command-line tool it comes in through, for Claude and Codex.
    var cli: AgentCLI? {
        switch self {
        case .claude: return .claude
        case .openAI: return .codex
        default: return nil
        }
    }

    /// Settings' line under the picker.
    var explanation: String {
        switch self {
        case .apple: return "Apple's on-device model. Nothing leaves this Mac."
        case .claude, .openAI: return "What you ask goes to \(maker); your data stays with \(WispCharacter.current.title), which answers only what your rules allow."
        case .compatible: return "Gemini, Mistral, OpenRouter, a local Ollama: anything with an OpenAI-style chat API. What you ask is sent there."
        }
    }

    var maker: String {
        switch self {
        case .apple: return "Apple"
        case .claude: return "Anthropic"
        case .openAI: return "OpenAI"
        case .compatible: return baseURL?.host ?? "that service"
        }
    }

    // MARK: Connection

    /// How Claude or Codex is reached: the signed-in command-line tool, or an API key.
    enum Connection: String, CaseIterable, Identifiable {
        case cli, key
        var id: String { rawValue }
    }

    var connectionKey: String { "wisp.\(rawValue).via" }

    /// The saved choice; unset is the API key when one is saved (what answered before the tools
    /// could), else the command-line tool. Another service always uses its address and key.
    var connection: Connection {
        guard cli != nil else { return .key }
        if let saved = UserDefaults.standard.string(forKey: connectionKey).flatMap(Connection.init(rawValue:)) { return saved }
        return WispKeys.has(self) ? .key : .cli
    }

    // MARK: Models

    var defaultModel: String {
        switch self {
        case .apple: return ""
        case .claude: return "claude-opus-5-5"
        case .openAI: return "gpt-5-mini"
        case .compatible: return ""
        }
    }

    var modelKey: String { "wisp.\(rawValue).model" }
    /// The command-line tool's model; unset is the tool's own default.
    var cliModelKey: String { "wisp.\(rawValue).cliModel" }
    static let addressKey = "wisp.compatible.address"

    /// The model named in Settings, or the provider's default, for the API key.
    var model: String {
        let saved = UserDefaults.standard.string(forKey: modelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return saved.isEmpty ? defaultModel : saved
    }

    /// The command-line tool's model, or "" for its own default.
    var cliModel: String {
        UserDefaults.standard.string(forKey: cliModelKey)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }

    /// The model menu for the current connection: ids, with "" meaning the tool's default. The
    /// saved one is always offered, so a name typed before menus stays.
    @MainActor var modelChoices: [String] {
        var choices: [String]
        switch (self, connection) {
        case (.claude, .cli): choices = ["", "opus", "sonnet", "haiku"]
        case (.claude, .key): choices = ["claude-opus-5-5", "claude-sonnet-5-5", "claude-haiku-5-5", "claude-fable-5-1"]
        case (.openAI, .cli): choices = [""] + AgentConnections.shared.codexModels
        case (.openAI, .key): choices = ["gpt-5-mini"] + AgentConnections.shared.codexModels
        default: choices = []
        }
        let saved = connection == .cli ? cliModel : model
        if !choices.contains(saved) { choices.append(saved) }
        return choices
    }

    static func modelTitle(_ id: String) -> String {
        switch id {
        case "": return "Default"
        case "opus", "sonnet", "haiku": return id.prefix(1).uppercased() + id.dropFirst()
        default: return id
        }
    }

    /// The model in use, for the tag and the menu.
    var modelInUse: String { connection == .cli ? cliModel : model }

    func setModel(_ id: String) {
        let key = connection == .cli ? cliModelKey : modelKey
        if id.isEmpty { UserDefaults.standard.removeObject(forKey: key) } else { UserDefaults.standard.set(id, forKey: key) }
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

    /// Why chat can't reach this provider yet, or nil when it's set up (or may be: a tool whose
    /// state isn't known yet is tried).
    @MainActor var setupProblem: String? {
        switch self {
        case .apple: return nil
        case .claude, .openAI:
            if connection == .cli, let cli {
                switch AgentConnections.shared.status(of: cli) {
                case .notInstalled: return "Install \(cli.title), or add your \(maker) API key in Settings › Tsukumo."
                case .signedOut: return "Sign in to \(cli.title) (\(cli.signInHint)), or add an API key in Settings › Tsukumo."
                case .ready, .unknown: return nil
                }
            }
            return WispKeys.has(self) ? nil : "Add your \(maker) API key in Settings › Tsukumo."
        case .compatible:
            if baseURL == nil { return "Add the service's address in Settings › Tsukumo." }
            if model.isEmpty { return "Name the model to use in Settings › Tsukumo." }
            return nil
        }
    }

    @MainActor var engine: WispEngine {
        if let setupProblem { return .offline(setupProblem, partner: self) }
        let name = self == .compatible ? model : title
        let how: String
        if connection == .cli, let cli {
            how = "\(title) answers through your \(cli.title)" + (cliModel.isEmpty ? "" : " (\(Self.modelTitle(cliModel)))") + "."
        } else {
            how = "\(model) answers with your API key."
        }
        return WispEngine(name: name, detail: "\(how) What you ask is sent to \(maker).", isModel: true,
                          symbol: "key.horizontal", partner: self)
    }
}

/// API keys for Wisp's providers, one Keychain item each, readable only by MacSpaces on this Mac.
enum WispKeys {
    private static let service = KeychainService.named("wisp")

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

/// Chat with Claude, Codex or another service, through the signed-in command-line tool or an API
/// key. None of them can call the on-device agent's tools or read the Mac: they ask for actions
/// with `DO:` lines and for personal facts with `ASK:` lines (`WispReply`), which the on-device
/// agent carries out or answers here.
@MainActor
final class WispCloudBrain {
    let provider: WispProvider
    let connection: WispProvider.Connection
    private var history: [(role: String, text: String)] = []

    init(provider: WispProvider) {
        self.provider = provider
        connection = provider.connection
    }

    /// The model's raw reply; the user's message joins the history once it's answered.
    func respond(to prompt: String) async throws -> String {
        if let problem = provider.setupProblem { throw WispCloudError(message: problem) }
        let turns = history + [(role: "user", text: prompt)]
        let reply: String
        if connection == .cli, let cli = provider.cli {
            reply = try await askCLI(cli, turns)
        } else {
            reply = try await provider == .claude ? askClaude(turns) : askChat(turns)
        }
        history.append((role: "user", text: prompt))
        return reply
    }

    /// The conversation as one prompt for a command-line tool, which keeps no session.
    static func transcript(_ turns: [(role: String, text: String)]) -> String {
        guard let last = turns.last else { return "" }
        guard turns.count > 1 else { return last.text }
        let earlier = turns.dropLast().map { ($0.role == "user" ? "User: " : "You: ") + $0.text }.joined(separator: "\n\n")
        return "The conversation so far:\n\n\(earlier)\n\nReply to this:\n\n\(last.text)"
    }

    /// Claude Code with no tools, no MCP servers, no settings or hooks and no saved session; Codex
    /// read-only, ephemeral, without the owner's config, hooks, apps or plugins. Both run in an empty
    /// folder with MacSpaces' privacy grants disclaimed (`AgentProcess`).
    private func askCLI(_ cli: AgentCLI, _ turns: [(role: String, text: String)]) async throws -> String {
        guard let path = cli.path else {
            AgentConnections.shared.refresh(force: true)
            throw WispCloudError(message: "Install \(cli.title), or add an API key in Settings › Tsukumo.")
        }
        let model = provider.cliModel
        let result: AgentProcess.Output
        do { // one scope for the run
            switch cli {
            case .claude:
                var arguments = ["-p", "--output-format", "json", "--tools", "", "--strict-mcp-config", "--setting-sources", "",
                                 "--no-session-persistence", "--system-prompt", instructions]
                if !model.isEmpty { arguments += ["--model", model] }
                result = try await AgentProcess.run(path, arguments, input: Self.transcript(turns), timeout: 180)
            case .codex:
                let answer = AgentProcess.workingDirectory.appendingPathComponent("codex-\(UUID().uuidString).txt")
                defer { try? FileManager.default.removeItem(at: answer) }
                var arguments = ["exec", "--skip-git-repo-check", "--ephemeral", "--ignore-user-config", "--ignore-rules",
                                 "--sandbox", "read-only", "-c", "approval_policy=\"never\"",
                                 "--disable", "hooks", "--disable", "apps", "--disable", "plugins",
                                 "--color", "never", "-o", answer.path]
                if !model.isEmpty { arguments += ["-m", model] }
                arguments.append("-")
                let ran = try await AgentProcess.run(path, arguments, input: instructions + "\n\n" + Self.transcript(turns), timeout: 180)
                let text = (try? String(contentsOf: answer, encoding: .utf8)) ?? ""
                result = AgentProcess.Output(status: ran.status, output: text, error: ran.error)
            }
        }
        return try Self.reply(cli, result, onSignedOut: { AgentConnections.shared.refresh(force: true) })
    }

    /// What a tool's run said, or a plain sentence on why it didn't.
    static func reply(_ cli: AgentCLI, _ result: AgentProcess.Output, onSignedOut: () -> Void) throws -> String {
        func signInProblem(_ text: String) -> Bool {
            let lower = text.lowercased()
            return ["auth", "log in", "login", "logged", "sign in", "credential", "401"].contains(where: lower.contains)
        }
        let signedOut = "\(cli.title) isn't signed in: \(cli.signInHint), or add an API key in Settings › Tsukumo."
        switch cli {
        case .claude:
            if let json = (try? JSONSerialization.jsonObject(with: Data(result.output.utf8))) as? [String: Any] {
                let text = (json["result"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                if json["is_error"] as? Bool != true, !text.isEmpty { return text }
                if signInProblem(text) { onSignedOut(); throw WispCloudError(message: signedOut) }
                throw WispCloudError(message: "Claude Code said: \(text.isEmpty ? "no answer" : String(text.prefix(200)))")
            }
        case .codex:
            let text = result.output.trimmingCharacters(in: .whitespacesAndNewlines)
            if result.status == 0, !text.isEmpty { return text }
        }
        let detail = result.error.split(separator: "\n").last.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
        if signInProblem(detail) { onSignedOut(); throw WispCloudError(message: signedOut) }
        if result.status >= 128 { throw WispCloudError(message: "\(cli.title) took too long to answer. Try again.") }
        throw WispCloudError(message: "\(cli.title) didn't answer" + (detail.isEmpty ? "." : ": \(String(detail.prefix(200)))"))
    }

    /// What Wisp said in the end, actions included, so the model knows what happened.
    func record(_ reply: String) {
        history.append((role: "assistant", text: reply))
        if history.count > 24 { history.removeFirst(history.count - 24) }
    }

    private var instructions: String {
        let now = Date().formatted(.dateTime.weekday(.wide).day().month(.wide).year().hour().minute())
        let agent = WispCharacter.current.title
        let you = provider == .compatible ? "an assistant" : provider.title
        return """
            You are \(you), talking with the user in MacSpaces, in the notch of their Mac. \(agent), their on-device \
            agent, runs on Apple Intelligence on this Mac: it holds their personal data and acts for you.
            Reply in one or two short sentences of plain text, no lists or markdown. You have no tools here and \
            can't read files or the Mac.
            To act on the Mac, add a line of its own starting with "DO:" and one plain request:
            DO: remind me to call the dentist tomorrow at 9am
            DO: check off call the dentist
            DO: remove call the dentist
            DO: note: buy oat milk
            DO: focus
            DO: stop focus
            DO: tea timer 4 minutes
            DO: my day
            \(agent) carries out each line and tells the user if one fails, so never say something is done without one.
            "DO: my day" shows the user's calendar and reminders for today; you don't see it.
            \(GatewayShare.instructionLines(agent: agent))
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
            case 401, 403: throw WispCloudError(message: "\(provider.title) didn't accept the API key. Check it in Settings › Tsukumo.")
            case 429: throw WispCloudError(message: "\(provider.title) is busy or the key is out of credit. Try again in a moment.")
            default: throw WispCloudError(message: "\(provider.title) said: \(detail ?? "error \(status)")")
            }
        }
        return json
    }
}
