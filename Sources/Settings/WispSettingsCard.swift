import SwiftUI

/// What answers Wisp: Apple's on-device model, or Claude, OpenAI or another service with the
/// owner's own API key. Keys go straight to the Keychain and are never shown again.
struct WispSettingsCard: View {
    @AppStorage(WispProvider.key) private var provider: WispProvider = .apple
    @AppStorage(WispProvider.addressKey) private var address = ""
    @State private var keyDraft = ""
    @State private var hasKey = false
    @State private var model = ""

    var body: some View {
        SettingsCard("Wisp", systemImage: "bubble.left.and.text.bubble.right") {
            Picker("Answers with", selection: $provider) {
                ForEach(WispProvider.allCases) { Text($0.title).tag($0) }
            }
            Text(provider.explanation).font(.caption).foregroundStyle(.secondary)
            if provider == .compatible {
                field("Address", text: $address, prompt: "https://api.example.com/v1")
            }
            if provider != .apple {
                field("Model", text: Binding(get: { model }, set: { model = $0; saveModel() }),
                      prompt: provider.defaultModel.isEmpty ? "Model name" : provider.defaultModel)
                keyRow
            }
        }
        .onAppear(perform: load)
        .onChange(of: provider) { _ in load(); WispModel.shared.providerChanged() }
        .onChange(of: address) { _ in WispModel.shared.providerChanged() }
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
                    WispModel.shared.providerChanged()
                }
                .buttonStyle(.settings(.destructive))
            } else {
                SecureField(provider.needsKey ? "Paste your key" : "Paste a key if the service needs one", text: $keyDraft)
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
        hasKey = provider != .apple && WispKeys.has(provider)
        model = UserDefaults.standard.string(forKey: provider.modelKey) ?? ""
    }

    private func saveKey() {
        guard WispKeys.set(keyDraft, for: provider) else { return }
        load()
        WispModel.shared.providerChanged()
    }

    private func saveModel() {
        let trimmed = model.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { UserDefaults.standard.removeObject(forKey: provider.modelKey) }
        else { UserDefaults.standard.set(trimmed, forKey: provider.modelKey) }
        WispModel.shared.providerChanged()
    }
}
