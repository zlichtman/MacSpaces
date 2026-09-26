import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreLocation
import ApplicationServices
import UserNotifications

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, widgets, appearance, activities, about

    static var primary: [Self] { [.general, .widgets, .appearance, .activities] }
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .widgets: return "Widgets"
        case .appearance: return "Appearance"
        case .activities: return "Activities"
        case .about: return "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .widgets: return "square.grid.2x2"
        case .appearance: return "paintpalette"
        case .activities: return "waveform.path.ecg"
        case .about: return "info.circle"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    static let shared = SettingsNavigationModel()
    @Published var selection: SettingsDestination = .general
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
                ForEach(SettingsDestination.primary) {
                    sidebarItem($0)
                }
            }
            .padding(.horizontal, 10)

            Spacer(minLength: 14)
            Divider().padding(.horizontal, 20)
            sidebarItem(.about)
                .padding(10)
                .padding(.bottom, 8)
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
        case .general: GeneralSettingsPane()
        case .widgets: NookSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .activities: ActivitiesSettingsPane()
        case .about: AboutSettingsPane()
        }
    }
}

struct NookThemePicker: View {
    private let surface = ThemeSurface.notch

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
                value: $theme.notchThemeIntensity,
                range: 0...1,
                valueText: "\(Int(theme.notchThemeIntensity * 100))%"
            )
            SettingsSlider(
                title: "Widget definition",
                value: $theme.notchTileContrast,
                range: 0...1,
                valueText: "\(Int(theme.notchTileContrast * 100))%"
            )
            SettingsSlider(
                title: "Ambient glow",
                value: $theme.notchGlowStrength,
                range: 0...1,
                valueText: "\(Int(theme.notchGlowStrength * 100))%"
            )

            SettingsSlider(title: "Surface opacity", value: $theme.notchOpacity,
                range: 0.84...1, valueText: "\(Int(theme.notchOpacity * 100))%")
            SettingsSlider(title: "Corner radius", value: $theme.notchCornerRadius,
                range: 14...34, valueText: "\(Int(theme.notchCornerRadius)) pt")
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
            get: { Color(themeHex: theme.customNotchHex) ?? .black },
            set: { color in
                theme.customNotchHex = NSColor(color).themeHexString
                theme.setPreset(.custom, for: .notch)
            }
        )
    }
}

private struct AppearanceSettingsPane: View {
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Choose a palette and the size of your Nook.") {
            NookThemePicker()
            NookSizeSettings()
            SettingsCard("Motion", systemImage: "sparkles") {
                Toggle("Reduce motion", isOn: $theme.reduceMotionPreference)
                Toggle("Trackpad haptics", isOn: $theme.hapticsEnabled)
            }
        }
    }
}

/// Access belongs to the enabled widget, rather than a separate settings destination.
struct WidgetAccessSettings: View {
    @ObservedObject private var settings = NookSettings.shared
    @State private var accessRevision = 0
    @MainActor private static let locationManager = CLLocationManager()

    private var needsAccess: Bool {
        settings.widgets.contains { [.mirror, .calendar, .todos, .media, .weather].contains($0) }
    }

    var body: some View {
        if needsAccess {
            SettingsCard("Widget access", systemImage: "hand.raised") {
                Text("Only the widgets in this profile are listed. Access is requested when you use a feature.")
                    .font(.caption).foregroundStyle(.secondary)
                if settings.widgets.contains(.media) {
                    PermissionRow(title: "Music & browsers", detail: "Now Playing and lyrics", symbol: "music.note",
                        status: .review, settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
                }
                if settings.widgets.contains(.weather) {
                    PermissionRow(title: "Location", detail: "Weather near you; approximate location is used if unavailable", symbol: "location",
                        status: locationStatus, settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices")
                }
                if settings.widgets.contains(.calendar) {
                    PermissionRow(title: "Calendars", detail: "Your upcoming events", symbol: "calendar",
                        status: eventStatus(.event), settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars")
                }
                if settings.widgets.contains(.todos) {
                    PermissionRow(title: "Reminders", detail: "Your to-do list", symbol: "checklist",
                        status: eventStatus(.reminder), settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders")
                }
                if settings.widgets.contains(.mirror) {
                    PermissionRow(title: "Camera", detail: "Mirror preview", symbol: "camera",
                        status: cameraStatus, settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera")
                }
            }
            .id(accessRevision)
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                accessRevision += 1
            }
        }
    }

    private var cameraStatus: PermissionState {
        mediaStatus(AVCaptureDevice.authorizationStatus(for: .video))
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
    var body: some View {
        SettingsPage(
            title: "About MacSpaces",
            subtitle: "Version and project information."
        ) {
            VStack(spacing: 14) {
                MacSpacesMark(size: 82)
                Text("MacSpaces")
                    .font(.system(size: 25, weight: .bold, design: .rounded))
                Text("Version \(version)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Music, widgets and files at your notch.")
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
        }
    }

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }
}

/// Automatic update preferences and the manual check, shown in General.
struct SoftwareUpdateCard: View {
    @ObservedObject private var updater = UpdateService.shared

    var body: some View {
        SettingsCard("Software updates", systemImage: "arrow.triangle.2.circlepath") {
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
                VStack(alignment: .leading, spacing: 2) {
                    Text(updater.status.label)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("MacSpaces \(installedVersion)")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button(updater.actionLabel) {
                    updater.performPrimaryAction()
                }
                .buttonStyle(.bordered)
                .disabled(updater.isBusy)
            }
        }
    }

    private var installedVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.1"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        return build.map { "\(version) (\($0))" } ?? version
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
