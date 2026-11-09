import SwiftUI
import AppKit

/// The walkthrough: a page for the notch and one for each app inside MacSpaces, with Tape's own
/// guide on its page (the Tape app's "How to Use Tape", folded in). It opens by itself once, on a
/// new install; the MacSpaces menu and Tape's menu open it any time.
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
final class WelcomeWindow: NSObject, ObservableObject, NSWindowDelegate {
    static let shared = WelcomeWindow()
    /// Set once the walkthrough has opened, or at first launch for anyone already using MacSpaces.
    static let seenKey = "welcome.seen"

    @Published var page: WelcomePage = .notch
    private var window: NSWindow?

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

    func show(_ page: WelcomePage = .notch) {
        UserDefaults.standard.set(true, forKey: Self.seenKey)
        self.page = page
        if window == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 640, height: 560),
                                  styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            window.title = "Welcome to MacSpaces"
            window.titlebarAppearsTransparent = true
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.contentView = NSHostingView(rootView: WelcomeView(model: self))
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func close() { window?.close() }
}

struct WelcomeView: View {
    @ObservedObject var model: WelcomeWindow
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var keys = NookHotKeys.shared
    @ObservedObject private var tape = TapeFeature.shared
    @ObservedObject private var options = WidgetOptions.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            tabs.padding(.top, 34).padding(.horizontal, 28)
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 14) {
                        mark(model.page, size: 30)
                            .frame(width: 52, height: 52)
                            .background(theme.settings.tile, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                    if let note = note(model.page) {
                        Text(note).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(28)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            Divider()
            footer.padding(.horizontal, 28).padding(.vertical, 16)
        }
        .frame(width: 640, height: 560)
        .foregroundStyle(theme.settingsForeground)
        .background(theme.settings.surface)
        .animation(theme.reduceMotion ? nil : Design.spring(), value: model.page)
    }

    /// The pages along the top, each wearing its mark as Settings does.
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
                .frame(width: 26, height: 26).background(theme.settings.tile, in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(text).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var findAction: String {
        keys.shortcut == .off ? "Find Action in the MacSpaces menu" : "Find Action (\(keys.shortcut.title))"
    }

    private func steps(_ page: WelcomePage) -> [(String, String)] {
        switch page {
        case .notch:
            return [("Open it", "Click the notch. Opening on hover or by scrolling down are in Settings, General."),
                    ("Move between pages", "The dock along the bottom switches pages: Home's widgets, Music, Calendar, Timers and the rest. Choose them in Settings, Dock."),
                    ("Find anything", "\(findAction) searches every page, setting and action."),
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
                    ("Ask in plain words", "On its page in the Nook: reminders, notes, timers, focus and your day. It answers with Apple's on-device model, or your own Claude or OpenAI key."),
                    ("KemoSabe, the gateway", "A cloud model never sees your calendar. Turn on Share when you're free and KemoSabe tells it only when you're free, showing each answer in the chat."),
                    ("Coding agents", "A bubble beside the notch when Claude Code or Codex needs you; click it to open that session.")]
        case .folio:
            return [("Hold files at the notch", "Drag files to the notch and they wait in the Tray until you drag them out or AirDrop them together. Removing one never touches the file."),
                    ("Clipboard history", "⇧⌘C shows what you've copied, to search and paste again. Passwords and other secrets are left out."),
                    ("Convert by Shift-dragging", "Hold Shift while dragging a file for a wheel of formats. Copies are saved beside the original."),
                    ("Baskets and search", "Park a basket anywhere from the MacSpaces menu. Folio's search finds words inside pictures and PDFs, in every list.")]
        }
    }

    private func note(_ page: WelcomePage) -> String? {
        page == .tape ? "Turn off Stage Manager and macOS window tiling, and pause other window managers, so they don't fight over window positions. Each desktop has its own switch in Settings, Tape." : nil
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
                Button("Open \(model.page.title) Settings") { SettingsWindowController.shared.show(destination) }
                    .buttonStyle(.settings())
            }
            if let next = WelcomePage(rawValue: model.page.rawValue + 1) {
                Button("Next") { model.page = next }.buttonStyle(.settings(.primary)).keyboardShortcut(.defaultAction)
            } else {
                Button("Done") { model.close() }.buttonStyle(.settings(.primary)).keyboardShortcut(.defaultAction)
            }
        }
    }
}
