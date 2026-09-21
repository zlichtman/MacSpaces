import SwiftUI

struct GeneralSettingsPane: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingResetConfirmation = false

    var body: some View {
        SettingsPage(title: "General", subtitle: "Choose when and where your Nook appears.") {
            SettingsCard("MacSpaces", systemImage: "power") {
                Toggle("Enable Nook", isOn: $app.notchEnabled)
                Toggle("Launch at login", isOn: $app.launchAtLogin)
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
                Text("Click the notch to open it at any time. Scrolling inside an open Nook stays with the widgets.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Displays", systemImage: "display") {
                DisplayTargetPicker(mode: $settings.displayMode,
                    selectedIDs: $settings.selectedDisplayIDs, preferBuiltIn: true)
            }
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

struct NookSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared

    var body: some View {
        SettingsPage(title: "Widgets", subtitle: "Arrange your Nook. Save a different setup for each part of your day.") {
            SettingsCard("Profile", systemImage: "rectangle.3.group") {
                HStack {
                    Picker("Active profile", selection: $settings.activeProfileID) {
                        ForEach(settings.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)

                    TextField(
                        "Profile name",
                        text: Binding(
                            get: { settings.activeProfile.name },
                            set: { settings.renameProfile(settings.activeProfile, to: $0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Menu {
                        Button("New Empty Profile") {
                            settings.addProfile(named: "Nook \(settings.profiles.count + 1)")
                        }
                        Button("Duplicate Current") {
                            settings.addProfile(
                                named: "\(settings.activeProfile.name) Copy",
                                copyingCurrent: true
                            )
                        }
                        Divider()
                        Button("Delete Current", role: .destructive) {
                            settings.removeProfile(settings.activeProfile)
                        }
                        .disabled(settings.profiles.count == 1)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            NookWidgetEditor(
                items: settings.widgets.map { WidgetEditorItem(id: $0.rawValue, kind: $0.rawValue, title: $0.title, symbol: $0.systemImage) },
                choices: NookWidgetKind.allCases.map { WidgetEditorItem(id: $0.rawValue, kind: $0.rawValue, title: $0.title, symbol: $0.systemImage) },
                toggle: { raw in
                    guard let kind = NookWidgetKind(rawValue: raw) else { return }
                    settings.setEnabled(!settings.widgets.contains(kind), for: kind)
                },
                remove: { raw in
                    guard let kind = NookWidgetKind(rawValue: raw) else { return }
                    settings.setEnabled(false, for: kind)
                },
                reorder: { settings.setWidgetOrder($0.compactMap(NookWidgetKind.init(rawValue:))) }
            )

            SettingsCard("Lyrics & captions", systemImage: "captions.bubble") {
                Toggle(
                    "Show lyrics and subtitles below the widgets",
                    isOn: $settings.showTeleprompterBar
                )
                Text("Shows available song lyrics or captions from a supported YouTube tab.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WidgetAccessSettings()
        }
    }
}

struct NookSizeSettings: View {
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
            SettingsCard("Size", systemImage: "arrow.up.left.and.arrow.down.right") {
                HStack(spacing: 10) {
                    Image(systemName: "macbook.gen2")
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Closed size follows each display")
                            .font(.system(size: 12, weight: .semibold))
                        Text("The closed Nook follows your display’s notch. These controls set its open size.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Toggle("Fit width to the active profile", isOn: $settings.fitWidthToProfile)
                SettingsSlider(
                    title: settings.fitWidthToProfile ? "Maximum width" : "Expanded width",
                    value: $settings.expandedWidth,
                    range: 480...1280,
                    valueText: "\(Int(settings.expandedWidth)) pt"
                )
                SettingsSlider(
                    title: "Expanded height",
                    value: $settings.expandedHeight,
                    range: 210...420,
                    valueText: "\(Int(settings.expandedHeight)) pt"
                )

            }

    }
}

struct ActivitiesSettingsPane: View {
    @ObservedObject private var settings = NookSettings.shared

    var body: some View {
        SettingsPage(title: "Activities", subtitle: "Choose what appears beside the closed notch.") {
            SettingsCard("Live activities", systemImage: "waveform.path.ecg") {
                Text("Music, timers & devices")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Now Playing", isOn: $settings.showMusicLiveActivity)
                Toggle("Running timer", isOn: $settings.showTimerLiveActivity)
                Toggle("Power and low-battery alerts", isOn: $settings.showPowerLiveActivity)
                Toggle("Bluetooth and AirPods battery", isOn: $settings.showBluetoothLiveActivity)

                Divider()

                Text("System controls")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Toggle("Volume", isOn: $settings.showVolumeLiveActivity)
                Toggle("Display brightness", isOn: $settings.showBrightnessLiveActivity)
                Toggle(
                    "Keyboard backlight",
                    isOn: $settings.showKeyboardBrightnessLiveActivity
                )
                Toggle("Microphone mute", isOn: $settings.showMicrophoneLiveActivity)
                Toggle("Focus mode", isOn: $settings.showFocusLiveActivity)

                Text("System changes appear briefly. Unsupported controls stay hidden.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
