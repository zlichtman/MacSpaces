import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreLocation
import ApplicationServices
import UserNotifications

enum SettingsDestination: String, CaseIterable, Identifiable {
    case notch
    case dock
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return "OpenNotch"
        case .dock: return "OpenDock"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .notch: return "macbook.gen2"
        case .dock: return "dock.rectangle"
        case .permissions: return "hand.raised"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    static let shared = SettingsNavigationModel()
    @Published var selection: SettingsDestination = .notch
}

struct SettingsView: View {
    @ObservedObject private var navigation = SettingsNavigationModel.shared

    var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 214)

            Rectangle()
                .fill(Color.primary.opacity(0.08))
                .frame(width: 1)

            detail
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .frame(minWidth: 880, idealWidth: 980, minHeight: 600, idealHeight: 680)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                MacSpacesMark(size: 34)
                Text("MacSpaces")
                    .font(.system(size: 15, weight: .bold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .padding(.top, 20)
            .padding(.bottom, 16)

            VStack(spacing: 3) {
                ForEach(SettingsDestination.allCases) {
                    sidebarItem($0)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 14)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func sidebarItem(_ destination: SettingsDestination) -> some View {
        let selected = navigation.selection == destination
        return Button {
            navigation.selection = destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? .primary : .secondary)
                    .frame(width: 19)
                Text(destination.title)
                    .font(.system(size: 13, weight: selected ? .semibold : .medium))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(
                selected ? Color.primary.opacity(0.075) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(Color.primary.opacity(0.72))
                        .frame(width: 2, height: 16)
                        .offset(x: -1)
                }
            }
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection {
        case .notch: NookSettingsPane()
        case .dock: DockSettingsPane()
        case .permissions: PermissionsSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}

private struct DockSettingsPane: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var audioMixer = AppServices.shared.audioMixer
    @State private var showingAudioMixer = false
    @State private var showingResetConfirmation = false

    var body: some View {
        SettingsPage(
            title: "OpenDock",
            subtitle: "Everything for the dock surface, in one place."
        ) {
            SettingsCard("OpenDock", systemImage: "power") {
                HStack {
                    Toggle("Enable OpenDock", isOn: $app.dockEnabled)
                    Spacer(minLength: 16)
                    Button("Reset…") {
                        showingResetConfirmation = true
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                Text("Places a configurable widget strip at your chosen screen edge.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Window previews", systemImage: "rectangle.on.rectangle") {
                Toggle(
                    "Show live windows when hovering over apps in Apple’s Dock",
                    isOn: $store.windowPreviewsEnabled
                )
                .onChange(of: store.windowPreviewsEnabled) { enabled in
                    guard enabled else { return }
                    requestWindowPreviewPermissions()
                }

                Text("Hover a running app to see every open, minimized, and hidden window. Select one to bring that exact window forward. The App Switcher widget uses the same browser.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if store.windowPreviewsEnabled {
                    HStack(spacing: 8) {
                        previewPermissionBadge(
                            title: "Accessibility",
                            granted: AXIsProcessTrusted(),
                            symbol: "accessibility",
                            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                        )
                        previewPermissionBadge(
                            title: "Screen Recording",
                            granted: CGPreflightScreenCaptureAccess(),
                            symbol: "record.circle",
                            settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                        )
                    }

                    SettingsSlider(
                        title: "Hover delay",
                        value: $store.windowPreviewDelay,
                        range: 0.05...0.75,
                        valueText: String(format: "%.2f s", store.windowPreviewDelay)
                    )

                    Picker(
                        "Maximum previews",
                        selection: $store.windowPreviewLimit
                    ) {
                        Text("4").tag(4)
                        Text("6").tag(6)
                        Text("8").tag(8)
                    }
                    .pickerStyle(.segmented)
                }
            }

            SettingsCard("App audio", systemImage: "speaker.wave.2") {
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Per-app volume profiles")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Set a separate level or mute state for each app. MacSpaces remembers it by bundle identifier.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 12)
                    Button("Open App Mixer") {
                        audioMixer.start()
                        showingAudioMixer = true
                    }
                    .buttonStyle(.borderedProminent)
                    .popover(
                        isPresented: $showingAudioMixer,
                        arrowEdge: .top
                    ) {
                        AudioMixerPanel(mixer: audioMixer)
                    }
                }

                if !store.widgets.contains(where: { $0.kind == .audio }) {
                    Button {
                        store.add(.audio)
                    } label: {
                        Label(
                            "Add Audio Controls to OpenDock",
                            systemImage: "plus"
                        )
                    }
                    .buttonStyle(.borderless)
                }
            }
            .onChange(of: showingAudioMixer) { showing in
                if !showing,
                   !store.widgets.contains(where: { $0.kind == .audio }) {
                    audioMixer.stop()
                }
            }

            SurfaceThemePicker(surface: .dock)

            SettingsCard("Profile", systemImage: "rectangle.3.group") {
                HStack {
                    Picker("Active profile", selection: $store.activeProfileID) {
                        ForEach(store.profiles) { profile in
                            Text(profile.name).tag(profile.id)
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 220)

                    TextField(
                        "Profile name",
                        text: Binding(
                            get: { store.activeProfile.name },
                            set: { store.renameProfile(store.activeProfile, to: $0) }
                        )
                    )
                    .textFieldStyle(.roundedBorder)

                    Menu {
                        Button("New Empty Profile") {
                            store.addProfile(named: "Dock \(store.profiles.count + 1)")
                        }
                        Button("Duplicate Current") {
                            store.addProfile(
                                named: "\(store.activeProfile.name) Copy",
                                copyingCurrent: true
                            )
                        }
                        Divider()
                        Button("Delete Current", role: .destructive) {
                            store.removeProfile(store.activeProfile)
                        }
                        .disabled(store.profiles.count == 1)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            SettingsCard("Widgets", systemImage: "square.grid.2x2") {
                HStack {
                    Text("\(store.widgets.count) selected")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Clear") {
                        store.widgets = []
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.widgets.isEmpty)
                }

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 150), spacing: 8)],
                    spacing: 8
                ) {
                    ForEach(WidgetKind.allCases) { kind in
                        dockWidgetCard(kind)
                    }
                }

                Text("Select cards to add or remove widgets. Drag widgets directly in OpenDock to reorder them; glanceable widgets stack at their designed default size.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard("Placement", systemImage: "rectangle.bottomthird.inset.filled") {
                Picker("Screen edge", selection: $store.position) {
                    ForEach(DockPosition.allCases) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                SettingsSlider(
                    title: "Edge offset",
                    value: $store.edgeOffset,
                    range: 0...40,
                    valueText: "\(Int(store.edgeOffset)) pt"
                )

                DisplayTargetPicker(
                    mode: $store.displayMode,
                    selectedIDs: $store.selectedDisplayIDs,
                    preferBuiltIn: false
                )
            }

            SettingsCard("Sizing", systemImage: "arrow.up.left.and.arrow.down.right") {
                SettingsSlider(
                    title: "Widget size",
                    value: $store.tileSize,
                    range: 56...96,
                    valueText: "\(Int(store.tileSize)) pt"
                )

                if store.effectivePosition.isVertical {
                    SettingsSlider(
                        title: "Side Dock width",
                        value: $store.sideDockWidth,
                        range: 104...220,
                        valueText: "\(Int(store.sideDockWidth)) pt"
                    )
                }
            }

            SettingsCard("Behavior", systemImage: "cursorarrow.rays") {
                Toggle("Auto-hide at the screen edge", isOn: $store.autoHide)
                if store.autoHide {
                    SettingsSlider(
                        title: "Hide delay",
                        value: $store.hideDelay,
                        range: 0.1...1.2,
                        valueText: String(format: "%.2f s", store.hideDelay)
                    )
                }
                Toggle("Dock is visible", isOn: $store.isDockVisible)
            }
        }
        .alert("Reset OpenDock?", isPresented: $showingResetConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button("Reset", role: .destructive) {
                store.resetToDefaults()
                theme.reset(.dock)
                app.dockEnabled = true
            }
        } message: {
            Text("This removes OpenDock profiles and widgets, then restores its theme, placement, size, displays, previews, and behavior defaults.")
        }
    }

    private func requestWindowPreviewPermissions() {
        if !AXIsProcessTrusted() {
            let promptKey = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
            AXIsProcessTrustedWithOptions([promptKey: true] as CFDictionary)
        }
        if !CGPreflightScreenCaptureAccess() {
            CGRequestScreenCaptureAccess()
        }
    }

    private func previewPermissionBadge(
        title: String,
        granted: Bool,
        symbol: String,
        settingsURL: String
    ) -> some View {
        Button {
            guard let url = URL(string: settingsURL) else { return }
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 7) {
                Image(systemName: symbol)
                Text(title)
                    .lineLimit(1)
                Image(systemName: granted ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                    .foregroundStyle(granted ? Color.green : Color.orange)
            }
            .font(.system(size: 11, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 32)
            .background(
                Color.primary.opacity(0.05),
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .help(granted ? "\(title) is allowed" : "Open \(title) settings")
    }

    private func dockWidgetCard(_ kind: WidgetKind) -> some View {
        let instance = store.widgets.first { $0.kind == kind }
        let selected = instance != nil
        return HStack(spacing: 0) {
            Button {
                if let instance {
                    store.remove(instance)
                } else {
                    store.add(kind)
                }
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

            if let instance {
                Menu {
                    Section("Look") {
                        ForEach(WidgetVisualStyle.styles(for: kind)) { style in
                            Button {
                                store.setWidgetStyle(style, for: instance)
                            } label: {
                                Label(style.title, systemImage: style.symbol)
                            }
                        }
                    }
                    Button("Add another") {
                        store.duplicate(instance)
                    }
                    Divider()
                    Button("Remove \(kind.title)", role: .destructive) {
                        store.remove(instance)
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
            selected ? theme.dock.accent : Color.primary.opacity(0.045),
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

struct SurfaceThemePicker: View {
    let surface: ThemeSurface

    @ObservedObject private var theme = ThemeStore.shared
    @State private var selectedForPairing: ThemePreset?

    private let presets =
        ThemePreset.macSpacesPresets + ThemePreset.terminalPresets

    var body: some View {
        SettingsCard("Theme", systemImage: "paintpalette") {
            Text("Choose one palette for \(surface.title). Widget materials are selected on each widget.")
                .font(.caption)
                .foregroundStyle(.secondary)

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4),
                spacing: 8
            ) {
                ForEach(presets) { preset in
                    themePill(preset)
                }
            }

            HStack(spacing: 10) {
                themePill(.custom)
                    .frame(maxWidth: .infinity)

                if theme.preset(for: surface) == .custom {
                    ColorPicker(
                        "Custom color",
                        selection: customSurfaceColor,
                        supportsOpacity: false
                    )
                    .labelsHidden()
                    .frame(width: 32)
                    .help("Choose a custom \(surface.title) color")
                }
            }

            if let selectedForPairing,
               theme.preset(for: surface.other) != selectedForPairing {
                HStack(spacing: 8) {
                    Image(systemName: "link")
                        .font(.caption)
                        .foregroundStyle(selectedForPairing.previewColor)
                    Text("Match \(surface.other.title) to \(selectedForPairing.title)?")
                        .font(.caption)
                    Spacer()
                    Button("Apply") {
                        pair(selectedForPairing)
                    }
                    .buttonStyle(.borderless)
                    Button {
                        self.selectedForPairing = nil
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .frame(height: 24)
            }

            Divider()

            SettingsSlider(
                title: "Color intensity",
                value: intensityBinding,
                range: 0...1,
                valueText: "\(Int(intensityBinding.wrappedValue * 100))%"
            )
            SettingsSlider(
                title: "Widget definition",
                value: contrastBinding,
                range: 0...1,
                valueText: "\(Int(contrastBinding.wrappedValue * 100))%"
            )
            SettingsSlider(
                title: "Ambient glow",
                value: glowBinding,
                range: 0...1,
                valueText: "\(Int(glowBinding.wrappedValue * 100))%"
            )

            if surface == .notch {
                SettingsSlider(
                    title: "Surface opacity",
                    value: $theme.notchOpacity,
                    range: 0.84...1,
                    valueText: "\(Int(theme.notchOpacity * 100))%"
                )
                SettingsSlider(
                    title: "Corner radius",
                    value: $theme.notchCornerRadius,
                    range: 14...34,
                    valueText: "\(Int(theme.notchCornerRadius)) pt"
                )
            } else {
                SettingsSlider(
                    title: "Surface opacity",
                    value: $theme.dockOpacity,
                    range: 0.72...1,
                    valueText: "\(Int(theme.dockOpacity * 100))%"
                )
                SettingsSlider(
                    title: "Corner radius",
                    value: $theme.dockCornerRadius,
                    range: 14...34,
                    valueText: "\(Int(theme.dockCornerRadius)) pt"
                )
            }
        }
    }

    private func themePill(_ preset: ThemePreset) -> some View {
        let isSelected = theme.preset(for: surface) == preset
        return Button {
            select(preset)
        } label: {
            HStack(spacing: 8) {
                paletteSwatches(for: preset)
                Text(preset.title)
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
                Spacer(minLength: 0)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 9, weight: .bold))
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 34)
            .background(
                isSelected ? preset.previewColor.opacity(0.16) : Color.primary.opacity(0.04),
                in: Capsule()
            )
            .overlay {
                Capsule()
                    .strokeBorder(
                        isSelected ? preset.previewColor.opacity(0.58) : Color.primary.opacity(0.08),
                        lineWidth: 0.8
                    )
            }
        }
        .buttonStyle(.plain)
    }

    private func paletteSwatches(for preset: ThemePreset) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(swatches(for: preset).enumerated()), id: \.offset) { _, color in
                RoundedRectangle(cornerRadius: 2, style: .continuous)
                    .fill(color)
                    .frame(width: 6, height: 16)
            }
        }
        .padding(2)
        .background(
            Color.black.opacity(0.24),
            in: RoundedRectangle(cornerRadius: 4, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 4, style: .continuous)
                .strokeBorder(.white.opacity(0.14), lineWidth: 0.5)
        }
    }

    private func swatches(for preset: ThemePreset) -> [Color] {
        if preset == .custom {
            let color = customSurfaceColor.wrappedValue
            return [color.opacity(0.32), color.opacity(0.68), color]
        }
        return preset.previewSwatches
    }

    private func select(_ preset: ThemePreset) {
        withAnimation(Design.spring()) {
            theme.setPreset(preset, for: surface)
        }
        selectedForPairing = preset
    }

    private func pair(_ preset: ThemePreset) {
        withAnimation(Design.spring()) {
            theme.setPreset(preset, for: surface.other)
            if preset == .custom {
                if surface == .notch {
                    theme.customDockHex = theme.customNotchHex
                } else {
                    theme.customNotchHex = theme.customDockHex
                }
            }
        }
        selectedForPairing = nil
    }

    private var customSurfaceColor: Binding<Color> {
        Binding(
            get: {
                let hex = surface == .notch ? theme.customNotchHex : theme.customDockHex
                return Color(themeHex: hex) ?? .black
            },
            set: { color in
                let hex = NSColor(color).themeHexString
                if surface == .notch {
                    theme.customNotchHex = hex
                } else {
                    theme.customDockHex = hex
                }
                theme.setPreset(.custom, for: surface)
            }
        )
    }

    private var intensityBinding: Binding<Double> {
        surfaceBinding(
            notch: \.notchThemeIntensity,
            dock: \.dockThemeIntensity
        )
    }

    private var contrastBinding: Binding<Double> {
        surfaceBinding(
            notch: \.notchTileContrast,
            dock: \.dockTileContrast
        )
    }

    private var glowBinding: Binding<Double> {
        surfaceBinding(
            notch: \.notchGlowStrength,
            dock: \.dockGlowStrength
        )
    }

    private func surfaceBinding(
        notch: ReferenceWritableKeyPath<ThemeStore, Double>,
        dock: ReferenceWritableKeyPath<ThemeStore, Double>
    ) -> Binding<Double> {
        Binding(
            get: { theme[keyPath: surface == .notch ? notch : dock] },
            set: { theme[keyPath: surface == .notch ? notch : dock] = $0 }
        )
    }
}

private struct ThemeSettingsPane: View {
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        SettingsPage(
            title: "Appearance",
            subtitle: "See every change live, start from a complete look, or shape every surface yourself."
        ) {
            ThemePreview()

            SettingsCard("Presets", systemImage: "wand.and.stars") {
                Text("Four complete starting points. Each sets color and widget geometry; customization remains fully editable below.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack(spacing: 9) {
                    ForEach(QuickLook.allCases) { look in
                        Button {
                            withAnimation(Design.spring()) { look.apply(to: theme) }
                        } label: {
                            VStack(alignment: .leading, spacing: 9) {
                                HStack {
                                    Image(systemName: look.symbol)
                                        .foregroundStyle(look.accent)
                                    Spacer(minLength: 0)
                                    if look.isActive(in: theme) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(look.accent)
                                    }
                                }

                                Text(look.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .lineLimit(1)

                                HStack(spacing: 4) {
                                    ForEach(Array(look.swatches.enumerated()), id: \.offset) { _, color in
                                        Capsule()
                                            .fill(color)
                                            .frame(maxWidth: .infinity)
                                            .frame(height: 5)
                                    }
                                }
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 82, alignment: .leading)
                            .background(
                                look.isActive(in: theme)
                                    ? look.accent.opacity(0.17)
                                    : Color.primary.opacity(0.045),
                                in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                            )
                            .overlay {
                                RoundedRectangle(cornerRadius: 11, style: .continuous)
                                    .strokeBorder(
                                        look.isActive(in: theme)
                                            ? look.accent.opacity(0.52)
                                            : Color.primary.opacity(0.08)
                                    )
                            }
                        }
                        .buttonStyle(PremiumPressButtonStyle())
                    }
                }
            }

            SettingsCard("Customization", systemImage: "slider.horizontal.3") {
                customizationHeading(
                    "Widget shape",
                    detail: "Geometry changes without replacing your colors."
                )

                HStack(spacing: 8) {
                    ForEach(WidgetVisualStyle.allCases) { style in
                        Button {
                            withAnimation(Design.spring()) {
                                theme.widgetVisualStyle = style
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 7) {
                                Image(systemName: style.symbol)
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundStyle(theme.widgetVisualStyle == style ? theme.accent : .secondary)
                                Text(style.title)
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, minHeight: 58, alignment: .leading)
                            .background {
                                PremiumWidgetChrome(
                                    tokens: theme.dock,
                                    style: style,
                                    isActive: theme.widgetVisualStyle == style
                                )
                            }
                            .clipShape(RoundedRectangle(cornerRadius: style.chromeRadius, style: .continuous))
                        }
                        .buttonStyle(PremiumPressButtonStyle())
                    }
                }

                Divider()

                customizationHeading(
                    "Surface palettes",
                    detail: "Keep Nook and Dock coordinated or mix any two palettes."
                )

                HStack(spacing: 10) {
                    Menu {
                        Section("MacSpaces") {
                            ForEach(ThemePreset.macSpacesPresets) { preset in
                                Button(preset.title) {
                                    theme.applyCoordinatedPreset(preset)
                                }
                            }
                        }
                        Section("Terminal classics") {
                            ForEach(ThemePreset.terminalPresets) { preset in
                                Button(preset.title) {
                                    theme.applyCoordinatedPreset(preset)
                                }
                            }
                        }
                    } label: {
                        Label("Apply to both", systemImage: "link")
                    }
                    .buttonStyle(.bordered)

                    Picker("Nook", selection: $theme.notchPreset) {
                        ForEach(ThemePreset.allCases) { Text($0.title).tag($0) }
                    }

                    Picker("Dock", selection: $theme.dockPreset) {
                        ForEach(ThemePreset.allCases) { Text($0.title).tag($0) }
                    }
                }

                Divider()

                customizationHeading(
                    "Color",
                    detail: "Choose a quick accent or enter exact colors for each surface."
                )

                HStack(spacing: 17) {
                    ForEach(AccentChoice.allCases) { choice in
                        Button {
                            theme.accentChoice = choice
                        } label: {
                            Circle()
                                .fill(choice == .custom ? (Color(themeHex: theme.customAccentHex) ?? .white) : choice.color)
                                .frame(width: 22, height: 22)
                                .overlay {
                                    if theme.accentChoice == choice {
                                        Circle().strokeBorder(.primary, lineWidth: 2)
                                            .padding(-4)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .help(choice.title)
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    ExactColorField(
                        "Accent",
                        color: accentColor,
                        hex: $theme.customAccentHex
                    ) {
                        theme.accentChoice = .custom
                    }
                    ExactColorField(
                        "Nook",
                        color: nookColor,
                        hex: $theme.customNotchHex
                    ) {
                        theme.notchPreset = .custom
                    }
                    ExactColorField(
                        "Dock",
                        color: dockColor,
                        hex: $theme.customDockHex
                    ) {
                        theme.dockPreset = .custom
                    }
                }

                Divider()

                customizationHeading(
                    "Finish",
                    detail: "Control depth, edges, density, and motion."
                )

                VStack(spacing: 10) {
                    SettingsSlider(
                        title: "Color intensity",
                        value: $theme.themeIntensity,
                        range: 0...1,
                        valueText: "\(Int(theme.themeIntensity * 100))%"
                    )
                    SettingsSlider(
                        title: "Tile definition",
                        value: $theme.tileContrast,
                        range: 0...1,
                        valueText: "\(Int(theme.tileContrast * 100))%"
                    )
                    SettingsSlider(
                        title: "Ambient glow",
                        value: $theme.glowStrength,
                        range: 0...1,
                        valueText: "\(Int(theme.glowStrength * 100))%"
                    )
                    SettingsSlider(
                        title: "Nook edge",
                        value: $theme.notchEdgeWidth,
                        range: 0...4,
                        valueText: String(format: "%.1f pt", theme.notchEdgeWidth)
                    )
                    SettingsSlider(
                        title: "Edge contrast",
                        value: $theme.notchEdgeStrength,
                        range: 0...1,
                        valueText: "\(Int(theme.notchEdgeStrength * 100))%"
                    )
                    SettingsSlider(
                        title: "Nook opacity",
                        value: $theme.notchOpacity,
                        range: 0.84...1,
                        valueText: "\(Int(theme.notchOpacity * 100))%"
                    )
                    SettingsSlider(
                        title: "Dock opacity",
                        value: $theme.dockOpacity,
                        range: 0.72...1,
                        valueText: "\(Int(theme.dockOpacity * 100))%"
                    )
                    SettingsSlider(
                        title: "Nook corners",
                        value: $theme.notchCornerRadius,
                        range: 14...34,
                        valueText: "\(Int(theme.notchCornerRadius)) pt"
                    )
                    SettingsSlider(
                        title: "Dock corners",
                        value: $theme.dockCornerRadius,
                        range: 14...34,
                        valueText: "\(Int(theme.dockCornerRadius)) pt"
                    )

                    Divider()

                    Toggle("Gradient surfaces", isOn: $theme.gradientSurfaces)
                    Toggle("Compact controls", isOn: $theme.compactControls)
                    Toggle("Reduce interface motion", isOn: $theme.reduceMotionPreference)
                        .disabled(theme.systemReduceMotion)
                    if theme.systemReduceMotion {
                        Text("Already on because Reduce Motion is enabled in System Settings › Accessibility › Display.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                HStack {
                    Text("Changes apply to the Nook and Dock immediately.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restore Defaults") {
                        theme.reset()
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    @MainActor
    private enum QuickLook: CaseIterable, Identifiable {
        case midnightStudio, tidalGlass, tokyoTerminal, emberSoft

        nonisolated var id: Self { self }

        var title: String {
            switch self {
            case .midnightStudio: return "Midnight Studio"
            case .tidalGlass: return "Tidal Glass"
            case .tokyoTerminal: return "Tokyo Terminal"
            case .emberSoft: return "Ember Soft"
            }
        }

        var symbol: String {
            switch self {
            case .midnightStudio: return "moon.stars.fill"
            case .tidalGlass: return "water.waves"
            case .tokyoTerminal: return "terminal.fill"
            case .emberSoft: return "sparkles"
            }
        }

        var accent: Color {
            switch self {
            case .midnightStudio: return AccentChoice.blue.color
            case .tidalGlass: return AccentChoice.cyan.color
            case .tokyoTerminal: return Color(themeHex: "#7AA2F7") ?? AccentChoice.blue.color
            case .emberSoft: return AccentChoice.orange.color
            }
        }

        var swatches: [Color] {
            switch self {
            case .midnightStudio:
                return [Color(themeHex: "#020714") ?? .black, Color(themeHex: "#0A2952") ?? .blue, accent]
            case .tidalGlass:
                return [Color(themeHex: "#021D2A") ?? .black, Color(themeHex: "#006B8F") ?? .cyan, accent]
            case .tokyoTerminal:
                return [Color(themeHex: "#1A1B26") ?? .black, Color(themeHex: "#24283B") ?? .gray, accent]
            case .emberSoft:
                return [Color(themeHex: "#240606") ?? .black, Color(themeHex: "#B82106") ?? .orange, accent]
            }
        }

        func apply(to theme: ThemeStore) {
            switch self {
            case .midnightStudio:
                theme.applyCoordinatedPreset(.midnight)
                theme.widgetVisualStyle = .studio
                theme.themeIntensity = 0.82
                theme.tileContrast = 0.72
                theme.glowStrength = 0.24
                theme.gradientSurfaces = true
            case .tidalGlass:
                theme.applyCoordinatedPreset(.ocean)
                theme.widgetVisualStyle = .glass
                theme.themeIntensity = 0.72
                theme.tileContrast = 0.56
                theme.glowStrength = 0.34
                theme.gradientSurfaces = true
            case .tokyoTerminal:
                theme.applyCoordinatedPreset(.tokyoNight)
                theme.widgetVisualStyle = .terminal
                theme.themeIntensity = 0.88
                theme.tileContrast = 0.84
                theme.glowStrength = 0.12
                theme.gradientSurfaces = false
            case .emberSoft:
                theme.applyCoordinatedPreset(.sunset)
                theme.widgetVisualStyle = .soft
                theme.themeIntensity = 0.86
                theme.tileContrast = 0.64
                theme.glowStrength = 0.31
                theme.gradientSurfaces = true
            }
        }

        func isActive(in theme: ThemeStore) -> Bool {
            switch self {
            case .midnightStudio: return theme.notchPreset == .midnight && theme.dockPreset == .midnight && theme.widgetVisualStyle == .studio
            case .tidalGlass: return theme.notchPreset == .ocean && theme.dockPreset == .ocean && theme.widgetVisualStyle == .glass
            case .tokyoTerminal: return theme.notchPreset == .tokyoNight && theme.dockPreset == .tokyoNight && theme.widgetVisualStyle == .terminal
            case .emberSoft: return theme.notchPreset == .sunset && theme.dockPreset == .sunset && theme.widgetVisualStyle == .soft
            }
        }
    }

    private var accentColor: Binding<Color> {
        customColor(hex: theme.customAccentHex) {
            theme.customAccentHex = $0
            theme.accentChoice = .custom
        }
    }

    private var nookColor: Binding<Color> {
        customColor(hex: theme.customNotchHex) {
            theme.customNotchHex = $0
            theme.notchPreset = .custom
        }
    }

    private var dockColor: Binding<Color> {
        customColor(hex: theme.customDockHex) {
            theme.customDockHex = $0
            theme.dockPreset = .custom
        }
    }

    private func customColor(hex: String, set: @escaping (String) -> Void) -> Binding<Color> {
        Binding(
            get: { Color(themeHex: hex) ?? .black },
            set: { set(NSColor($0).themeHexString) }
        )
    }

    private func customizationHeading(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 12, weight: .semibold))
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ExactColorField: View {
    private let title: String
    @Binding private var color: Color
    @Binding private var hex: String
    private let onCustom: () -> Void

    @State private var draft: String

    init(
        _ title: String,
        color: Binding<Color>,
        hex: Binding<String>,
        onCustom: @escaping () -> Void
    ) {
        self.title = title
        self._color = color
        self._hex = hex
        self.onCustom = onCustom
        self._draft = State(initialValue: hex.wrappedValue)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ColorPicker(title, selection: $color, supportsOpacity: false)
                .font(.system(size: 11, weight: .medium))
            TextField("#000000", text: $draft)
                .font(.system(size: 10, design: .monospaced))
                .textFieldStyle(.roundedBorder)
                .onChange(of: draft) { newValue in
                    // Only a user edit should switch the surface to its custom
                    // color; programmatic hex changes arrive with draft already
                    // synced below.
                    guard newValue != hex else { return }
                    hex = newValue
                    onCustom()
                }
                .onChange(of: hex) { newValue in
                    if draft != newValue { draft = newValue }
                }
        }
        .padding(9)
        .frame(maxWidth: .infinity)
        .background(
            Color.primary.opacity(0.04),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
    }
}

private struct ThemePreview: View {
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.08, green: 0.10, blue: 0.16),
                    Color(red: 0.12, green: 0.18, blue: 0.25),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            VStack(spacing: 12) {
                previewLabel("NOOK", value: theme.notchPreset.title)

                HStack(spacing: 7) {
                    previewTile("music.note", tokens: theme.notch, width: 104)
                    previewTile("timer", tokens: theme.notch, width: 58)
                    previewTile("calendar", tokens: theme.notch, width: 74)
                }
                .padding(9)
                .frame(maxWidth: .infinity)
                .background(
                    theme.notch.surface,
                    in: RoundedRectangle(cornerRadius: CGFloat(theme.notchCornerRadius), style: .continuous)
                )
                .background(
                    theme.notch.surfaceSecondary,
                    in: RoundedRectangle(cornerRadius: CGFloat(theme.notchCornerRadius), style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: CGFloat(theme.notchCornerRadius), style: .continuous)
                        .strokeBorder(theme.notch.border, lineWidth: max(1, theme.notchEdgeWidth))
                }

                HStack(spacing: 10) {
                    previewLabel("DOCK", value: theme.dockPreset.title)
                    Spacer()
                    HStack(spacing: 6) {
                        previewTile("clock.fill", tokens: theme.dock, width: 34)
                        previewTile("bolt.fill", tokens: theme.dock, width: 34)
                        previewTile("battery.100percent", tokens: theme.dock, width: 34)
                    }
                    .padding(6)
                    .background(
                        theme.dock.surface,
                        in: RoundedRectangle(cornerRadius: CGFloat(theme.dockCornerRadius), style: .continuous)
                    )
                    .background(
                        theme.dock.surfaceSecondary,
                        in: RoundedRectangle(cornerRadius: CGFloat(theme.dockCornerRadius), style: .continuous)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: CGFloat(theme.dockCornerRadius), style: .continuous)
                            .strokeBorder(theme.dock.border)
                    }
                }
            }
            .padding(14)
        }
        .frame(height: 190)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(.white.opacity(0.12))
        }
    }

    private func previewLabel(_ title: String, value: String) -> some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.system(size: 8, weight: .bold))
                .tracking(0.8)
            Text(value)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.secondary)
        }
        .foregroundStyle(.white)
    }

    private func previewTile(
        _ symbol: String,
        tokens: ThemeTokens,
        width: CGFloat
    ) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tokens.accent)
            .frame(width: width, height: 34)
            .background {
                PremiumWidgetChrome(tokens: tokens, style: theme.widgetVisualStyle, isActive: false)
            }
            .clipShape(RoundedRectangle(cornerRadius: previewRadius, style: .continuous))
    }

    private var previewRadius: CGFloat {
        switch theme.widgetVisualStyle {
        case .studio: return 10
        case .glass: return 12
        case .terminal: return 5
        case .soft: return 16
        case .signal: return 8
        case .orbit: return 17
        case .mono: return 6
        case .frame: return 7
        }
    }
}

private struct PermissionsSettingsPane: View {
    @MainActor private static let locationManager = CLLocationManager()

    var body: some View {
        SettingsPage(
            title: "Permissions",
            subtitle: "Features ask only when used. MacSpaces keeps personal data on this Mac."
        ) {
            SettingsCard("Feature access", systemImage: "hand.raised") {
                PermissionRow(
                    title: "Camera",
                    detail: "Mirror in the Notch Hub",
                    symbol: "camera",
                    status: cameraStatus,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"
                )
                PermissionRow(
                    title: "Microphone",
                    detail: "Voice Memo widget",
                    symbol: "mic",
                    status: microphoneStatus,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone"
                )
                PermissionRow(
                    title: "Calendars",
                    detail: "Calendar and meeting widgets",
                    symbol: "calendar",
                    status: eventStatus(.event),
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
                )
                PermissionRow(
                    title: "Reminders",
                    detail: "Todo widget",
                    symbol: "checklist",
                    status: eventStatus(.reminder),
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"
                )
                PermissionRow(
                    title: "Location",
                    detail: "Local weather",
                    symbol: "location",
                    status: locationStatus,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"
                )
                PermissionRow(
                    title: "Accessibility",
                    detail: "Window management, Dock app detection, and exact window focus",
                    symbol: "accessibility",
                    status: AXIsProcessTrusted() ? .granted : .notGranted,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
                )
                PermissionRow(
                    title: "Screen Recording",
                    detail: "Live thumbnails for OpenDock window previews",
                    symbol: "record.circle",
                    status: CGPreflightScreenCaptureAccess() ? .granted : .notGranted,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
                )
                PermissionRow(
                    title: "System Audio",
                    detail: "Per-app volume and live mixer levels",
                    symbol: "waveform",
                    status: AppServices.shared.audioMixer.isMixerRunning
                        ? .granted
                        : .review,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
                )
                PermissionRow(
                    title: "Media apps & browsers",
                    detail: "Now Playing metadata fallback",
                    symbol: "music.note",
                    status: .review,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                )
            }

            SettingsCard("Privacy", systemImage: "lock.shield") {
                Label("Clipboard history, notes, profiles, and tray items stay on this Mac.", systemImage: "checkmark.shield")
                Label("Network widgets contact only the service they display.", systemImage: "network")
            }
        }
    }

    private var cameraStatus: PermissionState {
        mediaStatus(AVCaptureDevice.authorizationStatus(for: .video))
    }

    private var microphoneStatus: PermissionState {
        mediaStatus(AVCaptureDevice.authorizationStatus(for: .audio))
    }

    private func mediaStatus(_ status: AVAuthorizationStatus) -> PermissionState {
        switch status {
        case .authorized: return .granted
        case .notDetermined: return .notRequested
        default: return .notGranted
        }
    }

    private func eventStatus(_ type: EKEntityType) -> PermissionState {
        switch EKEventStore.authorizationStatus(for: type) {
        case .fullAccess, .authorized: return .granted
        case .notDetermined: return .notRequested
        default: return .notGranted
        }
    }

    @MainActor
    private var locationStatus: PermissionState {
        switch Self.locationManager.authorizationStatus {
        case .authorized, .authorizedAlways: return .granted
        case .notDetermined: return .notRequested
        default: return .notGranted
        }
    }
}

private enum PermissionState: Equatable {
    case granted
    case notRequested
    case notGranted
    case review

    var title: String {
        switch self {
        case .granted: return "Granted"
        case .notRequested: return "When Needed"
        case .notGranted: return "Open Settings"
        case .review: return "Check Access"
        }
    }

    var color: Color {
        switch self {
        case .granted: return .green
        case .notRequested: return .secondary
        case .notGranted: return .orange
        case .review: return AccentChoice.mint.color
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let symbol: String
    let status: PermissionState
    let settingsURL: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 30, height: 30)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.system(size: 13, weight: .medium))
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button(status.title) {
                guard let url = URL(string: settingsURL) else { return }
                NSWorkspace.shared.open(url)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(status.color)
            .disabled(status == .granted)
        }
        .padding(.vertical, 3)
    }
}

private struct AboutSettingsPane: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var updater = UpdateService.shared

    var body: some View {
        SettingsPage(
            title: "About MacSpaces",
            subtitle: "A local-first, open-source control surface for macOS."
        ) {
            VStack(spacing: 14) {
                MacSpacesMark(size: 82)
                Text("MacSpaces")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("One app. Two surfaces. Your Mac, arranged around the way you work.")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 30)

            SettingsCard("Open source", systemImage: "chevron.left.forwardslash.chevron.right") {
                Text("Built with SwiftUI and AppKit. Personal data stays on-device unless a widget explicitly connects to a network service.")
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Updates", systemImage: "arrow.triangle.2.circlepath") {
                Toggle(
                    "Check for new versions automatically",
                    isOn: $updater.automaticallyCheckForUpdates
                )
                Toggle(
                    "Download new versions automatically",
                    isOn: $updater.automaticallyInstallUpdates
                )
                .disabled(!updater.automaticallyCheckForUpdates)
                Text("Updates are fetched from GitHub and verified against the installed app's signature. MacSpaces always asks before quitting to finish an install.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                HStack {
                    Text(updater.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button(updater.actionLabel) {
                        updater.performPrimaryAction()
                    }
                    .buttonStyle(.bordered)
                    .disabled(updater.isBusy)
                }
            }

            SettingsCard("Startup", systemImage: "power") {
                Toggle("Launch MacSpaces at login", isOn: $app.launchAtLogin)
                Text("MacSpaces launches directly as a menu-bar app—there is no setup tour or extra first-run window.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

struct MacSpacesMark: View {
    let size: CGFloat

    var body: some View {
        Group {
            if
                let url = Bundle.main.url(
                    forResource: "MacSpacesIcon-master",
                    withExtension: "png"
                ),
                let image = NSImage(contentsOf: url)
            {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
            } else {
                RoundedRectangle(cornerRadius: size * 0.27, style: .continuous)
                    .fill(ThemeStore.shared.accent)
                    .overlay {
                        Image(systemName: "square.grid.2x2.fill")
                            .font(.system(size: size * 0.25, weight: .semibold))
                            .foregroundStyle(.white)
                    }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Color.black.opacity(0.22), radius: size * 0.12, y: size * 0.06)
    }
}
