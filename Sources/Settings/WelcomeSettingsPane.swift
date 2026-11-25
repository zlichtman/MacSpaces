import SwiftUI
import AppKit

/// The walkthrough, Settings' Welcome page: a page for the notch and one for each app inside
/// MacSpaces, with Tape's own guide on its page (the Tape app's "How to Use Tape", folded in).
/// Settings opens on it by itself once, on a new install; the sidebar, the MacSpaces menu, Tape's
/// menu and Find Action open it any time.
enum WelcomePage: Int, CaseIterable, Identifiable {
    case notch, heartable, tape, tsukumo, folio

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .notch: return "MacSpaces"
        case .heartable: return "Heartable"
        case .tape: return "Tape"
        case .tsukumo: return "Tsukumo"
        case .folio: return "Folio"
        }
    }

    var headline: String {
        switch self {
        case .notch: return "Your notch, opened up."
        case .heartable: return "Your music, in time with the words."
        case .tape: return "Your windows, side by side."
        case .tsukumo: return "An agent in your notch."
        case .folio: return "Files and clipboard at the notch."
        }
    }

    /// The Settings page it leads to, after the notch.
    var destination: SettingsDestination? {
        switch self {
        case .notch: return nil
        case .heartable: return .heartable
        case .tape: return .tape
        case .tsukumo: return .tsukumo
        case .folio: return .folio
        }
    }
}

@MainActor
final class WelcomeGuide: ObservableObject {
    static let shared = WelcomeGuide()
    /// Set once the walkthrough has opened, or at first launch for anyone already using MacSpaces.
    static let seenKey = "welcome.seen"
    /// The card's name in Settings search.
    static let card = "How to Use MacSpaces"

    @Published var page: WelcomePage = .notch

    /// Before anything else is saved this launch: a copy that has run before already has its
    /// settings, so it never opens the walkthrough by itself; only a new install does.
    static func noteInstall(_ defaults: UserDefaults = .standard) {
        guard defaults.object(forKey: seenKey) == nil, let id = Bundle.main.bundleIdentifier else { return }
        let saved = (defaults.persistentDomain(forName: id) ?? [:]).keys.filter { !$0.hasPrefix("NS") && !$0.hasPrefix("Apple") }
        if saved.count >= 5 { defaults.set(true, forKey: seenKey) }
    }

    /// At launch: opens the walkthrough on a new install, once the Nook is up.
    func showIfNew() {
        guard !UserDefaults.standard.bool(forKey: Self.seenKey) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in self?.show() }
    }

    /// Opens Settings on the walkthrough. It asks for nothing.
    func show(_ page: WelcomePage = .notch) {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        self.page = page
        SettingsWindowController.shared.show(.welcome)
    }
}

struct WelcomeSettingsPane: View {
    @ObservedObject private var model = WelcomeGuide.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var keys = NookHotKeys.shared
    @ObservedObject private var tape = TapeFeature.shared
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var nook = NookSettings.shared
    @ObservedObject private var navigation = SettingsNavigationModel.shared

    var body: some View {
        SettingsPage(title: "Welcome", subtitle: "How to use MacSpaces, a page at a time.") {
            tabs
            card
        }
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 14) {
                mark(model.page, size: 30)
                    .frame(width: 52, height: 52)
                    .background(theme.settings.selected, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.page.title).font(.system(size: 22, weight: .bold))
                    Text(model.page.headline).foregroundStyle(.secondary)
                }
            }
            ForEach(Array(steps(model.page).enumerated()), id: \.offset) { index, step in
                instruction(index + 1, step.0, step.1)
                if model.page == .heartable, index == 2 {
                    // Under "Pick a look": it changes the Nook at once, so each can be seen.
                    SettingsSegmentedPicker("Look", selection: $options.musicLook, options: MusicLook.allCases) { $0.title }
                        .fixedSize()
                        .padding(.leading, 38)
                }
            }
            ForEach(notes(model.page), id: \.self) { note in
                Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Rectangle().fill(theme.settings.border).frame(height: 1)
            footer
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.settings.tile, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(theme.settings.border, lineWidth: 1)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.settings.accent.opacity(navigation.searchTarget == WelcomeGuide.card ? 0.65 : 0), lineWidth: 1.5)
        }
        .id("settings." + WelcomeGuide.card)
        .animation(theme.reduceMotion ? nil : Design.spring(), value: model.page)
    }

    /// The pages along the top, each wearing its mark as the sidebar does.
    private var tabs: some View {
        HStack(spacing: 6) {
            ForEach(WelcomePage.allCases) { page in
                Button { model.page = page } label: {
                    HStack(spacing: 6) {
                        mark(page, size: 13).frame(width: 16)
                        Text(page.title).font(.system(size: 12, weight: model.page == page ? .semibold : .medium))
                    }
                    .padding(.horizontal, 10).frame(height: 28)
                    .background(model.page == page ? theme.settings.selected : Color.clear, in: Capsule())
                    .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.page == page ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func mark(_ page: WelcomePage, size: CGFloat) -> some View {
        switch page {
        case .notch: Image(systemName: "macbook.gen2").font(.system(size: size * 0.9, weight: .semibold))
        case .heartable: Image(systemName: "heart.fill").font(.system(size: size, weight: .semibold))
        case .tape: Image(nsImage: TapeMark.image(size: size * 1.3)).renderingMode(.template)
        case .tsukumo: TsukumoGlyph(size: size * 1.3)
        case .folio: Image(systemName: "tray.full.fill").font(.system(size: size * 0.9, weight: .semibold))
        }
    }

    private func instruction(_ number: Int, _ title: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)").font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .frame(width: 26, height: 26).background(theme.settings.selected, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var findAction: String {
        keys.shortcut == .off ? "Find Action in the MacSpaces menu" : "Find Action (\(keys.shortcut.title))"
    }

    /// As this copy is set up: hover opens the Nook unless it was turned off.
    private var opening: String {
        (nook.expandOnHover ? "Rest the pointer on the notch, or click it." : "Click the notch.")
            + " Hover, scrolling down and file drags are in Settings, General."
    }

    private func steps(_ page: WelcomePage) -> [(String, String)] {
        switch page {
        case .notch:
            return [("Open it", opening),
                    ("Move between pages", "The dock under the Nook switches pages: Music, Calendar, Weather and the rest, with Home last. The gear at its end opens Settings, and so does the MacSpaces menu in the menu bar. Choose the pages in Settings, Dock."),
                    ("Make Home yours", "Home is a grid of widgets: music, timers, the clock and more. Add, remove and arrange them in Settings, Home."),
                    ("Beside the notch", "With the notch closed, the playing song, a running timer and more show on either side. Choose them in Settings, Activities.")]
        case .heartable:
            return [("Play a song", "Play anything in Spotify or Apple Music, and the Music page shows it with lyrics in time."),
                    ("Change songs", "Swipe sideways with two fingers on the notch for the next or previous song."),
                    ("Pick a look", "Try them here: Standard shows the cover and lyrics, Vinyl a turning ASCII record, Shelf your covers and a record player. Right-click the Music page to switch any time."),
                    ("Connect Spotify", "For the Shelf, your stats and playlist backups, connect it in Settings, Heartable.")]
        case .tape:
            return [("Turn on Tape", "Tape moves, resizes and focuses windows, so macOS asks for Accessibility when you turn it on, and never before. It arranges normal windows on each display and desktop you leave on."),
                    ("Choose your apps", "In Tape's menu-bar menu, Managed Windows, Choose Apps. Uncheck apps you want to leave alone, or manage only the windows you check."),
                    ("Choose a window", "Click any app in the Dock or its window, or use Go to Window in Tape's menu. Keyboard: ⌃⌥← and ⌃⌥→. Hold ⌃⌥ and scroll sideways with two fingers to browse without switching apps."),
                    ("Make room", "Width in Tape's menu sizes the column. Float a window (⌃⌥F) to place it freely, or move it to the next display. Pause and Restore puts back the windows Tape arranged.")]
        case .tsukumo:
            return [("Pick your agent", "Wisp's eyes, or KemoSabe in any of its looks, in Settings, Tsukumo."),
                    ("Ask in plain words", "On its page in the Nook: reminders, notes, timers, focus and your day. It answers with Apple's on-device model, or Claude with your own login or key."),
                    ("KemoSabe, the gateway", "A cloud model never sees your calendar. Turn on Share when you're free and KemoSabe tells it only when you're free, showing each answer in the chat."),
                    ("Coding agents", "A bubble beside the notch when Claude Code or Codex needs you; click it to open that session."),
                    ("Give it a voice", "Replies can be read aloud in a Mac voice, or in one made from your own recordings in Studio's Voices. The voice models download only when you choose them in Settings, Tsukumo.")]
        case .folio:
            return [("Hold files at the notch", "Drag files to the notch and they wait in the Tray until you drag them out or AirDrop them together. Removing one never touches the file."),
                    ("Clipboard history", "⇧⌘C shows what you've copied, to search and paste again. Passwords and other secrets are left out."),
                    ("Convert by Shift-dragging", "Hold Shift while dragging a file for a wheel of formats. Copies are saved beside the original."),
                    ("Baskets and search", "Park a basket anywhere from the MacSpaces menu. Folio's search finds words inside pictures and PDFs, in every list.")]
        }
    }

    private func notes(_ page: WelcomePage) -> [String] {
        switch page {
        case .notch:
            return ["\(findAction) searches every page, setting and action.",
                    "MacSpaces counts each copy anonymously: a random ID and the version."]
        case .tape:
            return ["Turn off Stage Manager and macOS window tiling, and pause other window managers, so they don't fight over window positions. Each desktop has its own switch in Settings, Tape."]
        default:
            return []
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if let previous = WelcomePage(rawValue: model.page.rawValue - 1) {
                Button("Back") { model.page = previous }.buttonStyle(.settings())
            }
            Spacer()
            if model.page == .tape {
                if tape.isOn {
                    Label("Tape is on", systemImage: "checkmark.circle.fill").foregroundStyle(.secondary)
                } else {
                    // The explicit action that asks for Accessibility.
                    Button("Turn On Tape") { tape.setOn(true) }.buttonStyle(.settings())
                }
            }
            if let destination = model.page.destination {
                Button("Open \(model.page.title) Settings") { navigation.open(destination) }
                    .buttonStyle(.settings())
            }
            if let next = WelcomePage(rawValue: model.page.rawValue + 1) {
                Button("Next") { model.page = next }.buttonStyle(.settings(.primary)).keyboardShortcut(.defaultAction)
            } else {
                // The walkthrough stays in the sidebar; Done goes on to General.
                Button("Done") { model.page = .notch; navigation.open(.general) }
                    .buttonStyle(.settings(.primary)).keyboardShortcut(.defaultAction)
            }
        }
    }
}
