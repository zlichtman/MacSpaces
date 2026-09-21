import SwiftUI

struct NookSettingsPane: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingResetConfirmation = false

    var body: some View {
        SettingsPage(
            title: "Nook",
            subtitle: "Choose your widgets, then make the Nook fit your day."
        ) {
            SettingsCard("Nook", systemImage: "power") {
                HStack {
                    Toggle("Enable Nook", isOn: $app.notchEnabled)
                    Spacer(minLength: 16)
                    Button("Reset…") {
                        showingResetConfirmation = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                Text("Shows the compact live bar and opens your widget canvas at the physical notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SurfaceWidgetEditor(
                surface: .notch,
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

            SettingsCard("Size", systemImage: "arrow.up.left.and.arrow.down.right") {
                HStack(spacing: 10) {
                    Image(systemName: "macbook.gen2")
                        .foregroundStyle(theme.accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Closed size follows each display")
                            .font(.system(size: 12, weight: .semibold))
                        Text("At rest, MacSpaces matches the physical notch. It adds side room only while a live activity is visible.")
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

            SettingsCard("Open & close", systemImage: "cursorarrow.motionlines") {
                Toggle("Expand when hovering over the closed notch", isOn: $settings.expandOnHover)

                if settings.expandOnHover {
                    SettingsSlider(
                        title: "Hover delay",
                        value: $settings.hoverDelay,
                        range: 0...1,
                        valueText: String(format: "%.2f s", settings.hoverDelay)
                    )
                }

                Toggle("Scroll down on the closed notch to open", isOn: $settings.scrollGesturesEnabled)
                Text("Once open, gestures belong to the widgets. They no longer switch to the file Tray or close the Nook accidentally.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Teleprompter", systemImage: "captions.bubble") {
                Toggle(
                    "Show lyrics and subtitles below the widgets",
                    isOn: $settings.showTeleprompterBar
                )
                Text("MacSpaces follows song lyrics—synchronized when available—or the active captions in a supported YouTube tab. You can also toggle the strip from the Nook header.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard("Activities & displays", systemImage: "waveform.path.ecg") {
                Text("Nook")
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

                Divider()
                DisplayTargetPicker(
                    mode: $settings.displayMode,
                    selectedIDs: $settings.selectedDisplayIDs,
                    preferBuiltIn: true
                )
                Text("Changes appear briefly beside the closed notch. Unsupported controls stay hidden automatically.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .alert("Reset Nook?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                settings.resetToDefaults()
                theme.reset(.notch)
                app.notchEnabled = true
            }
        } message: {
            Text("This removes Nook profiles and widgets, then restores its theme, size, displays, activities, and behavior defaults.")
        }
    }

}
