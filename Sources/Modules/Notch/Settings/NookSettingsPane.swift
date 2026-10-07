import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct GeneralSettingsPane: View {
    @ObservedObject private var screenshots = ScreenshotWatcher.shared
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingResetConfirmation = false

    var body: some View {
        SettingsPage(title: "General", subtitle: "Choose when and where your Nook appears, and how MacSpaces updates.") {
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
            SettingsCard("Downloads & folders", systemImage: "tray.and.arrow.down") {
                CompletedDownloadsSettings()
            }
            SettingsCard("Screenshots", systemImage: "camera.viewfinder") {
                Toggle("Add new screenshots to the Tray", isOn: Binding(
                    get: { screenshots.isEnabled }, set: { screenshots.setEnabled($0) }))
                Text("Each screenshot appears beside the notch for a moment and waits in the Tray, ready to drag into an email, AirDrop, copy, or turn into text. The file stays where macOS saves it. If that's the Desktop, macOS asks once for access.")
                    .font(.caption).foregroundStyle(.secondary)
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

            SettingsCard("File Converter", systemImage: "arrow.triangle.2.circlepath") {
                Toggle("Convert files by Shift-dragging", isOn: $app.fileConverterEnabled)
                Button("Open File Tools") { FileToolsWindow.shared.show() }
                Toggle("Reveal results in Finder automatically", isOn: Binding(get: { UserDefaults.standard.bool(forKey: "converter.revealResults") }, set: { UserDefaults.standard.set($0, forKey: "converter.revealResults") }))
                Text("Hold Shift while dragging a file for a wheel of formats; Option-Shift shows tools such as compress and remove metadata. Copies are saved beside the original, and nothing leaves your Mac.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Motion", systemImage: "sparkles") {
                Toggle("Reduce motion", isOn: $theme.reduceMotionPreference)
                Toggle("Trackpad haptics", isOn: $theme.hapticsEnabled)
            }
            SoftwareUpdateCard()
            HStack {
                Button("Reset all Nook settings…", role: .destructive) {
                    showingResetConfirmation = true
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(.top, 4)
        }
        .alert("Reset Nook?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                theme.reset(.notch)
                app.notchEnabled = true
            }
        } message: {
            Text("This removes widget profiles and restores the default appearance, size, displays and behavior. Your notes and tray files are kept.")
        }
    }
}

struct ActivitiesSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var agents = AgentActivityMonitor.shared
    @ObservedObject private var messages = AppServices.shared.messages
    @ObservedObject private var feed = SystemNotificationsFeed.shared
    @ObservedObject private var banners = NotchBanners.shared

    var body: some View {
        SettingsPage(title: "Activities", subtitle: "Choose what appears beside the closed notch.") {
            SettingsCard("Live activities", systemImage: "waveform.path.ecg") {
                Text("Music, timers & power")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Now Playing", isOn: $settings.showMusicLiveActivity)
                Toggle("Running timer", isOn: $settings.showTimerLiveActivity)
                Toggle("Upcoming video meeting", isOn: $settings.showMeetingLiveActivity)
                    .help("Counts down from ten minutes before a meeting with a video link. Uses Calendar access only if you've already allowed it.")
                Toggle("Power and low-battery alerts", isOn: $settings.showPowerLiveActivity)

                Divider()

                Text("Clipboard & Tray")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Paste queue count", isOn: $settings.showPasteQueueLiveActivity)
                    .help("How many queued clips are left to paste. The queue keeps working when this is off.")
                Toggle("New screenshot in Tray", isOn: $settings.showScreenshotLiveActivity)
                    .help("A thumbnail of a screenshot just added to the Tray. Screenshots are still added when this is off.")

                Divider()

                Text("System controls")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Microphone mute", isOn: $settings.showMicrophoneLiveActivity)
                Toggle("Focus mode", isOn: $settings.showFocusLiveActivity)

                Text("These appear briefly. Volume and brightness use macOS's own indicators.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Notifications", systemImage: "bell.badge") {
                Toggle("Show new Messages in the notch", isOn: Binding(
                    get: { messages.incomingEnabled }, set: { messages.setIncomingEnabled($0) }))
                Toggle("Show other apps' notifications in the notch", isOn: Binding(
                    get: { feed.isEnabled }, set: { feed.setEnabled($0) }))
                Toggle("Show what they say", isOn: $banners.showsText)
                    .help("Off shows only who or which app it's from.")
                Text("A card slides down under the camera with the message or notification; Reply opens the conversation. Cards never appear in screen sharing or recordings, or while your Mac is locked. Both read on your Mac only and need Full Disk Access.")
                    .font(.caption).foregroundStyle(.secondary)
                if messages.incomingNeedsAccess || feed.needsAccess {
                    Button("Open Full Disk Access Settings") { messages.openIncomingAccessSettings() }
                }
                if !feed.status.isEmpty, feed.isEnabled { Text(feed.status).font(.caption).foregroundStyle(.secondary) }
                if messages.incomingEnabled { Text(messages.incomingStatus).font(.caption).foregroundStyle(.secondary) }
            }

            SettingsCard("Coding agents", systemImage: "sparkle") {
                Toggle("Show Claude Code and Codex beside the notch", isOn: Binding(
                    get: { agents.isEnabled }, set: { agents.setEnabled($0) }))
                Text("Shows when an agent is working, needs you, or has just finished. MacSpaces adds one silent hook to ~/.claude/settings.json and ~/.codex/hooks.json (your own hooks are kept, and a backup is saved); turning this off removes it.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if let error = agents.error { Text(error).font(.caption).foregroundStyle(.red) }
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
