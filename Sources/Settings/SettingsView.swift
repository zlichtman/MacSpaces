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
    case theme
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return "OpenNotch"
        case .dock: return "OpenDock"
        case .theme: return "Theme"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .notch: return "macbook.gen2"
        case .dock: return "dock.rectangle"
        case .theme: return "paintpalette"
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
        case .theme: ThemeSettingsPane()
        case .permissions: PermissionsSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}

private struct DockSettingsPane: View {
    @ObservedObject private var app = AppSettings.shared
    @ObservedObject private var store = DockStore.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var appleDock = AppleDockPlacement.shared
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

            SurfaceWidgetEditor(
                surface: .dock,
                items: store.widgets.map { WidgetEditorItem(id: $0.id.uuidString, kind: $0.kind.rawValue, title: $0.kind.title, symbol: $0.kind.systemImage) },
                choices: WidgetKind.allCases.map { WidgetEditorItem(id: $0.rawValue, kind: $0.rawValue, title: $0.title, symbol: $0.systemImage) },
                toggle: { raw in
                    guard let kind = WidgetKind(rawValue: raw) else { return }
                    if store.widgets.contains(where: { $0.kind == kind }) {
                        store.widgets.removeAll { $0.kind == kind }
                    } else { store.add(kind) }
                },
                remove: { id in store.widgets.removeAll { $0.id.uuidString == id } },
                reorder: { ids in
                    let current = Dictionary(uniqueKeysWithValues: store.widgets.map { ($0.id.uuidString, $0) })
                    store.setWidgetOrder(ids.compactMap { current[$0] })
                }
            )

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

            SettingsCard("Placement", systemImage: "rectangle.bottomthird.inset.filled") {
                Picker("Screen edge", selection: Binding(get: { store.effectivePosition }, set: { store.position = $0 })) {
                    ForEach(DockPlacementPolicy.allowedEdges(appleDock: appleDock.edge)) { position in
                        Text(position.title).tag(position)
                    }
                }
                .pickerStyle(.segmented)

                Text("Apple’s Dock is on the \(appleDock.edge.title.lowercased()). OpenDock keeps that edge free and moves automatically when it changes.")
                    .font(.caption).foregroundStyle(.secondary)

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

}

struct SurfaceThemePicker: View {
    let surface: ThemeSurface

    @ObservedObject private var theme = ThemeStore.shared
    @State private var selectedForPairing: ThemePreset?

    private let presets =
        ThemePreset.macSpacesPresets + ThemePreset.terminalPresets

    var body: some View {
        SettingsCard("Theme", systemImage: "paintpalette") {
            Text("Choose one palette for \(surface.title). The same modern widget style is used everywhere.")
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

            DisclosureGroup("Fine-tune appearance") {
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
    @State private var surface: ThemeSurface = .notch

    var body: some View {
        SettingsPage(title: "Theme", subtitle: "One clean widget style. Colors for your whole workspace.") {
            Picker("Surface", selection: $surface) {
                Text("OpenNotch").tag(ThemeSurface.notch)
                Text("OpenDock").tag(ThemeSurface.dock)
            }.pickerStyle(.segmented)
            SurfaceThemePicker(surface: surface)
            SettingsCard("Motion", systemImage: "sparkles") {
                Toggle("Reduce motion", isOn: $theme.reduceMotionPreference)
            }
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
