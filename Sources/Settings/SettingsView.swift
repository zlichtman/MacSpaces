import SwiftUI
import AppKit
import AVFoundation
import EventKit
import CoreLocation
import ApplicationServices
import UserNotifications
import CoreBluetooth

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
                    .fill(appearance.settings.border)
                    .frame(width: 1)

                detail
                    // Pages start below the title bar but scroll up under it,
                    // fading out, so there's no separate strip across the top.
                    .scrollContentTopMargin(Self.titleBarHeight)
                    .overlay(alignment: .top) {
                        LinearGradient(colors: [appearance.settings.surface, appearance.settings.surface.opacity(0)],
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
        .background(appearance.settings.surface)
        .foregroundStyle(appearance.settingsForeground)
        .preferredColorScheme(appearance.settings.colorScheme)
        .tint(appearance.settings.accent)
        .background {
            Button { compactSearch = true; searchFocused = true } label: { EmptyView() }
                .keyboardShortcut("f", modifiers: .command)
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
        }
        .onChange(of: query) { _ in resultIndex = 0 }
        .onChange(of: navigation.selection) { _ in query = ""; compactSearch = false }
    }

    private var searchField: some View {
        SettingsSearchField(text: $navigation.searchQuery, focused: searchFocused,
                            onClear: { navigation.searchTarget = nil }) {
            TextField("Search settings", text: $navigation.searchQuery)
                .focused($searchFocused)
                .accessibilityLabel("Search settings")
                .onSubmit { if results.indices.contains(resultIndex) { openResult(results[resultIndex]) } }
                .textFieldKeys(up: { resultIndex = max(0, resultIndex - 1) },
                               down: { resultIndex = min(max(0, results.count - 1), resultIndex + 1) },
                               escape: { query = ""; searchFocused = false; compactSearch = false })
        }
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
                                    .foregroundStyle(appearance.settings.accent)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(result.card).font(.system(size: 14, weight: .semibold))
                                    Text(result.destination.title).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                            }
                            .padding(12).contentShape(Rectangle())
                            .background(index == resultIndex ? appearance.settings.selected : appearance.settings.tile,
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
                                .foregroundStyle(appearance.settingsForeground.opacity(0.5))
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
        .background(appearance.settings.tile)
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
                    .foregroundStyle(selected ? appearance.settings.accent : appearance.settingsForeground.opacity(0.65))
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
                selected ? appearance.settings.selected : Color.clear,
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
            WispSettingsCard()
            SpotifySettingsCard()
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

private struct AppearanceSettingsPane: View {
    @ObservedObject private var theme = ThemeStore.shared
    /// Off by default. Turning it on asks for the music folder; cancelling leaves it off.
    @AppStorage(LocalCovers.enabledKey) private var localFileCovers = false
    /// The chosen folder's bookmark; unset with the switch on reads the folders Spotify names.
    @AppStorage(LocalCovers.folderKey) private var musicFolder: Data?
    var body: some View {
        SettingsPage(title: "Appearance", subtitle: "Choose a theme. The Nook takes care of its size and styling.") {
            NookThemePicker()
            LyricStylePicker()
            AsciiArtPicker()
            SettingsCard("Album covers", systemImage: "photo") {
                Toggle("Show covers and lyrics from your local music files", isOn: Binding(
                    get: { localFileCovers },
                    set: { on in
                        guard on else { localFileCovers = false; return }
                        guard musicFolder == nil else {
                            localFileCovers = true
                            LocalCovers.shared.switchedOn()
                            return
                        }
                        chooseMusicFolder { chosen in
                            guard chosen else { return }
                            localFileCovers = true
                            LocalCovers.shared.switchedOn()
                        }
                    }))
                musicFolderRow
                Text("Spotify shares no cover for songs it plays from your own files. MacSpaces can read the cover saved in the file, and its lyrics when it has them, from the folder you choose, using Spotify's list of your local files. Nothing is sent anywhere.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            SettingsCard("Motion", systemImage: "sparkles") {
                Toggle("Reduce motion", isOn: $theme.reduceMotionPreference)
                    .help("Theme effects and lyric motion hold still, and transitions are simpler. macOS's own Reduce Motion does the same.")
                Toggle("Trackpad haptics", isOn: $theme.hapticsEnabled)
            }
        }
    }

    /// Asks for the music folder in a sheet on Settings; calls back with whether one was kept.
    /// Choosing it in the panel is what grants access, so macOS asks nothing more.
    private func chooseMusicFolder(completion: @escaping (Bool) -> Void) {
        let panel = LocalCovers.folderPanel()
        SettingsWindowController.shared.runPanel(panel) { chosen in
            completion(chosen && panel.url.map(LocalCovers.keepFolder) == true)
        }
    }

    /// The chosen folder with Change and Remove; with the switch on and none chosen (turned on
    /// before folders were asked for), a note and Choose Folder.
    @ViewBuilder private var musicFolderRow: some View {
        if let musicFolder {
            let info = LocalCovers.folderInfo(musicFolder)
            HStack(spacing: 8) {
                Image(systemName: "folder.fill").foregroundStyle(.secondary)
                Text(info?.name ?? "Folder not found")
                    .lineLimit(1).truncationMode(.middle)
                    .help(info?.path ?? "Choose the folder again.")
                Spacer()
                Button("Change") { chooseMusicFolder { _ in } }
                    .buttonStyle(.settings())
                Button("Remove") { LocalCovers.removeFolder() }
                    .buttonStyle(.settings(.destructive))
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Music folder")
        } else if localFileCovers {
            HStack(spacing: 8) {
                Text("Reading the folders Spotify lists. Choose a folder to read only that one.")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Choose Folder") { chooseMusicFolder { _ in } }
                    .buttonStyle(.settings())
            }
        }
    }
}

/// One shared stage keeps each style readable at the Music page's scale.
/// Hover previews a choice; only a click changes the saved style.
struct LyricStylePicker: View {
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.controlActiveState) private var controlActiveState
    @State private var hovered: LyricStyle?
    @State private var previewHovered = false
    @FocusState private var focusedStyle: LyricStyle?

    private var previewStyle: LyricStyle { hovered ?? focusedStyle ?? theme.lyricStyle }
    private var playing: Bool {
        (hovered != nil || previewHovered) && controlActiveState != .inactive
            && !reduceMotion && !theme.reduceMotion
    }

    var body: some View {
        SettingsCard("Lyrics", systemImage: "quote.bubble") {
            HStack(alignment: .top, spacing: 16) {
                VStack(spacing: 3) {
                    ForEach(LyricStyle.allCases) { style in
                        styleButton(style)
                    }
                }
                .frame(width: 152)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Lyric styles")

                preview
            }
        }
        .onChange(of: controlActiveState) { state in
            if state == .inactive {
                hovered = nil
                previewHovered = false
            }
        }
        .onDisappear {
            hovered = nil
            previewHovered = false
        }
    }

    private var preview: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "quote.opening")
                    .font(.system(size: 10, weight: .semibold))
                Text("Preview")
                    .font(.system(size: 10, weight: .semibold))
                    .tracking(0.6)
                Spacer(minLength: 8)
                if !reduceMotion && !theme.reduceMotion {
                    Text(playing ? "Playing" : "Hover to play")
                        .font(.system(size: 10, weight: .medium))
                }
            }
            .foregroundStyle(theme.nookForeground.opacity(0.45))
            .frame(height: 16)
            .accessibilityHidden(true)

            LyricStyleSample(style: previewStyle, accent: theme.notch.accent,
                             ink: theme.nookForeground, playing: playing)
                .id(previewStyle)
                .frame(height: 130)
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            Text(previewStyle.summary)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(theme.nookForeground.opacity(0.55))
                .lineLimit(2)
                .frame(maxWidth: .infinity, minHeight: 28, alignment: .bottomLeading)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .frame(height: max(252, CGFloat(LyricStyle.allCases.count * 36 - 3)))
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(theme.notch.surface)
                .overlay {
                    LinearGradient(colors: [theme.notch.accent.opacity(0.06), .clear],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(theme.nookForeground.opacity(0.10), lineWidth: 1)
        }
        .environment(\.colorScheme, theme.notch.colorScheme)
        .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onHover { previewHovered = $0 }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(previewStyle.title) preview")
        .accessibilityValue(previewStyle.summary)
    }

    private func styleButton(_ style: LyricStyle) -> some View {
        let selected = theme.lyricStyle == style
        let previewed = hovered == style || focusedStyle == style
        return Button {
            theme.lyricStyle = style
            focusedStyle = style
        } label: {
            HStack(spacing: 8) {
                Text(style.title)
                    .font(.system(size: 12, weight: selected ? .semibold : .medium))
                    .foregroundStyle(theme.settingsForeground.opacity(selected || previewed ? 1 : 0.65))
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: selected ? "checkmark.circle.fill" : "play.fill")
                    .font(.system(size: selected ? 13 : 9, weight: .semibold))
                    .foregroundStyle(selected ? theme.settings.accent : theme.settingsForeground.opacity(0.45))
                    .opacity(selected || previewed ? 1 : 0)
                    .frame(width: 14)
            }
            .padding(.horizontal, 10)
            .frame(height: 33)
            .background(selected ? theme.settings.accent.opacity(0.13)
                        : theme.settingsForeground.opacity(previewed ? 0.055 : 0),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(selected ? theme.settings.accent.opacity(0.32) : .clear, lineWidth: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focused($focusedStyle, equals: style)
        .onHover { hovered = $0 ? style : (hovered == style ? nil : hovered) }
        .accessibilityLabel(style.title)
        .accessibilityHint(style.summary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Synthetic lyrics only: no player, permissions or lyric service. The sleeping
/// task advances lines; just Karaoke and Typewriter need a clock between lines.
private struct LyricStyleSample: View {
    let style: LyricStyle
    let accent: Color
    let ink: Color
    let playing: Bool
    @State private var sequence = 0
    @State private var lineStarted = Date()

    private static let lineDuration: TimeInterval = 4.8
    private static let lines = [
        "Watch the flowers open for you",
        "Let the rain carry yesterday away",
        "Take the moonlight all the way home"
    ]

    var body: some View {
        Group {
            if playing && style.followsSong {
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { context in
                    lyric(elapsed: max(0, context.date.timeIntervalSince(lineStarted)))
                }
            } else {
                lyric(elapsed: 0)
            }
        }
        .animation(playing ? .easeInOut(duration: 0.24) : nil, value: sequence)
        .task(id: playing) {
            guard playing else { return }
            sequence = 0
            lineStarted = Date()
            while !Task.isCancelled {
                do {
                    try await Task.sleep(nanoseconds: UInt64(Self.lineDuration * 1_000_000_000))
                } catch { return }
                guard !Task.isCancelled else { return }
                sequence += 1
                lineStarted = Date()
            }
        }
    }

    private func lyric(elapsed: TimeInterval) -> some View {
        let index = playing ? sequence % Self.lines.count : 0
        return StyledLyricView(style: style, current: Self.lines[index],
                               upcoming: Self.lines[(index + 1) % Self.lines.count],
                               accent: accent, ink: ink, animated: playing,
                               sequence: playing ? sequence : 0,
                               progress: min(1, elapsed / (Self.lineDuration * 0.85)),
                               typed: playing ? min(1, elapsed / 1.1) : 1,
                               span: 0...Self.lineDuration, songTime: 0, playing: playing)
    }
}

/// Automatic update preferences and the manual check, shown in General.
struct SoftwareUpdateCard: View {
    @ObservedObject private var updater = UpdateService.shared

    private var updateAvailable: Bool {
        if case .available = updater.status { return true }
        return false
    }
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
                    .buttonStyle(.settings(updateAvailable ? .primary : .secondary)).disabled(updater.isBusy)
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
