import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OpenCloseCard: View {
    @ObservedObject private var settings = NookSettings.shared

    var body: some View {
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
            SettingsCaption("Click the notch to open it. Hover, scroll and file-drag gestures are optional.")
        }
    }
}

struct GeneralSettingsPane: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingResetConfirmation = false

    var body: some View {
        SettingsPage(title: "General", subtitle: "Updates, when and where the Nook opens, and keyboard shortcuts.") {
            // Updates first, so a waiting update is the first thing General shows (owner, 4.03).
            SoftwareUpdateCard()
            SettingsCard("Startup", systemImage: "power") {
                Toggle("Enable Nook", isOn: $app.notchEnabled)
                Toggle("Launch at login", isOn: $app.launchAtLogin)
            }
            SettingsCard("Displays", systemImage: "display") {
                DisplayTargetPicker(mode: $settings.displayMode,
                    selectedIDs: $settings.selectedDisplayIDs, preferBuiltIn: true)
            }
            OpenCloseCard()

            SettingsDrawerCard("Keyboard", systemImage: "keyboard", openKey: WidgetOptions.Keys.nookKeyboardDrawer) {
                NookKeyboardSettings()
            }
            SettingsDrawerCard("Hide in apps", systemImage: "eye.slash", openKey: WidgetOptions.Keys.hideInAppsDrawer) {
                SettingsCaption("The Nook steps away while one of these apps is in front, such as a game.")
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

/// The Activities page: what shows beside the closed notch, and how those bubbles look. Nothing
/// drops down under it; the dock's app pages have their own page, Dock.
struct ActivitiesSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var spaces = AppServices.shared.spaces

    var body: some View {
        SettingsPage(title: "Activities", subtitle: "What shows beside the closed notch.") {
            SettingsCard("Beside the notch", systemImage: "rectangle.topthird.inset.filled") {
                group("Music, timers & power")
                Toggle("Now Playing", isOn: $settings.showMusicLiveActivity)
                Toggle("Running timer", isOn: $settings.showTimerLiveActivity)
                Toggle("Keep Awake", isOn: $settings.showKeepAwakeLiveActivity)
                    .help("A cup while Keep Awake is on, with the time left when it has a limit.")
                Toggle("Upcoming video meeting", isOn: $settings.showMeetingLiveActivity)
                    .help("Counts down from ten minutes before a meeting with a video link. Uses Calendar access only if you've already allowed it.")
                Toggle("Battery warnings", isOn: $settings.showPowerLiveActivity)
                    .help("Warns at low battery or when the charger can't keep up.")
                Divider()
                group("Clipboard & Tray")
                Toggle("Paste queue count", isOn: $settings.showPasteQueueLiveActivity)
                    .help("How many queued clips are left to paste. The queue keeps working when this is off.")
                Toggle("New screenshot thumbnail", isOn: $settings.showScreenshotLiveActivity)
                    .help("A thumbnail of a screenshot just added to the Tray (Settings → Folio). Screenshots are still added when this is off.")
                Divider()
                group("System controls")
                Toggle("Microphone mute", isOn: $settings.showMicrophoneLiveActivity)
                Toggle("Focus mode", isOn: $settings.showFocusLiveActivity)
                if !spaces.isUnavailable {
                    Toggle("Desktop changes", isOn: $settings.showSpacesLiveActivity)
                        .help("The desktop's number and name for a moment after you move to another one.")
                }
                SettingsCaption("These appear briefly. Volume and brightness use macOS's own indicators.")
            }
            ClosedNotchCard()
        }
    }

    private func group(_ title: String) -> some View {
        Text(title).font(.caption.weight(.semibold)).foregroundStyle(.secondary)
    }
}

private struct NookKeyboardSettings: View {
    @ObservedObject private var keys = NookHotKeys.shared
    var body: some View {
        Picker("Find Action", selection: $keys.shortcut) { ForEach(NookHotKeys.Shortcut.allCases) { Text($0.title).tag($0) } }
        Toggle("Direct page shortcuts", isOn: $keys.directPages)
        if keys.directPages { SettingsCaption("⌃⌥N Home · ⌃⌥T Folio · ⌃⌥M Music · ⌃⌥K Terminal · ⌃⌥D Dictate") }
        if let problem = keys.problem { Text(problem).font(.caption).foregroundStyle(.orange) }
        Button("Find an Action") { ActionSearchWindow.shared.show() }.buttonStyle(.settings())
    }
}
