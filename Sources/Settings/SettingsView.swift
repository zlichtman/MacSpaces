import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreLocation
import ApplicationServices
import UserNotifications

enum SettingsDestination: String, CaseIterable, Identifiable {
    case notch
    case theme
    case permissions
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .notch: return "Nook"
        case .theme: return "Theme"
        case .permissions: return "Permissions"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .notch: return "macbook.gen2"
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
        case .theme: ThemeSettingsPane()
        case .permissions: PermissionsSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}

struct SurfaceThemePicker: View {
    let surface: ThemeSurface

    @ObservedObject private var theme = ThemeStore.shared

    private let presets =
        ThemePreset.macSpacesPresets + ThemePreset.terminalPresets

    var body: some View {
        SettingsCard("Theme", systemImage: "paintpalette") {
            Text("Choose a palette for your Nook. Every widget shares one clean, modern style.")
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
        SettingsPage(title: "Theme", subtitle: "Make your Nook feel at home.") {
            SurfaceThemePicker(surface: .notch)
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
                    title: "Media apps & browsers",
                    detail: "Now Playing metadata fallback",
                    symbol: "music.note",
                    status: .review,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"
                )
            }

            SettingsCard("Weather", systemImage: "cloud.sun") {
                PermissionRow(title: "Location", detail: "Local weather when the Weather widget is enabled", symbol: "location", status: locationStatus,
                    settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
            }
            SettingsCard("Privacy", systemImage: "lock.shield") {
                Label("Clipboard history, notes, profiles, and tray items stay on this Mac.", systemImage: "checkmark.shield")
                Label("Weather, lyrics, and app updates use their respective online services.", systemImage: "network")
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
                Text("Music, focus, files and everyday tools. One thoughtfully arranged Nook.")
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
