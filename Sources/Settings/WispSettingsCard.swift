import SwiftUI

/// The chat's card, named for the on-device agent picked in the Agent card (Wisp or KemoSabe):
/// who's connected (Claude through Claude Code, Codex through Codex, each with an API key as the
/// fallback and a model menu), then the gateway's rules. Who you talk to is picked in the chat.
/// Keys go straight to the Keychain and are never shown again; MacSpaces never reads the tools'
/// own credentials, it only runs them.
struct WispSettingsCard: View {
    @AppStorage(WidgetOptions.Keys.wispCharacter) private var character: WispCharacter = .wisp
    @AppStorage(WispProvider.key) private var provider: WispProvider = .apple
    @AppStorage(WispProvider.addressKey) private var address = ""
    @ObservedObject private var connections = AgentConnections.shared
    @State private var addingService = false

    var body: some View {
        SettingsCard(character.title, systemImage: "bubble.left.and.text.bubble.right", anchor: "Wisp") {
            SettingsCaption("\(character.title) runs on Apple Intelligence on this Mac. Claude and Codex ask it for anything personal.",
                            help: "\(character.title) runs on Apple Intelligence on this Mac. Claude and Codex ask it for anything personal and get only its answer.")
            SettingsSectionHeading("Connected")
            WispConnectionRow(provider: .claude)
            WispConnectionRow(provider: .openAI)
            if provider == .compatible || !address.isEmpty || addingService {
                WispConnectionRow(provider: .compatible)
            } else {
                Button("Add another service") { addingService = true }
                    .buttonStyle(.settings())
                    .help("Gemini, Mistral, OpenRouter, a local Ollama: anything with an OpenAI-style chat API, with your key.")
            }
            Divider()
            GatewayRulesSection()
        }
        .onAppear { connections.refresh(force: true) }
    }
}

/// One service: its mark and name, whether it's connected, how (the command-line tool or an API
/// key), and its model.
private struct WispConnectionRow: View {
    let provider: WispProvider
    @ObservedObject private var connections = AgentConnections.shared
    @AppStorage(WispProvider.addressKey) private var address = ""
    @State private var connection: WispProvider.Connection = .cli
    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var typedModel = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                AgentMark(partner: provider, size: 18)
                Text(provider.title).font(.system(size: 13, weight: .semibold))
                Spacer(minLength: 8)
                status
            }
            if let cli = provider.cli {
                SettingsSegmentedPicker("Connect with", selection: Binding(get: { connection }, set: { choose($0) }),
                                        options: [WispProvider.Connection.cli, .key]) { $0 == .cli ? cli.title : "API key" }
                if connection == .key { keyRow }
                Picker("Model", selection: Binding(get: { provider.modelInUse }, set: { provider.setModel($0); changed() })) {
                    ForEach(provider.modelChoices, id: \.self) { Text(WispProvider.modelTitle($0)).tag($0) }
                }
                .fixedSize()
            } else {
                field("Address", text: $address, prompt: "https://api.example.com/v1")
                field("Model", text: Binding(get: { typedModel }, set: { typedModel = $0; saveTypedModel() }), prompt: "Model name")
                keyRow
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 9, style: .continuous))
        .onAppear(perform: load)
        .onChange(of: address) { _ in changed() }
    }

    /// Connected or not, in a few words; the tooltip says how to fix it.
    @ViewBuilder private var status: some View {
        let problem = provider.setupProblem
        HStack(spacing: 4) {
            Image(systemName: problem == nil ? "checkmark.circle.fill" : "exclamationmark.circle")
                .foregroundStyle(problem == nil ? Color.green : Color.secondary)
            Text(statusText).foregroundStyle(.secondary)
        }
        .font(.caption)
        .help(problem ?? provider.explanation)
    }

    private var statusText: String {
        _ = connections.status
        if connection == .cli, let cli = provider.cli {
            switch connections.status(of: cli) {
            case .ready: return "Signed in"
            case .signedOut: return "Not signed in"
            case .notInstalled: return "Not installed"
            case .unknown: return cli.path == nil ? "Not installed" : "Installed"
            }
        }
        return provider.setupProblem == nil ? (hasKey ? "Key saved" : "Ready") : (hasKey ? "Not set up" : "No key")
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        HStack(spacing: 8) {
            Text(label).frame(width: 64, alignment: .leading)
            TextField(prompt, text: text).settingsTextField()
        }
    }

    @ViewBuilder private var keyRow: some View {
        HStack(spacing: 8) {
            Text("API key").frame(width: 64, alignment: .leading)
            if hasKey {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Saved in your Keychain").foregroundStyle(.secondary)
                Spacer()
                Button("Remove") {
                    WispKeys.remove(provider)
                    load()
                    changed()
                }
                .buttonStyle(.settings(.destructive))
            } else {
                SecureField(provider.needsKey ? "Paste your \(provider.maker) key" : "Paste a key if the service needs one", text: $keyDraft)
                    .settingsTextField()
                    .onSubmit(saveKey)
                Button("Save", action: saveKey)
                    .buttonStyle(.settings())
                    .disabled(keyDraft.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func load() {
        keyDraft = ""
        hasKey = WispKeys.has(provider)
        connection = provider.connection
        typedModel = UserDefaults.standard.string(forKey: provider.modelKey) ?? ""
    }

    private func choose(_ new: WispProvider.Connection) {
        UserDefaults.standard.set(new.rawValue, forKey: provider.connectionKey)
        connection = new
        changed()
    }

    private func changed() {
        WispModel.shared.providerChanged()
    }

    private func saveKey() {
        guard WispKeys.set(keyDraft, for: provider) else { return }
        load()
        changed()
    }

    private func saveTypedModel() {
        let trimmed = typedModel.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { UserDefaults.standard.removeObject(forKey: provider.modelKey) }
        else { UserDefaults.standard.set(trimmed, forKey: provider.modelKey) }
        changed()
    }
}
