import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct OpenCloseCard: View {
    @ObservedObject private var settings = NookSettings.shared

    var body: some View {
        SettingsCard("Opening", systemImage: "cursorarrow.motionlines") {
            // The three ways in side by side, so the card stays short; the delay belongs to Hover.
            HStack(alignment: .top, spacing: 16) {
                toggle("Hover", "Rest the pointer on the notch.", $settings.expandOnHover)
                toggle("Scroll", "Scroll down on the notch.", $settings.scrollGesturesEnabled)
                toggle("Drag Files", "Drag files to open the Tray.", $settings.openTrayOnFileDrag)
            }

            if settings.expandOnHover {
                SettingsSlider(
                    title: "Hover Delay",
                    value: $settings.hoverDelay,
                    range: 0...1,
                    valueText: String(format: "%.2f s", settings.hoverDelay)
                )
            }

            SettingsCaption("A click on the notch always opens it.")
        }
    }

    private func toggle(_ title: String, _ detail: String, _ isOn: Binding<Bool>) -> some View {
        Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The Status icon's switch and what its ring shows.
struct StatusIconCard: View {
    @ObservedObject private var feature = StatusIconFeature.shared

    var body: some View {
        SettingsCard(StatusIconFeature.card, systemImage: "gauge.medium") {
            Toggle("Show a Status Icon in the Menu Bar", isOn: Binding(get: { feature.isOn }, set: { feature.setOn($0) }))
            if feature.isOn {
                SettingsSegmentedPicker("Ring", selection: $feature.reading, options: StatusGauge.available(feature.snapshot)) { $0.title }
                    .fixedSize()
                SettingsSegmentedPicker("Size", selection: $feature.size, options: StatusIconFeature.Size.allCases) { $0.title }
                    .fixedSize()
                Toggle("Show the Number", isOn: $feature.showsValue)
                Toggle("Open on Hover", isOn: $feature.opensOnHover)
            }
            SettingsCaption("One icon in place of three: your battery as a ring, Wi-Fi in the middle, the volume beside it.")
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
            StatusIconCard()

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

            HStack(spacing: 8) {
                Button("Reset MacSpaces", role: .destructive) {
                    showingResetConfirmation = true
                }
                .buttonStyle(.settings(.destructive))
                Button("Run Onboarding") { WelcomeGuide.shared.show(.notch) }
                    .buttonStyle(.settings())
                Spacer()
            }
            .padding(.top, 4)
            .id("settings.Reset MacSpaces")
        }
        .alert("Reset MacSpaces?", isPresented: $showingResetConfirmation) {
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
