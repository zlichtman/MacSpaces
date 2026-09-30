import SwiftUI

/// Quick tasks share the caption bar's proportions, never a dashboard column.
struct TsukumoWidget: View {
    var onEditingChanged: (Bool) -> Void = { _ in }
    @FocusState private var composing: Bool
    @StateObject private var bridge = TsukumoBridgeClient()
    @State private var conversation: UUID?
    @State private var prompt = ""
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "sparkles").accessibilityLabel("Tsukumo")
            if bridge.conversations.isEmpty {
                Button("Connect Tsukumo") { Task { await bridge.discover() } }.disabled(bridge.busy)
                Text(bridge.message).foregroundStyle(.secondary).lineLimit(1).help(bridge.message)
                Spacer(minLength: 0)
            } else {
                Picker("Conversation", selection: $conversation) {
                    Text("Conversation…").tag(nil as UUID?)
                    ForEach(bridge.conversations) { item in Text(item.title).tag(Optional(item.id)) }
                }.labelsHidden().frame(maxWidth: 155).disabled(bridge.sending)
                TextField("Quick task…", text: $prompt).textFieldStyle(.plain).focused($composing).disabled(bridge.sending)
                    .onSubmit { send() }
                Button(action: send) { Image(systemName: "arrow.up.circle.fill") }
                    .disabled(!canSend).accessibilityLabel("Send task")
                Menu {
                    Text(bridge.message)
                    Button("Open conversation") { guard let conversation else { return }; Task { await bridge.open(conversation) } }.disabled(conversation == nil)
                    Button("Cancel task") { guard let conversation else { return }; Task { await bridge.cancel(conversation) } }.disabled(selected?.canCancel != true)
                    Button("Refresh conversations") { Task { await bridge.discover() } }
                } label: { Image(systemName: "ellipsis") }.fixedSize().disabled(bridge.busy).help(bridge.message)
            }
            if bridge.busy { ProgressView().controlSize(.mini) }
        }
        .task(id: conversation) {
            guard let conversation else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
                await bridge.status(conversation)
            }
        }
        .onChange(of: composing) { onEditingChanged($0) }
        .onDisappear { bridge.disconnect(); onEditingChanged(false) }
    }
    private var selected: MacSpacesBridge.Conversation? { bridge.conversations.first { $0.id == conversation } }
    private var canSend: Bool { !bridge.busy && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && selected?.canSubmit == true }
    private func send() {
        guard canSend, let conversation else { return }
        Task { if await bridge.submit(prompt, to: conversation) { prompt = "" } }
    }
}

private struct QuickActionBarStyle: ViewModifier {
    @ObservedObject private var theme = ThemeStore.shared
    func body(content: Content) -> some View {
        content.font(.system(size: 11)).buttonStyle(.borderless)
            .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 38)
            .foregroundStyle(theme.nookForeground).tint(theme.notch.accent)
            .background(theme.notch.control.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
    }
}
extension View {
    func quickActionBar() -> some View { modifier(QuickActionBarStyle()) }
}
