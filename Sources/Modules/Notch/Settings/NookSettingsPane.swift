import SwiftUI

struct NookSettingsPane: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        SettingsPage(
            title: "OpenNotch",
            subtitle: "Everything for the notch surface, in one place."
        ) {
            SettingsCard("OpenNotch", systemImage: "power") {
                Toggle("Enable OpenNotch", isOn: $app.notchEnabled)
                Text("Shows the compact live bar and opens your widget canvas at the physical notch.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SurfaceThemePicker(surface: .notch)

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

            SettingsCard("Widgets", systemImage: "square.grid.2x2") {
                HStack {
                    Text("\(settings.widgets.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        settings.widgets = []
                    }
                    .buttonStyle(.borderless)
                    .disabled(settings.widgets.isEmpty)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 145), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(NookWidgetKind.allCases) { kind in
                        nookWidgetCard(kind)
                    }
                }

                Text("Select a card to add or remove it. Drag widgets directly in OpenNotch to reorder them; each widget uses its designed default size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard("Size & edge", systemImage: "arrow.up.left.and.arrow.down.right") {
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
                SettingsSlider(
                    title: "Edge width",
                    value: $theme.notchEdgeWidth,
                    range: 0.5...3,
                    valueText: String(format: "%.1f pt", theme.notchEdgeWidth)
                )
                SettingsSlider(
                    title: "Edge strength",
                    value: $theme.notchEdgeStrength,
                    range: 0...1,
                    valueText: "\(Int(theme.notchEdgeStrength * 100))%"
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
    }

    private func nookWidgetCard(_ kind: NookWidgetKind) -> some View {
        let selected = settings.widgets.contains(kind)
        return HStack(spacing: 0) {
            Button {
                settings.setEnabled(!selected, for: kind)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: kind.systemImage)
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 20)
                    Text(kind.title)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(
                            selected
                                ? Color.black.opacity(0.72)
                                : Color.primary.opacity(0.24)
                        )
                }
                .padding(.leading, 10)
                .padding(.trailing, selected ? 4 : 10)
                .frame(maxWidth: .infinity, minHeight: 42)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if selected {
                Menu {
                    Section("Look") {
                        ForEach(WidgetVisualStyle.styles(for: kind)) { style in
                            Button {
                                settings.setWidgetStyle(style, for: kind)
                            } label: {
                                Label(style.title, systemImage: style.symbol)
                            }
                        }
                    }
                    Divider()
                    Button("Remove \(kind.title)", role: .destructive) {
                        settings.setEnabled(false, for: kind)
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 11, weight: .bold))
                        .frame(width: 30, height: 42)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }
        }
        .foregroundStyle(selected ? Color.black : Color.primary)
        .background(
            selected ? theme.notch.accent : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(
                    selected ? Color.black.opacity(0.10) : Color.primary.opacity(0.06),
                    lineWidth: 0.8
                )
        }
    }
}
