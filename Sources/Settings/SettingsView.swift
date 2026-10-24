import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreLocation
import ApplicationServices
import UserNotifications
import CoreBluetooth
import Contacts

@MainActor
final class SettingsNavigationModel: ObservableObject {
    static let shared = SettingsNavigationModel()
    @Published var selection: SettingsDestination = .general
    @Published var searchTarget: String?
    @Published var searchQuery = ""

    func open(_ destination: SettingsDestination, card: String? = nil) {
        searchQuery = ""
        selection = destination
        searchTarget = card
    }
}

struct SettingsView: View {
    static let titleBarHeight: CGFloat = 28
    @ObservedObject private var navigation = SettingsNavigationModel.shared
    @ObservedObject private var appearance = ThemeStore.shared

    private var query: String {
        get { navigation.searchQuery }
        nonmutating set { navigation.searchQuery = newValue }
    }
    @State private var resultIndex = 0
    @State private var compactSearch = false
    @FocusState private var searchFocused: Bool

    private var results: [SettingsSearchEntry] { SettingsSearch.matches(query) }

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
                    .scrollContentTopMargin(Self.titleBarHeight)
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
        .background {
            Button { compactSearch = true; searchFocused = true } label: { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .onChange(of: query) { _ in resultIndex = 0 }
        .onChange(of: navigation.selection) { _ in query = ""; compactSearch = false }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search settings", text: $navigation.searchQuery)
                .textFieldStyle(.plain)
                .focused($searchFocused)
                .accessibilityLabel("Search settings")
                .tint(Color.primary)
                .onSubmit { if results.indices.contains(resultIndex) { openResult(results[resultIndex]) } }
                .textFieldKeys(up: { resultIndex = max(0, resultIndex - 1) },
                               down: { resultIndex = min(max(0, results.count - 1), resultIndex + 1) },
                               escape: { query = ""; searchFocused = false; compactSearch = false })
            if !query.isEmpty {
                Button { query = ""; navigation.searchTarget = nil } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }.buttonStyle(.plain).accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12).frame(height: 34)
        .background(Color.primary.opacity(searchFocused ? 0.09 : 0.06), in: Capsule())
        .overlay { Capsule().strokeBorder(Color.primary.opacity(searchFocused ? 0.18 : 0), lineWidth: 1) }
    }

    private func openResult(_ result: SettingsSearchEntry) {
        query = ""; compactSearch = false; searchFocused = false
        navigation.open(result.destination, card: result.card)
    }

    private var searchResults: some View {
        SettingsPage(title: "Search", subtitle: "\(results.count) matching section\(results.count == 1 ? "" : "s")",
                     scrollAnchor: results.indices.contains(resultIndex) ? "search." + results[resultIndex].id : nil) {
            if results.isEmpty {
                NoSearchResultsView(text: query)
            } else {
                VStack(spacing: 6) {
                    ForEach(results.indices, id: \.self) { index in
                        let result = results[index]
                        Button { openResult(result) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: result.destination.symbol).frame(width: 22)
                                    .foregroundStyle(appearance.notch.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.card).font(.system(size: 14, weight: .semibold))
                                    Text(result.destination.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12).contentShape(Rectangle())
                            .background(index == resultIndex ? appearance.notch.selected : appearance.notch.tile,
                                        in: RoundedRectangle(cornerRadius: 9))
                        }.buttonStyle(.plain).id("search." + result.id)
                    }
                }
            }
        }
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

            Group {
                if compact {
                    Button { compactSearch = true } label: { Image(systemName: "magnifyingglass").frame(maxWidth: .infinity, minHeight: 30) }
                        .buttonStyle(.plain).accessibilityLabel("Search settings")
                        .popover(isPresented: $compactSearch) {
                            searchField.frame(width: 240).padding(12).onAppear { searchFocused = true }
                        }
                } else { searchField }
            }
            .padding(.horizontal, compact ? 8 : 10).padding(.bottom, 12)

            VStack(spacing: 3) {
                // Small labels group the pages, like macOS sidebars; they don't collapse.
                let pages = SettingsDestination.allCases
                ForEach(Array(pages.enumerated()), id: \.element) { index, destination in
                    let previous = index > 0 ? pages[index - 1] : nil
                    if destination.section != previous?.section {
                        if !compact {
                            Text(destination.section.uppercased())
                                .font(.system(size: 10, weight: .semibold)).tracking(0.4)
                                .foregroundStyle(appearance.nookForeground.opacity(0.5))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.leading, 10).padding(.top, index > 0 ? 12 : 0).padding(.bottom, 2)
                                .accessibilityAddTraits(.isHeader)
                        } else if index > 0 {
                            Spacer().frame(height: 8)
                        }
                    }
                    sidebarItem(destination, compact: compact)
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
            query = ""; compactSearch = false
            navigation.open(destination)
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
        }
        .buttonStyle(.plain)
        .help(compact ? destination.title : "")
        .accessibilityLabel(destination.title)
    }

    @ViewBuilder
    private var detail: some View {
        if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            searchResults
        } else {
        switch navigation.selection {
        case .general: GeneralSettingsPane()
        case .apps: SettingsPage(title: "Apps", subtitle: "") {
            DockAppsCard(settings: NookSettings.shared)
        }
        case .widgets: NookSettingsPane()
        case .clipboard: ClipboardSettingsPane()
        case .appearance: AppearanceSettingsPane()
        case .permissions: SettingsPage(title: "Permissions", subtitle: "See what each widget can access, and why.") { WidgetAccessSettings() }
        case .activities: ActivitiesSettingsPane()
        case .files: FilesSettingsPane()
        }
        }
    }
}

struct NookThemePicker: View {
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Start closed so every appearance section is visible.
    @State private var open: Set<ThemeCollection> = {
        if NookThemePicker.startsFullyOpen { return Set(ThemeCollection.allCases) }
        return []
    }()
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)
    /// QA captures open every drawer to review all palettes at once.
    static var startsFullyOpen = false

    var body: some View {
        themeCard
    }

    private var themeCard: some View {
        SettingsCard("Theme", systemImage: "paintpalette") {
            Picker("Appearance", selection: $theme.appearanceMode) {
                ForEach(AppearanceMode.allCases) { mode in Text(mode.title).tag(mode) }
            }
            .pickerStyle(.segmented)
            .disabled(theme.family.fixedScheme != nil)

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
            if theme.family == .tinted {
                HStack(spacing: 18) {
                    ColorPicker("Tint", selection: hexBinding(\.tintedGlassTint, family: .tinted), supportsOpacity: false)
                    ColorPicker("Accent", selection: hexBinding(\.tintedGlassAccent, family: .tinted), supportsOpacity: false)
                    Toggle("Blur", isOn: $theme.tintedGlassBlurs)
                        .help("Frost the desktop behind the tint, or keep it perfectly clear")
                    Spacer()
                    Button("Reset") {
                        theme.tintedGlassTint = TintedGlassColors.defaultTint
                        theme.tintedGlassAccent = TintedGlassColors.defaultAccent
                        theme.tintedGlassStrength = TintedGlassColors.defaultStrength
                        theme.tintedGlassBlurs = true
                    }
                    .buttonStyle(.borderless)
                }
                .padding(.top, 6)
                HStack(spacing: 10) {
                    Text("Strength")
                    Slider(value: $theme.tintedGlassStrength, in: TintedGlassColors.strengthRange)
                    Text("\(Int((theme.tintedGlassStrength * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
                }
                Text("The tint colours the glass over your desktop; Strength sets how much of it covers what's behind. Text follows the tint, light on dark tints and dark on light ones, instead of the Appearance setting.")
                    .font(.caption).foregroundStyle(.secondary)
            }



        }
    }

    /// Edits one of a user-coloured theme's hex colours through a ColorPicker.
    private func hexBinding(_ key: ReferenceWritableKeyPath<ThemeStore, String>, family: ThemeFamily = .custom) -> Binding<Color> {
        Binding(
            get: { Color(themeHex: theme[keyPath: key]) ?? .gray },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                theme[keyPath: key] = String(format: "%02X%02X%02X",
                    Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()),
                    Int((rgb.blueComponent * 255).rounded()))
                if theme.family != family { theme.selectFamily(family) }
            })
    }

    private func drawer(_ collection: ThemeCollection) -> some View {
        let isOpen = open.contains(collection)
        let current: ThemeFamily? = collection.families.contains(theme.family) ? theme.family : nil
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
                        if family.isUserColoured {
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
                        RoundedRectangle(cornerRadius: 6).fill(palette.color(palette.surface).opacity(family.glassTint == nil ? 1 : 0.55))
                    }.frame(height: 34)
                }
                .padding(12)
                .background {
                    ZStack {
                        if let tint = family.glassTint {
                            // Glass: a stand-in desktop seen through the pane, sharp behind Clear
                            // and frosted behind the rest, under the theme's real tint.
                            GlassPreviewDesktop(blur: family.glassBlurs ? 9 : 0)
                            palette.color(palette.background).opacity(tint)
                            if family.glassBlurs {
                                GlassSheen(dark: (family.fixedScheme ?? theme.resolvedScheme) == .dark)
                            }
                        } else {
                            palette.color(palette.background)
                        }
                        if let motif = family.motif {
                            ThemeMotifView(motif: motif, accent: palette.color(palette.accent),
                                           ink: palette.color(palette.foreground), scale: 0.5, strength: 1.8,
                                           softensCenter: false, thumbnail: true)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(
                    selected ? theme.notch.accent : family.glassTint != nil ? Color.white.opacity(0.5) : Color.primary.opacity(0.10),
                    lineWidth: selected ? 2 : 1))
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

/// A small, fixed stand-in for the desktop behind Glass theme cards, drawn in a
/// Canvas so its blur also shows in captures.
private struct GlassPreviewDesktop: View {
    var blur: CGFloat = 0

    var body: some View {
        Canvas { context, size in
            let all = CGRect(origin: .zero, size: size)
            context.fill(Path(all), with: .linearGradient(
                Gradient(colors: [Color(red: 0.30, green: 0.45, blue: 0.78), Color(red: 0.52, green: 0.40, blue: 0.70)]),
                startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)))
            if blur > 0 { context.addFilter(.blur(radius: blur)) }
            let sun = size.height * 0.9
            context.fill(Path(ellipseIn: CGRect(x: size.width * 0.78 - sun / 2, y: size.height * 0.30 - sun / 2, width: sun, height: sun)),
                         with: .color(Color(red: 0.98, green: 0.70, blue: 0.40)))
            context.fill(Path(roundedRect: CGRect(x: size.width * 0.09, y: size.height * 0.55, width: size.width * 0.42, height: size.height * 0.34),
                              cornerRadius: 6), with: .color(.white.opacity(0.85)))
        }
    }
}

private struct AppearanceSettingsPane: View {
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Choose a theme. The Nook takes care of its size and styling.") {
            NookThemePicker()
            LyricStylePicker()
            SettingsCard("Motion", systemImage: "sparkles") {
                Toggle("Reduce motion", isOn: $theme.reduceMotionPreference)
                    .help("Theme effects and lyric motion hold still, and transitions are simpler. macOS's own Reduce Motion does the same.")
                Toggle("Trackpad haptics", isOn: $theme.hapticsEnabled)
            }
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
                                animated: hovered == style && !reduceMotion,
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

/// Automatic update preferences and the manual check, shown in General.
struct SoftwareUpdateCard: View {
    @ObservedObject private var updater = UpdateService.shared

    private var channel: String {
        updater.followsPrereleases ? "Pre-release · gets every new build" : "Stable release"
    }
    var body: some View {
        SettingsCard("Updates", systemImage: "arrow.triangle.2.circlepath") {
            HStack(spacing: 12) {
                MacSpacesMark(size: 36)
                VStack(alignment: .leading, spacing: 3) {
                    Text("MacSpaces \(installedVersion)").font(.system(size: 14, weight: .semibold))
                        .help(installedBuild.map { "Build \($0)" } ?? "")
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
        }
    }

    /// Just the version ("3.0"). The build number only orders updates, so it's kept
    /// out of sight and shown on hover (owner, after 3.0).
    private var installedVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
    }

    private var installedBuild: String? {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
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
