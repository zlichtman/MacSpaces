import SwiftUI

/// Heartable: MacSpaces' music side. How the Music page looks, swiping through songs, and Spotify.
struct HeartableSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared

    var body: some View {
        SettingsPage(title: "Heartable", subtitle: "Your music: how the player looks, changing songs, and Spotify.") {
            MusicPlayerCard()
            SettingsCard("Swipe", systemImage: "hand.draw") {
                Toggle("Swipe sideways on the notch or Music panel to change songs", isOn: $settings.swipeToChangeSongs)
            }
            SpotifySettingsCard()
            LocalFilesCard()
        }
    }
}

/// Tsukumo: the agents. Who shows on Wisp's page, what answers it, and the coding agents MacSpaces follows.
struct TsukumoSettingsPane: View {
    @ObservedObject private var agents = AgentActivityMonitor.shared
    @AppStorage(WidgetOptions.Keys.wispCharacter) private var character: WispCharacter = .wisp
    @AppStorage(WidgetOptions.Keys.kemoSabeLook) private var lookID = KemoSabeLook.apricot.id
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        SettingsPage(title: "Tsukumo", subtitle: "Your agent, what it may share, and the coding agents you run.") {
            SettingsCard("Agent", systemImage: "person.crop.circle") {
                HStack(spacing: 12) {
                    ForEach(WispCharacter.allCases) { AgentChoice(character: $0, selection: $character, look: KemoSabeLook.named(lookID)) }
                }
                if character == .kemosabe {
                    // KemoSabe's looks, as the theme picker shows scenes.
                    Text("Look").font(.caption.weight(.semibold)).foregroundStyle(.secondary).padding(.top, 4)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)], alignment: .leading, spacing: 12) {
                        ForEach(KemoSabeLook.all) { look in
                            KemoSabeLookCard(look: look, selected: look.id == KemoSabeLook.named(lookID).id,
                                             accent: theme.settings.accent) { lookID = look.id }
                        }
                    }
                }
            }
            WispSettingsCard()
            GatewaySettingsCard()
            SettingsCard("Creating audio", systemImage: "waveform") {
                Text("Coming next: drop in a voice recording and \(character.title) can answer in that voice.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            SettingsCard("Coding agents", systemImage: "terminal") {
                Toggle("Coding agents that need you", isOn: Binding(
                    get: { agents.isEnabled }, set: { agents.setEnabled($0) }))
                    .help("MacSpaces adds one silent hook to ~/.claude/settings.json and ~/.codex/hooks.json (your own hooks are kept, and a backup is saved); turning this off removes it.")
                Text("A bubble beside the notch when Claude Code or Codex needs you. Click it to open that session.")
                    .font(.caption).foregroundStyle(.secondary)
                    .help("Sessions show in the Terminal page's Agents tab. The bubble pulses until the agent is working again, never covers your windows, waits while your Mac is locked or a Hide in app is in front, and doesn't appear in screen sharing or recordings.")
                if let error = agents.error { Text(error).font(.caption).foregroundStyle(.red) }
                if agents.isEnabled {
                    Toggle("Show the bubble while agents work", isOn: Binding(
                        get: { agents.peekWhileWorking }, set: { agents.setPeekWhileWorking($0) }))
                        .help("The bubble also sits beside the notch while any agent works, showing its app with a soft pulse, and ticks for a moment when one finishes. Off, it appears only when an agent needs you.")
                    Toggle("Answer permission requests in MacSpaces", isOn: Binding(
                        get: { agents.answersEnabled }, set: { agents.setAnswersEnabled($0) }))
                        .help("When an agent asks to run a command or edit a file, Allow and Deny appear in Agents (and the bubble's menu). Each answer covers that one request. Unanswered after \(Int(AgentActivityMonitor.answerWait)) seconds, or with Answer in App, the agent's own prompt takes over.")
                    CodexHookNotice(inSettings: true)
                }
            }
        }
    }
}

/// One agent to pick, shown as it looks on its page: on the Nook's own colour, live.
private struct AgentChoice: View {
    let character: WispCharacter
    @Binding var selection: WispCharacter
    let look: KemoSabeLook
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let selected = selection == character
        Button { selection = character } label: {
            VStack(spacing: 8) {
                Group {
                    switch character {
                    case .wisp: WispFace(mood: .idle, size: 52)
                    case .kemosabe: KemoSabeFace(mood: .idle, size: 64, look: look)
                    }
                }
                .frame(width: 112, height: 76)
                .background(theme.notch.surface, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                Text(character.title).font(.system(size: 12, weight: selected ? .semibold : .medium))
            }
            .padding(8)
            .background(selected ? theme.settings.selected : Color.clear, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(selected ? theme.settings.accent : Color.clear, lineWidth: 1.5)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(character.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// One of KemoSabe's looks, as a theme card: KemoSabe still, on its palette's own colour.
private struct KemoSabeLookCard: View {
    let look: KemoSabeLook
    let selected: Bool
    let accent: Color
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(alignment: .leading, spacing: 8) {
                ZStack {
                    Color(kemoHex: look.background)
                    KemoSabeFace(mood: .idle, size: 54, look: look, small: true, still: true)
                }
                .frame(height: 64)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
                    selected ? accent : Color.primary.opacity(0.10), lineWidth: selected ? 2 : 1))
                HStack(spacing: 4) {
                    Text(look.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("KemoSabe, \(look.name)")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// KemoSabe, the gateway: what a cloud model may learn from this Mac, whichever face is picked.
/// Today that's when you're free, and only with this switch on (`KemoSabeGateway`).
private struct GatewaySettingsCard: View {
    @AppStorage(WispProvider.key) private var provider: WispProvider = .apple
    @AppStorage(WidgetOptions.Keys.kemoSabeShareFreeTimes) private var shareFreeTimes = false
    @AppStorage(WidgetOptions.Keys.wispCharacter) private var character: WispCharacter = .wisp

    var body: some View {
        SettingsCard("Gateway", systemImage: "checkmark.shield") {
            if provider == .apple {
                Text("Apple's model runs on this Mac, so KemoSabe holds nothing back. With a cloud model, KemoSabe decides what it learns.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                // Turning it on is the explicit action that may ask for Calendar access.
                Toggle("Share when you're free", isOn: Binding(get: { shareFreeTimes }, set: { on in
                    shareFreeTimes = on
                    if on { Task { _ = await WispAccess.calendar() } }
                }))
                Text("\(provider.title) never sees your calendar: KemoSabe reads it on this Mac and answers with free times only. Each answer shows in the chat.")
                    .help("Never what an event is, where, or with whom. Events marked free, declined or cancelled don't count.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// Folio: your files and your clipboard.
struct FolioSettingsPane: View {
    var body: some View {
        SettingsPage(title: "Folio", subtitle: "Your files and clipboard: what reaches the Tray, converting files, and history.") {
            FilesSettingsCards()
            ClipboardSettingsCards()
        }
    }
}
