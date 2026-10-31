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
                        SettingsRemoveButton { settings.hiddenInApps.removeAll { $0 == bundleID } }
                    }
                }
                Button("Add App") {
                    let panel = NSOpenPanel()
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    panel.allowedContentTypes = [.application]
                    panel.allowsMultipleSelection = true
                    SettingsWindowController.shared.runPanel(panel) { chosen in
                        guard chosen else { return }
                        for url in panel.urls {
                            if let id = Bundle(url: url)?.bundleIdentifier, !settings.hiddenInApps.contains(id) { settings.hiddenInApps.append(id) }
                        }
                    }
                }
                .buttonStyle(.settings())
            }

            HStack {
                Button("Reset all Nook settings", role: .destructive) {
                    showingResetConfirmation = true
                }
                .buttonStyle(.settings(.destructive))
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

/// The Activities page: what shows beside the closed notch. Nothing drops down under
/// it; the dock's app pages have their own page, Apps.
struct ActivitiesSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var agents = AgentActivityMonitor.shared

    var body: some View {
        SettingsPage(title: "Activities", subtitle: "Choose what shows beside the closed notch.") {
            SettingsCard("Look", systemImage: "circle.dashed") {
                SettingsSegmentedPicker("Closed notch", selection: $settings.notchLook,
                                        options: [.solid, .clear]) { $0 == .solid ? "Solid" : "Clear" }
                Text(settings.notchLook == .solid
                     ? "A black notch, with activities beside the camera on it."
                     : "Nothing drawn around the camera. Each activity is its own bubble beside it, like the agent bubble.")
                    .font(.caption).foregroundStyle(.secondary)
                if settings.notchLook == .clear {
                    Toggle("Faint pill on displays without a camera", isOn: $settings.notchlessHint)
                        .help("Something to point at on external displays while nothing is showing. Off leaves the top of those displays clear.")
                }
            }
            SettingsCard("Beside the notch", systemImage: "rectangle.topthird.inset.filled") {
                group("Music, timers & power")
                Toggle("Now Playing", isOn: $settings.showMusicLiveActivity)
                Toggle("Running timer", isOn: $settings.showTimerLiveActivity)
                Toggle("Keep Awake", isOn: $settings.showKeepAwakeLiveActivity)
                    .help("A cup while Keep Awake is on, with the time left when it has a limit.")
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
                Divider()
                group("Coding agents")
                Toggle("Coding agents that need you", isOn: Binding(
                    get: { agents.isEnabled }, set: { agents.setEnabled($0) }))
                    .help("MacSpaces adds one silent hook to ~/.claude/settings.json and ~/.codex/hooks.json (your own hooks are kept, and a backup is saved); turning this off removes it.")
                Text("Follows Claude Code and Codex sessions in the Terminal page's Agents tab. When one needs you, a bubble with its app's icon slides out beside the notch and pulses until it's working again; click it to open that session. It never covers your windows, waits while your Mac is locked or a Hide in app is in front, and doesn't appear in screen sharing or recordings.")
                    .font(.caption).foregroundStyle(.secondary)
                if let error = agents.error { Text(error).font(.caption).foregroundStyle(.red) }
                if agents.isEnabled {
                    Toggle("Show the bubble while agents work", isOn: Binding(
                        get: { agents.peekWhileWorking }, set: { agents.setPeekWhileWorking($0) }))
                        .help("The bubble also sits beside the notch while any agent works, showing its app with a soft pulse, and ticks for a moment when one finishes. Off, it appears only when an agent needs you.")
                    Toggle("Answer permission requests in MacSpaces", isOn: Binding(
                        get: { agents.answersEnabled }, set: { agents.setAnswersEnabled($0) }))
                    Text("When an agent asks to run a command or edit a file, Allow and Deny appear in Agents (and the bubble's menu). Each answer covers that one request. Unanswered after \(Int(AgentActivityMonitor.answerWait)) seconds, or with Answer in App, the agent's own prompt takes over.")
                        .font(.caption).foregroundStyle(.secondary)
                    CodexHookNotice(inSettings: true)
                }
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
                Button("Open File Tools") { FileToolsWindow.shared.show() }.buttonStyle(.settings())
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
        Button("Find an Action") { ActionSearchWindow.shared.show() }.buttonStyle(.settings())
    }
}
