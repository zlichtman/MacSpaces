import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreLocation
import ApplicationServices
import UserNotifications
import CoreBluetooth

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, widgets, clipboard, appearance, permissions, activities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .widgets: return "Widgets"
        case .clipboard: return "Clipboard"
        case .appearance: return "Appearance"
        case .permissions: return "Permissions"
        case .activities: return "Activities"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .widgets: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        case .appearance: return "paintpalette"
        case .permissions: return "hand.raised"
        case .activities: return "waveform.path.ecg"
        }
    }
}

@MainActor
final class SettingsNavigationModel: ObservableObject {
    static let shared = SettingsNavigationModel()
    @Published var selection: SettingsDestination = .general
}

struct SettingsView: View {
    static let titleBarHeight: CGFloat = 28
    @ObservedObject private var navigation = SettingsNavigationModel.shared
    @ObservedObject private var appearance = ThemeStore.shared

    /// Always fills the window it's given, pinned to the leading edge. macOS
    /// window tiling can make a window narrower than its minimum size; the
    /// sidebar then shrinks to icons instead of the layout overflowing.
    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 720
            HStack(spacing: 0) {
                sidebar(compact: compact)
                    .frame(width: compact ? 60 : 214)

                Rectangle()
                    .fill(appearance.notch.border)
                    .frame(width: 1)

                detail
                    // Pages start below the title bar but scroll up under it,
                    // fading out, so there's no separate strip across the top.
                    .contentMargins(.top, Self.titleBarHeight, for: .scrollContent)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [appearance.notch.surface, appearance.notch.surface.opacity(0)],
                                       startPoint: .top, endPoint: .bottom)
                            .frame(height: Self.titleBarHeight + 8)
                            .allowsHitTesting(false)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        // The whole window, title bar included: the sidebar and its divider run to the top edge.
        .ignoresSafeArea(.container, edges: .top)
        .background(appearance.notch.surface)
        .foregroundStyle(appearance.nookForeground)
        .preferredColorScheme(appearance.notch.colorScheme)
        .tint(appearance.notch.accent)
    }

    private func sidebar(compact: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                MacSpacesMark(size: compact ? 30 : 34)
                if !compact {
                    Text("MacSpaces")
                        .font(.system(size: 15, weight: .bold))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, compact ? 15 : 16)
            .padding(.top, 20 + Self.titleBarHeight)
            .padding(.bottom, 16)

            VStack(spacing: 3) {
                ForEach(SettingsDestination.allCases) {
                    sidebarItem($0, compact: compact)
                }
            }
            .padding(.horizontal, compact ? 8 : 10)

            Spacer(minLength: 14)
        }
        .background(appearance.notch.tile)
    }

    private func sidebarItem(_ destination: SettingsDestination, compact: Bool) -> some View {
        let selected = navigation.selection == destination
        return Button {
            navigation.selection = destination
        } label: {
            HStack(spacing: 10) {
                Image(systemName: destination.symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(selected ? appearance.notch.accent : appearance.nookForeground.opacity(0.65))
                    .frame(width: 19)
                if !compact {
                    Text(destination.title)
                        .font(.system(size: 13, weight: selected ? .semibold : .medium))
                    Spacer(minLength: 0)
                }
            }
            .frame(maxWidth: compact ? .infinity : nil)
            .padding(.horizontal, compact ? 0 : 10)
            .frame(height: 34)
            .contentShape(Rectangle())
            .background(
                selected ? appearance.notch.selected : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
            .overlay(alignment: .leading) {
                if selected {
                    Capsule()
                        .fill(appearance.notch.accent)
                        .frame(width: 2, height: 16)
                        .offset(x: -1)
                }
            }
        }
        .buttonStyle(.plain)
        .help(compact ? destination.title : "")
        .accessibilityLabel(destination.title)
    }

    @ViewBuilder
    private var detail: some View {
        switch navigation.selection {
        case .general: GeneralSettingsPane()
        case .widgets: NookSettingsPane()
        case .clipboard: ClipboardSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .permissions: SettingsPage(title: "Permissions", subtitle: "See what each widget can access, and why.") { WidgetAccessSettings() }
        case .activities: ActivitiesSettingsPane()
        }
    }
}

struct NookThemePicker: View {
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Open drawers. Core and the drawer holding the current theme start open.
    @State private var open: Set<ThemeCollection> = {
        if NookThemePicker.startsFullyOpen { return Set(ThemeCollection.allCases) }
        var open: Set<ThemeCollection> = [.core]
        if let family = ThemeStore.shared.family { open.insert(family.collection) }
        return open
    }()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    /// QA captures open every drawer to review all palettes at once.
    static var startsFullyOpen = false

    var body: some View {
        SettingsCard("Theme", systemImage: "paintpalette") {
            Picker("Appearance", selection: $theme.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            .disabled(theme.family == nil || theme.family == .custom)
            Toggle("Theme effects", isOn: $theme.showsPatterns)
                .help("Petals, rain, rainbow keys and other effects behind the Nook, for themes that have one")
            Toggle("Animate theme effects", isOn: $theme.animatesEffects)
                .disabled(!theme.showsPatterns)
                .help("Effects move only while the Nook is open. With Reduce Motion on, they stay still.")

            VStack(spacing: 0) {
                ForEach(ThemeCollection.allCases) { collection in
                    if collection != .core { Divider() }
                    drawer(collection)
                }
            }
            .padding(.top, 4)

            if theme.family == .custom {
                HStack(spacing: 18) {
                    ColorPicker("Background", selection: hexBinding(\.customThemeBackground), supportsOpacity: false)
                    ColorPicker("Accent", selection: hexBinding(\.customThemeAccent), supportsOpacity: false)
                    Spacer()
                    Button("Reset") {
                        theme.customThemeBackground = CustomThemeColors.defaultBackground
                        theme.customThemeAccent = CustomThemeColors.defaultAccent
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.top, 6)
                Text("Text and tile colours follow your background, so everything stays readable. Custom uses its own light or dark look instead of the Appearance setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            if theme.notchPreset == .custom {
                Button {
                    theme.setPreset(.custom, for: .notch)
                } label: {
                    HStack {
                        Label("Saved custom colors", systemImage: "paintbrush.pointed")
                        Spacer()
                        if theme.family == nil { Image(systemName: "checkmark") }
                    }
                }
                .buttonStyle(.plain)
                .padding(.vertical, 6)
                if theme.family == nil {
                    Text("Your original custom colors are preserved. Choose a theme to use automatic appearance.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }


        }
    }

    /// Edits one of the Custom theme's hex colours through a ColorPicker.
    private func hexBinding(_ key: ReferenceWritableKeyPath<ThemeStore, String>) -> Binding<Color> {
        Binding(
            get: { Color(themeHex: theme[keyPath: key]) ?? .gray },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                theme[keyPath: key] = String(format: "%02X%02X%02X",
                    Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()),
                    Int((rgb.blueComponent * 255).rounded()))
                if theme.family != .custom { theme.selectFamily(.custom) }
            })
    }

    private func drawer(_ collection: ThemeCollection) -> some View {
        let isOpen = open.contains(collection)
        let current = theme.family.flatMap { collection.families.contains($0) ? $0 : nil }
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
                    if isOpen { open.remove(collection) } else { open.insert(collection) }
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: collection.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(collection.title).font(.system(size: 13, weight: .semibold))
                            Text("\(collection.families.count)").font(.caption).foregroundStyle(.tertiary)
                        }
                        Text(current.map { "Using \($0.title)" } ?? collection.subtitle)
                            .font(.caption)
                            .foregroundStyle(current == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.notch.accent))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.vertical, 10)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(collection.title) themes")
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")

            if isOpen {
                LazyVGrid(columns: columns, spacing: 14) {
                    ForEach(collection.families) { family in familyCard(family) }
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    private func familyCard(_ family: ThemeFamily) -> some View {
        let selected = theme.family == family
        let palette = family.palette(family.fixedScheme ?? theme.resolvedScheme)
        return Button { theme.selectFamily(family) } label: {
            VStack(alignment: .leading, spacing: 8) {
                VStack(spacing: 8) {
                    HStack {
                        Capsule().fill(palette.color(palette.accent)).frame(width: 22, height: 5)
                        Spacer()
                        if family == .custom {
                            Image(systemName: "paintpalette.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(palette.color(palette.foreground).opacity(0.7))
                        } else {
                            Circle().fill(palette.color(palette.foreground).opacity(0.25)).frame(width: 5, height: 5)
                        }
                    }
                    // Custom's palette icon must not make its card taller than the others.
                    .frame(height: 10)
                    HStack(spacing: 6) {
                        RoundedRectangle(cornerRadius: 6).fill(palette.color(palette.accent).opacity(0.20))
                        RoundedRectangle(cornerRadius: 6).fill(palette.color(palette.surface))
                    }.frame(height: 34)
                }
                .padding(12)
                .background {
                    ZStack {
                        palette.color(palette.background)
                        if theme.showsPatterns, let motif = family.motif {
                            ThemeMotifView(motif: motif, accent: palette.color(palette.accent),
                                           ink: palette.color(palette.foreground), scale: 0.5, strength: 1.8,
                                           softensCenter: false)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                    selected ? theme.notch.accent : Color.primary.opacity(0.10), lineWidth: selected ? 2 : 1))
                HStack(spacing: 4) {
                    Text(family.title).font(.system(size: 12, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(theme.notch.accent) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(family.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }


}

private struct AppearanceSettingsPane: View {
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Choose a theme. The Nook takes care of its size and styling.") {
            NookThemePicker()
            LyricStylePicker()
        }
    }
}

/// How the Music page sets lyrics, each previewed in the current theme.
/// Hovering a preview plays its motion.
struct LyricStylePicker: View {
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var hovered: LyricStyle?
    /// A drawer like the theme drawers: closed until opened.
    @State private var isOpen = false
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 3)

    var body: some View {
        SettingsCard("Lyrics", systemImage: "quote.bubble") {
            Button {
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) { isOpen.toggle() }
            } label: {
                HStack(spacing: 10) {
                    VStack(alignment: .leading, spacing: 1) {
                        Text("Lyric style").font(.system(size: 13, weight: .semibold))
                        Text("Using \(theme.lyricStyle.title)").font(.caption).foregroundStyle(theme.notch.accent)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isOpen ? 90 : 0))
                }
                .padding(.vertical, 6)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Lyric styles")
            .accessibilityValue(isOpen ? "Expanded" : "Collapsed")
            if isOpen {
                Text("How the Music page sets the current lyric. Every style uses your theme's colours.")
                    .font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                LazyVGrid(columns: columns, spacing: 12) {
                    ForEach(LyricStyle.allCases) { style in tile(style) }
                }
                .transition(.opacity)
            }
        }
    }

    private func tile(_ style: LyricStyle) -> some View {
        let selected = theme.lyricStyle == style
        return Button { theme.lyricStyle = style } label: {
            VStack(alignment: .leading, spacing: 6) {
                StyledLyricView(style: style, current: style == .stickers ? "My heart keeps time with the city" : "Hold the evening light a little longer",
                                upcoming: "Till the harbour lamps come on",
                                accent: theme.notch.accent, ink: theme.nookForeground,
                                animated: hovered == style && !reduceMotion && theme.animatesEffects,
                                progress: 0.55)
                    .padding(10)
                    .frame(height: 96)
                    .background(theme.notch.surface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(selected ? theme.notch.accent : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1))
                    .environment(\.colorScheme, .dark)
                HStack(spacing: 5) {
                    Text(style.title).font(.system(size: 11, weight: selected ? .semibold : .medium))
                    if selected { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)).foregroundStyle(theme.notch.accent) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 ? style : (hovered == style ? nil : hovered) }
        .help(style.summary)
        .accessibilityLabel(style.title)
        .accessibilityHint(style.summary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Read-only permission status; visiting this page never starts a feature.
/// Each permission names the widgets that use it, and only permissions that
/// an enabled widget needs can be flagged as missing.
struct WidgetAccessSettings: View {
    @State private var accessRevision = 0
    @ObservedObject private var settings = NookSettings.shared
    @MainActor private static let locationManager = CLLocationManager()

    private struct AccessItem: Identifiable {
        let title: String
        let symbol: String
        let usedBy: [NookWidgetKind]
        let status: PermissionState
        let settingsURL: String
        var id: String { title }
    }

    private var enabledKinds: Set<NookWidgetKind> { Set(settings.profiles.flatMap(\.widgets)) }

    private var items: [AccessItem] {
        [
            .init(title: "Automation", symbol: "gearshape.2", usedBy: [.media, .quickActions, .notifications], status: .review,
                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation"),
            .init(title: "Accessibility", symbol: "list.number", usedBy: [.clipboard],
                  status: AXIsProcessTrusted() ? .granted : .notRequested,
                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"),
            .init(title: "Calendars", symbol: "calendar", usedBy: [.calendar], status: eventStatus(.event),
                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"),
            .init(title: "Reminders", symbol: "checklist", usedBy: [.todos], status: eventStatus(.reminder),
                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Reminders"),
            .init(title: "Camera", symbol: "camera", usedBy: [.mirror], status: mediaStatus(AVCaptureDevice.authorizationStatus(for: .video)),
                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera"),
            .init(title: "Location", symbol: "location", usedBy: [.weather], status: locationStatus,
                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_LocationServices"),
            .init(title: "Bluetooth", symbol: "headphones", usedBy: [.battery], status: bluetoothStatus,
                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_Bluetooth"),
            .init(title: "Full Disk Access", symbol: "bubble.left.and.bubble.right", usedBy: [.notifications], status: .review,
                  settingsURL: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles")
        ]
    }

    var body: some View {
        let inUse = items.filter { !enabledKinds.isDisjoint(with: $0.usedBy) }
        let unused = items.filter { enabledKinds.isDisjoint(with: $0.usedBy) }
        SettingsCard("Used by your widgets", systemImage: "hand.raised") {
            HStack(alignment: .top) {
                Text("macOS asks the first time a widget needs access. Nothing here requests access.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                RefreshButton("Refresh") { accessRevision += 1 }
                    .buttonStyle(.borderless)
            }
            if inUse.isEmpty {
                Text("Your widgets don't need any special access.").font(.system(size: 13)).padding(.vertical, 6)
            }
            ForEach(inUse) { row($0, inUse: true) }
        }
        .id(accessRevision)
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in accessRevision += 1 }

        if !unused.isEmpty {
            SettingsCard("Not used right now", systemImage: "moon.zzz") {
                Text("These are only needed if you add the widgets listed.").font(.caption).foregroundStyle(.secondary)
                ForEach(unused) { row($0, inUse: false) }
            }
            .id("unused-\(accessRevision)")
        }
    }

    private func row(_ item: AccessItem, inUse: Bool) -> some View {
        PermissionRow(title: item.title,
                      detail: "Used by " + ListFormatter.localizedString(byJoining: item.usedBy.map(\.title)),
                      symbol: item.symbol,
                      status: inUse ? item.status : (item.status == .granted ? .granted : .notRequested),
                      settingsURL: item.settingsURL)
            .opacity(inUse ? 1 : 0.7)
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

    private var bluetoothStatus: PermissionState {
        switch CBCentralManager.authorization {
        case .allowedAlways: return .granted
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

private enum PermissionState: Hashable {
    case granted
    case notRequested
    case notGranted
    case review

    var title: String {
        switch self {
        case .granted: return "Allowed"
        case .notRequested: return "Asks when used"
        case .notGranted: return "Open Settings"
        case .review: return "Review"
        }
    }

    var symbol: String? {
        switch self {
        case .granted: return "checkmark.circle.fill"
        case .notGranted: return "exclamationmark.circle.fill"
        default: return nil
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
            if status == .notGranted || status == .review {
                Button {
                    guard let url = URL(string: settingsURL) else { return }
                    NSWorkspace.shared.open(url)
                } label: {
                    Label(status.title, systemImage: status.symbol ?? "arrow.up.forward.app")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(status.color)
            } else {
                HStack(spacing: 4) {
                    if let symbol = status.symbol { Image(systemName: symbol) }
                    Text(status.title)
                }
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(status.color)
            }
        }
        .padding(.vertical, 3)
    }
}

/// Automatic update preferences and the manual check, shown in General.
struct SoftwareUpdateCard: View {
    @ObservedObject private var updater = UpdateService.shared

    private var channel: String {
        updater.followsPrereleases ? "Pre-release · gets every new 2.x build" : "Stable release"
    }
    var body: some View {
        SettingsCard("Updates", systemImage: "arrow.triangle.2.circlepath") {
            HStack(spacing: 12) {
                MacSpacesMark(size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacSpaces \(installedVersion)").font(.system(size: 14, weight: .semibold))
                    Text(updater.status == .idle ? channel : updater.status.label)
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Button(updater.actionLabel) { updater.performPrimaryAction() }
                    .buttonStyle(.bordered).disabled(updater.isBusy)
            }
            Divider()
            Toggle("Check automatically", isOn: $updater.automaticallyCheckForUpdates)
            if updater.automaticallyCheckForUpdates {
                Toggle("Download updates when available", isOn: $updater.automaticallyInstallUpdates)
            }
            Text("Updates come from GitHub and are signature-verified. MacSpaces asks before restarting to install.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var installedVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        // Versions like 2.32 already end in their build; older ones show it.
        guard let build, !version.hasSuffix(".\(build)") else { return version }
        return "\(version) (\(build))"
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
                // The master artwork is full-bleed; round it like a Dock icon.
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .clipShape(RoundedRectangle(cornerRadius: size * 0.225, style: .continuous))
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
