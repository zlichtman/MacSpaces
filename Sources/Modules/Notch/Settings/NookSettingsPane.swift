import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GeneralSettingsPane: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingResetConfirmation = false

    var body: some View {
        SettingsPage(title: "General", subtitle: "When and where the Nook opens, keyboard shortcuts, and updates.") {
            SoftwareUpdateCard()
            SettingsCard("Startup", systemImage: "power") {
                Toggle("Enable Nook", isOn: $app.notchEnabled)
                Toggle("Launch at login", isOn: $app.launchAtLogin)
            }
            SettingsCard("Displays", systemImage: "display") {
                DisplayTargetPicker(mode: $settings.displayMode,
                    selectedIDs: $settings.selectedDisplayIDs, preferBuiltIn: true)
            }
            SettingsCard("Open & close", systemImage: "cursorarrow.motionlines") {
                Toggle("Open on hover", isOn: $settings.expandOnHover)

                if settings.expandOnHover {
                    SettingsSlider(
                        title: "Hover delay",
                        value: $settings.hoverDelay,
                        range: 0...1,
                        valueText: String(format: "%.2f s", settings.hoverDelay)
                    )
                }

                Toggle("Open by scrolling down on the notch", isOn: $settings.scrollGesturesEnabled)
                Toggle("Open Tray when dragging files to the notch", isOn: $settings.openTrayOnFileDrag)
                Text("Click the notch to open it. Hover, scroll and file-drag gestures are optional.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Keyboard", systemImage: "keyboard") {
                NookKeyboardSettings()
            }
            SettingsCard("Hide in apps", systemImage: "eye.slash") {
                Text("The Nook steps away while one of these apps is in front, such as a game or a presentation.")
                    .font(.caption).foregroundStyle(.secondary)
                ForEach(settings.hiddenInApps, id: \.self) { bundleID in
                    HStack(spacing: 8) {
                        AppIcon(bundleID: bundleID).frame(width: 18, height: 18)
                        Text(NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
                                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? bundleID)
                            .lineLimit(1)
                        Spacer()
                        Button { settings.hiddenInApps.removeAll { $0 == bundleID } } label: {
                            Image(systemName: "minus.circle.fill").foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain).accessibilityLabel("Remove")
                    }
                }
                Button("Add App…") {
                    let panel = NSOpenPanel()
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowedContentTypes = [.application]
                    panel.allowsMultipleSelection = true
                    guard panel.runModal() == .OK else { return }
                    for url in panel.urls {
                        if let id = Bundle(url: url)?.bundleIdentifier, !settings.hiddenInApps.contains(id) { settings.hiddenInApps.append(id) }
                    }
                }
            }

            HStack {
                Button("Reset all Nook settings…", role: .destructive) {
                    showingResetConfirmation = true
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.top, 4)
            .id("settings.Reset Nook")
        }
        .alert("Reset Nook?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                theme.reset()
                app.notchEnabled = true
            }
        } message: {
            Text("This removes widget profiles and restores the default appearance, size, displays and behavior. Your notes and tray files are kept.")
        }
    }
}

/// The Activities page: what shows beside the closed notch, and in cards under it.
/// The dock's app pages have their own page, Apps.
struct ActivitiesSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var agents = AgentActivityMonitor.shared
    @ObservedObject private var messages = AppServices.shared.messages
    @ObservedObject private var feed = SystemNotificationsFeed.shared
    @ObservedObject private var banners = NotchBanners.shared

    var body: some View {
        SettingsPage(title: "Activities", subtitle: "Choose what shows beside the closed notch, and in cards under it.") {
            SettingsCard("Beside the notch", systemImage: "rectangle.topthird.inset.filled") {
                group("Music, timers & power")
                Toggle("Now Playing", isOn: $settings.showMusicLiveActivity)
                Toggle("Running timer", isOn: $settings.showTimerLiveActivity)
                Toggle("Upcoming video meeting", isOn: $settings.showMeetingLiveActivity)
                    .help("Counts down from ten minutes before a meeting with a video link. Uses Calendar access only if you've already allowed it.")
                Toggle("Power and low-battery alerts", isOn: $settings.showPowerLiveActivity)
                    .help("Shows the battery level when you plug in or unplug, and warns at low battery or when the charger can't keep up.")
                Divider()
                group("Clipboard & Tray")
                Toggle("Paste queue count", isOn: $settings.showPasteQueueLiveActivity)
                    .help("How many queued clips are left to paste. The queue keeps working when this is off.")
                Toggle("New screenshot thumbnail", isOn: $settings.showScreenshotLiveActivity)
                    .help("A thumbnail of a screenshot just added to the Tray (Settings → Files). Screenshots are still added when this is off.")
                Divider()
                group("System controls")
                Toggle("Microphone mute", isOn: $settings.showMicrophoneLiveActivity)
                Toggle("Focus mode", isOn: $settings.showFocusLiveActivity)
                Text("These appear briefly. Volume and brightness use macOS's own indicators.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SettingsCard("Under the notch", systemImage: "bell.badge") {
                Toggle("New Messages", isOn: Binding(
                    get: { messages.incomingEnabled }, set: { messages.setIncomingEnabled($0) }))
                Toggle("Other apps' notifications", isOn: Binding(
                    get: { feed.isEnabled }, set: { feed.setEnabled($0) }))
                Toggle("Show what they say", isOn: $banners.showsText)
                    .help("Off shows only who or which app it's from.")
                Toggle("Coding agents that need you", isOn: Binding(
                    get: { agents.isEnabled }, set: { agents.setEnabled($0) }))
                    .help("Follows Claude Code and Codex sessions: they're listed in the Terminal page's Agents tab, and a card appears when one needs you. MacSpaces adds one silent hook to ~/.claude/settings.json and ~/.codex/hooks.json (your own hooks are kept, and a backup is saved); turning this off removes it.")
                Divider()
                Picker("When a message or agent needs you", selection: $banners.delivery) {
                    ForEach(NotificationRoute.Delivery.allCases) { Text($0.title).tag($0) }
                }
                Text(banners.delivery == .openPage
                     ? "A new message opens the Messages page on that conversation (click once to type a reply); an agent that needs you opens the Terminal page's Agents tab on that session. It closes after a few seconds unless you move in. While you're using the Nook, a card slides down instead, and clicking it goes to the same place."
                     : "A card slides down under the camera; clicking it opens the conversation or the agent's session in the Nook, Reply answers right in the card and Go brings the agent's app forward.")
                    .font(.caption).foregroundStyle(.secondary)
                Text("Other apps' notifications are cards that open their page or app. Nothing shows while your Mac is locked or a Hide in app is in front, and none of it appears in screen sharing or recordings. Messages and notifications are read on your Mac only and need Full Disk Access.")
                    .font(.caption).foregroundStyle(.secondary)
                if messages.incomingNeedsAccess || feed.needsAccess {
                    Button("Open Full Disk Access Settings") { messages.openIncomingAccessSettings() }
                }
                if !feed.status.isEmpty, feed.isEnabled { Text(feed.status).font(.caption).foregroundStyle(.secondary) }
                if messages.incomingEnabled { Text(messages.incomingStatus).font(.caption).foregroundStyle(.secondary) }
                if let error = agents.error { Text(error).font(.caption).foregroundStyle(.red) }
            }
        }
    }

    private func group(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

/// The Files page: what reaches the Tray on its own, and the File Converter.
struct FilesSettingsPane: View {
    @ObservedObject private var screenshots = ScreenshotWatcher.shared
    @ObservedObject private var app = AppSettings.shared

    var body: some View {
        SettingsPage(title: "Files", subtitle: "What lands in the Tray by itself, and converting files.") {
            SettingsCard("Screenshots", systemImage: "camera.viewfinder") {
                Toggle("Add new screenshots to the Tray", isOn: Binding(
                    get: { screenshots.isEnabled }, set: { screenshots.setEnabled($0) }))
                Text("Each screenshot waits in the Tray, ready to drag into an email, AirDrop, copy, or turn into text. The file stays where macOS saves it. If that's the Desktop, macOS asks once for access. Whether a thumbnail shows beside the notch is under Activities.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard("Downloads & folders", systemImage: "tray.and.arrow.down") {
                CompletedDownloadsSettings()
            }
            SettingsCard("File Converter", systemImage: "arrow.triangle.2.circlepath") {
                Toggle("Convert files by Shift-dragging", isOn: $app.fileConverterEnabled)
                Button("Open File Tools") { FileToolsWindow.shared.show() }
                Toggle("Reveal results in Finder automatically", isOn: Binding(get: { UserDefaults.standard.bool(forKey: "converter.revealResults") }, set: { UserDefaults.standard.set($0, forKey: "converter.revealResults") }))
                Text("Hold Shift while dragging a file for a wheel of formats; Option-Shift shows tools such as compress and remove metadata. Copies are saved beside the original, and nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct NookKeyboardSettings: View {
    @ObservedObject private var keys = NookHotKeys.shared
    var body: some View {
        Picker("Find Action", selection: $keys.shortcut) { ForEach(NookHotKeys.Shortcut.allCases) { Text($0.title).tag($0) } }
        Toggle("Direct page shortcuts", isOn: $keys.directPages)
        if keys.directPages { Text("⌃⌥N Home · ⌃⌥T Tray · ⌃⌥M Music · ⌃⌥K Terminal · ⌃⌥D Dictation").font(.caption).foregroundStyle(.secondary) }
        if let problem = keys.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
        Button("Find an Action") { ActionSearchWindow.shared.show() }
    }
}
