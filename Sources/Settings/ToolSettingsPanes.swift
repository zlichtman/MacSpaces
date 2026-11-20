import SwiftUI

/// Heartable: MacSpaces' music side. How the Music page looks, swiping through songs, and Spotify.
struct HeartableSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared

    var body: some View {
        SettingsPage(title: "Heartable", subtitle: "Your music: how the player looks, changing songs, your files and Spotify.") {
            MusicPlayerCard()
            SettingsCard("Swipe", systemImage: "hand.draw") {
                Toggle("Swipe sideways on the notch or Music page to change songs", isOn: $settings.swipeToChangeSongs)
            }
            LocalFilesCard()
            SpotifySettingsCard()
        }
    }
}

/// Tsukumo: the agents. The on-device agent (who shows on its page), who's connected and its
/// rules, the coding agents MacSpaces follows, then the voice models.
struct TsukumoSettingsPane: View {
    @ObservedObject private var agents = AgentActivityMonitor.shared
    @AppStorage(WidgetOptions.Keys.wispCharacter) private var character: WispCharacter = .wisp

    var body: some View {
        SettingsPage(title: "Tsukumo", subtitle: "Your agent, what it may share, and the coding agents you run.") {
            AgentSettingsCard(character: $character)
            WispSettingsCard()
            SettingsCard("Coding agents", systemImage: "terminal") {
                Toggle("Coding agents that need you", isOn: Binding(
                    get: { agents.isEnabled }, set: { agents.setEnabled($0) }))
                    .help("MacSpaces adds one silent hook to ~/.claude/settings.json and ~/.codex/hooks.json (your own hooks are kept, and a backup is saved); turning this off removes it.")
                SettingsCaption("A bubble beside the notch when Claude Code or Codex needs you. Click it to open that session.",
                                help: "Sessions show in the Terminal page's Agents tab. The bubble pulses until the agent is working again, never covers your windows, waits while your Mac is locked or a Hide in app is in front, and doesn't appear in screen sharing or recordings.")
                if let error = agents.error { SettingsCaption(error, colour: .red) }
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
            SettingsCard("Voice", systemImage: "waveform") {
                VoiceSettings(agent: character.title)
            }
        }
    }
}

/// The Agent card: pick who shows on Wisp's page, then its colours from the full theme list
/// (`TerminalThemeList` with `AgentThemePick`): the same search, tone and pack filters and rows as
/// Appearance. A theme colours both
/// characters (`AgentColours.palette(for:)`) and never changes the Nook's; the arrow keys step
/// through it the same way. Under the list, the colours in use as wells (changing one makes them
/// Custom, with no row picked) and a Glass level for both. The character tiles show the pick live.
struct AgentSettingsCard: View {
    @Binding var character: WispCharacter
    // Not private: a private stored property would make the memberwise initialiser private.
    var colours = AgentColourSettings()
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var library = GhosttyLibrary.shared
    /// The list is a drawer, closed to save space; its header names the colours picked.
    @AppStorage(WidgetOptions.Keys.agentColoursDrawer) private var coloursOpen = false

    init(character: Binding<WispCharacter>) {
        _character = character
    }

    var body: some View {
        let palette = colours.palette
        SettingsCard("Agent", systemImage: "person.crop.circle") {
            HStack(spacing: 12) {
                ForEach(WispCharacter.allCases) { AgentChoice(character: $0, selection: $character) }
            }
            SettingsDisclosure("Colours", detail: palette.name, isOpen: $coloursOpen) {
                TerminalThemeList(agent: AgentThemePick(
                    selectedID: palette.themeItemID,
                    choose: { AgentColours.choose($0) }))
                    .onAppear {
                        library.load()
                        MotifThumbnails.shared.prepare(ThemeCollection.live.cardPhotos)
                    }
                Divider()
                AgentColourBar(character: character)
            }
            .padding(.top, 4)
        }
    }
}

/// Under the list: the colours in use as wells, which open the same wheel and hex field as a
/// theme's dots (changing one makes the colours Custom, starting from what shows), and the Glass
/// level, which both characters wear.
private struct AgentColourBar: View {
    let character: WispCharacter
    // Not private: a private stored property would make the memberwise initialiser private.
    var colours = AgentColourSettings()
    @ObservedObject private var theme = ThemeStore.shared
    @State private var editing: String?

    private struct Well: Identifiable {
        let id: String
        let title: String
        let hex: String
    }

    private var wells: [Well] {
        let look = colours.kemoSabe()
        let light = theme.nookScheme == .light
        let eye: String = colours.wispEye()?.hex ?? (light ? "000000" : "FFFFFF")
        switch character {
        case .wisp: return [Well(id: WidgetOptions.Keys.agentCustomFace, title: "Eyes", hex: eye)]
        case .kemosabe:
            return [Well(id: WidgetOptions.Keys.agentCustomBody, title: "Body", hex: look.body),
                    Well(id: WidgetOptions.Keys.agentCustomFace, title: "Face", hex: look.face)]
        }
    }

    private var glass: Double { character == .kemosabe ? colours.glass : colours.wispGlass }

    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 5) {
                // Custom shows here, in the wells, since no theme row is picked.
                Text(colours.palette.id == AgentPalette.custom.id ? "Custom" : "Colours").padding(.trailing, 3)
                ForEach(wells) { well in
                    Button { editing = well.id } label: {
                        Circle().fill(Color(kemoHex: well.hex))
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.28), lineWidth: 1))
                            .frame(width: 16, height: 16)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(well.title)
                    .accessibilityLabel("\(well.title) colour")
                    .popover(isPresented: Binding(get: { editing == well.id }, set: { if !$0 { editing = nil } }), arrowEdge: .bottom) {
                        ThemeColourEditor(title: well.title, current: { well.hex }, apply: { makeCustom(well.id, $0) })
                    }
                }
            }
            .fixedSize()
            HStack(spacing: 6) {
                Text("Glass")
                Slider(value: Binding(get: { glass }, set: { AgentColours.setGlass($0) }), in: 0...1)
                    .controlSize(.mini)
                    .accessibilityLabel("Glass")
                    .frame(width: 64)
                Text("\(Int((glass * 100).rounded()))%")
                    .monospacedDigit().foregroundStyle(.secondary)
                    .fixedSize().frame(minWidth: 30, alignment: .trailing)
            }
            .help("How much glass Wisp and KemoSabe wear: from solid to frosted and see-through, with the face still solid.")
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
    }

    /// Custom from the colours showing, with one changed.
    private func makeCustom(_ key: String, _ hex: String) {
        let defaults = UserDefaults.standard
        if colours.palette.id != AgentPalette.custom.id {
            let look = colours.kemoSabe()
            defaults.set(look.body, forKey: WidgetOptions.Keys.agentCustomBody)
            let face: String = character == .wisp ? (colours.wispEye()?.hex ?? look.face) : look.face
            defaults.set(face, forKey: WidgetOptions.Keys.agentCustomFace)
        }
        defaults.set(hex, forKey: key)
        AgentColours.choose(.custom)
    }
}

/// One agent to pick, shown as it looks on its page: on the Nook's own colour, live, in the agent's colours.
private struct AgentChoice: View {
    let character: WispCharacter
    @Binding var selection: WispCharacter
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let selected = selection == character
        Button { selection = character } label: {
            VStack(spacing: 8) {
                Group {
                    switch character {
                    case .wisp: WispFace(mood: .idle, size: 52)
                    case .kemosabe: KemoSabeAgentFace(mood: .idle, size: 66)
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

/// The gateway's rules: what the on-device agent may tell Claude, Codex or another service. It
/// shares by judgement, from what macOS lets it read, unless these plain-words rules say otherwise
/// (`GatewayShare`), and Ask me before sharing holds each answer for the owner.
struct GatewayRulesSection: View {
    @AppStorage(WidgetOptions.Keys.gatewayRules) private var rules = ""
    @AppStorage(WidgetOptions.Keys.gatewayAskFirst) private var askFirst = false
    @AppStorage(WidgetOptions.Keys.wispCharacter) private var character: WispCharacter = .wisp
    @ObservedObject private var theme = ThemeStore.shared

    init() {}

    var body: some View {
        SettingsSectionHeading("Rules")
        ZStack(alignment: .topLeading) {
            TextEditor(text: $rules)
                .font(.system(size: 12))
                .scrollContentBackground(.hidden)
                .frame(height: 76)
            if rules.isEmpty {
                Text("Only Claude may know my schedule.\nNever say who I'm with.\nNever share anything about my health.")
                    .font(.system(size: 12)).foregroundStyle(.tertiary)
                    .padding(.horizontal, 5).padding(.top, 1)
                    .allowsHitTesting(false)
            }
        }
        .padding(6)
        .background(theme.settings.selected, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .help("Plain words, like a system prompt. \(character.title) shares what macOS lets it read unless a rule says otherwise; Apple's model on this Mac checks every answer against them before it leaves.")
        SettingsCaption(rulesNote)
        Toggle("Ask me before sharing", isOn: $askFirst)
            .help("Each answer waits in the chat, showing exactly what would go, until you choose Share or Don't share. Left for two minutes, it isn't shared.")
    }

    private var rulesNote: String {
        let agent = character.title
        let shown = askFirst ? "Each answer waits in the chat until you share it." : "Every answer that goes shows in the chat."
        if GatewayJudge.split(rules).isEmpty {
            return rules.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "\(agent) shares what it can read: Calendar and Reminders, as Permissions allow. \(shown)"
                : "\(agent) follows these exactly. \(shown)"
        }
        return KemoSabeReader.isAvailable
            ? "Apple's model checks every answer against your rules first. \(shown)"
            : "Rules need Apple's model, which isn't available on this Mac, so \(agent) shares nothing while they're set."
    }
}


/// Folio: your files and your clipboard.
struct FolioSettingsPane: View {
    var body: some View {
        SettingsPage(title: "Folio", subtitle: "Your files and clipboard: the library, what comes in, history and converting.") {
            FolioLibraryCard()
            FolioSourcesCard()
            ClipboardSettingsCards()
            FileConverterCard()
        }
    }
}
