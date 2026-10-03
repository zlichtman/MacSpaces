import SwiftUI

struct GeneralSettingsPane: View {
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

    var body: some View {
        SettingsPage(title: "Activities", subtitle: "Choose what appears beside the closed notch.") {
            SettingsCard("Live activities", systemImage: "waveform.path.ecg") {
                Text("Music, timers & power")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Now Playing", isOn: $settings.showMusicLiveActivity)
                Toggle("Running timer", isOn: $settings.showTimerLiveActivity)
                Toggle("Power and low-battery alerts", isOn: $settings.showPowerLiveActivity)

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
        }
    }
}
