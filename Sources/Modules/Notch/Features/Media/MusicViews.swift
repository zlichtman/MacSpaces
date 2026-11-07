import SwiftUI

/// The Music page's views, picked in the dock's middle group: the player, your Spotify stats,
/// your Spotify backups and where the sound plays.
enum MusicView: String, CaseIterable, Identifiable {
    case playing, stats, backups, devices
    static let defaultsKey = "music.view"
    /// Set when a song or artist is opened from Stats: coming back finds Stats still open, not
    /// the player (which every other way of leaving the page returns to).
    @MainActor static var keepOnReturn = false
    var id: String { rawValue }
    var title: String {
        switch self {
        case .playing: return "Playing"
        case .stats: return "Stats"
        case .backups: return "Backups"
        case .devices: return "Devices"
        }
    }
    var symbol: String {
        switch self {
        case .playing: return "play.fill"
        case .stats: return "chart.bar"
        case .backups: return "externaldrive"
        case .devices: return "hifispeaker"
        }
    }
}

/// The Music page with the view chosen in the dock.
struct MusicPage<Player: View>: View {
    @AppStorage(MusicView.defaultsKey) private var view: MusicView = .playing
    @ViewBuilder let player: () -> Player

    var body: some View {
        Group {
            switch view {
            case .playing: player()
            case .stats: MusicStatsView()
            case .backups: MusicBackupsView()
            case .devices: MusicDevicesView()
            }
        }
        // The titled views sit a little higher, closer to the panel's top edge than the player.
        .padding(.top, view == .playing ? 0 : -MusicPageHeader<EmptyView>.lift)
        // Stats and Backups are side trips: leaving the Music page (another tab, or the Nook
        // closing) brings it back to the player, except after opening a song from Stats.
        .onAppear {
            if MusicView.keepOnReturn { MusicView.keepOnReturn = false } else if view != .playing { view = .playing }
        }
        .onDisappear { if !MusicView.keepOnReturn, view != .playing { view = .playing } }
    }
}

/// The dock's middle group on the Music page: Playing, Stats and Backups (and Apple Music's
/// playlist when it's playing).
struct MusicViewButtons: View {
    @ObservedObject var nowPlaying: NowPlayingController
    @AppStorage(MusicView.defaultsKey) private var view: MusicView = .playing
    @ObservedObject private var theme = ThemeStore.shared
    @Namespace private var selection

    static func width(for info: NowPlayingInfo) -> CGFloat {
        CGFloat(MusicView.allCases.count * 33 + 5) + (MusicDockControls.hasPlaylist(for: info) ? 33 : 0)
    }

    var body: some View {
        HStack(spacing: 3) {
            ForEach(MusicView.allCases) { item in
                Button { withAnimation(Design.spring()) { view = item } } label: { icon(item) }
                    .buttonStyle(.plain)
                    .help(item.title).accessibilityLabel("Music: \(item.title)")
                    .accessibilityAddTraits(view == item ? .isSelected : [])
            }
            MusicDockControls(nowPlaying: nowPlaying)
                .foregroundStyle(theme.nookForeground.opacity(0.65))
        }
    }

    private func icon(_ item: MusicView) -> some View {
        let selected = view == item
        return Image(systemName: item.symbol).font(.system(size: 13, weight: .medium))
            .frame(width: 30, height: 30).contentShape(Circle())
            .foregroundStyle(selected ? theme.notch.accent : theme.nookForeground.opacity(0.65))
            .background {
                if selected {
                    Circle().fill(theme.notch.accent.opacity(0.14)).matchedGeometryEffect(id: "music-view", in: selection)
                }
            }
    }
}

/// Stats' and Backups' title, centred over the page, with any controls on the right.
struct MusicPageHeader<Trailing: View>: View {
    static var lift: CGFloat { 6 }
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    init(_ title: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.title = title
        self.trailing = trailing
    }

    var body: some View {
        ZStack {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            HStack { Spacer(minLength: 0); trailing() }
        }
        .frame(maxWidth: .infinity)
        .frame(height: TerminalTabMetrics.headerHeight)
    }
}

// MARK: - Stats

/// Spotify's own top songs (or artists) for one range at a time: all 50 as a wall of covers (or
/// pictures), ten across and five down, sized to fit with no scrolling, under a header in the same
/// place as Backups'. The panel grows to hold it all. Pointing at one shows its name in the line under
/// the wall (`MusicStatsCaptionBar`); clicking opens it in Spotify, and a song plays.
struct MusicStatsView: View {
    @ObservedObject private var spotify = SpotifyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @AppStorage("music.statsArtists") private var artists = false
    @State private var range: SpotifyLibrary.Range = .short
    @State private var hovered: Int?

    /// One tile: rank, title, detail line, picture and link.
    private struct Tile: Identifiable {
        let id: Int
        let title: String
        let detail: String?
        let image: URL?
        let link: URL?
    }

    var body: some View {
        if !spotify.isConnected {
            SpotifyConnectView(purpose: "Your top songs and artists over 4 weeks, 6 months and a year")
        } else {
            GeometryReader { proxy in
                let side = Self.tileSide(in: proxy.size)
                let columnGap = Self.columnGap(side: side, width: proxy.size.width)
                let width = side * CGFloat(Self.columns) + columnGap * CGFloat(Self.columns - 1)
                VStack(spacing: TerminalTabMetrics.gap) {
                    header.frame(height: TerminalTabMetrics.headerHeight)
                    if spotify.top != nil {
                        wall(side: side, columnGap: columnGap)
                            // Another list rebuilds the wall (tiles and pictures) rather than reusing tiles.
                            .id("\(artists)|\(range.rawValue)")
                        MusicStatsCaptionBar()
                    } else {
                        EmptyTabMessage(systemImage: "chart.bar", title: spotify.loadingTop ? "Loading your stats" : "No stats yet",
                                        detail: spotify.problem ?? "Spotify needs a little listening history first.") { EmptyView() }
                    }
                }
                // The header's chips line up with the wall's edges: one block, centred.
                .frame(width: width)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
            // Opening Stats or switching lists fetches anew when what's saved is stale; the load
            // carries on in the background if you leave, and lands when it's done.
            .task(id: artists) { spotify.refreshTop() }
            .onChange(of: range) { _ in hovered = nil }
            .onChange(of: artists) { _ in hovered = nil }
            .onChange(of: hovered) { publishCaption($0) }
            .onChange(of: tiles.first?.title) { _ in publishCaption(hovered) }
            .onAppear { publishCaption(hovered) }
            .onDisappear { showCaption(nil) }
        }
    }

    /// The tile pointed at, or the number one.
    private func publishCaption(_ index: Int?) {
        let list = tiles
        let tile = index.flatMap { index in list.first { $0.id == index } } ?? list.first
        showCaption(tile.map { .init(rank: $0.id + 1, title: $0.title, detail: $0.detail) })
    }

    /// Only its arriving and leaving animate, growing the panel; a new name just changes.
    private func showCaption(_ line: MusicStatsCaption.Line?) {
        let caption = MusicStatsCaption.shared
        guard caption.line != line else { return }
        if (caption.line == nil) != (line == nil), !theme.reduceMotion {
            withAnimation(Design.spring()) { caption.line = line }
        } else {
            caption.line = line
        }
    }

    private var tiles: [Tile] {
        guard let top = spotify.top else { return [] }
        if artists {
            return (top.artists[range.rawValue] ?? []).enumerated().map {
                Tile(id: $0.offset, title: $0.element.name, detail: nil, image: $0.element.image, link: $0.element.link)
            }
        }
        return (top.songs[range.rawValue] ?? []).enumerated().map {
            Tile(id: $0.offset, title: $0.element.title, detail: $0.element.artists, image: $0.element.image, link: $0.element.link)
        }
    }

    private static let columns = 10, rows = 5
    private static let rowGap: CGFloat = 4
    private static let columnGaps: ClosedRange<CGFloat> = 4...12
    /// Keeps the corner covers clear of the panel's rounded corners.
    private static let sideInset: CGFloat = 8

    /// The largest square tile that fits ten across and five down under the header.
    private static func tileSide(in size: CGSize) -> CGFloat {
        let across = (size.width - sideInset * 2 - columnGaps.lowerBound * CGFloat(columns - 1)) / CGFloat(columns)
        let down = (size.height - TerminalTabMetrics.headerHeight - MusicStatsCaptionBar.height - TerminalTabMetrics.gap * 2
                    - rowGap * CGFloat(rows - 1)) / CGFloat(rows)
        return max(10, min(across, down).rounded(.down))
    }

    /// The panel is wider than five rows' height allows, so the columns spread to its margins
    /// rather than leaving borders beside the wall.
    private static func columnGap(side: CGFloat, width: CGFloat) -> CGFloat {
        let spare = (width - sideInset * 2 - side * CGFloat(columns)) / CGFloat(columns - 1)
        return min(columnGaps.upperBound, max(columnGaps.lowerBound, spare.rounded(.down)))
    }

    private var header: some View {
        ZStack {
            Text("Stats").font(.system(size: 13, weight: .semibold)).lineLimit(1)
            HStack(spacing: 3) {
                ForEach(SpotifyLibrary.Range.allCases) { choice in
                    Button(choice.title) { range = choice }.buttonStyle(WidgetChipStyle(prominent: range == choice, height: 20))
                }
                Spacer(minLength: 0)
                Button("Songs") { artists = false }.buttonStyle(WidgetChipStyle(prominent: !artists, height: 20))
                Button("Artists") { artists = true }.buttonStyle(WidgetChipStyle(prominent: artists, height: 20))
            }
        }
    }

    private func wall(side: CGFloat, columnGap: CGFloat) -> some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(side), spacing: columnGap), count: Self.columns), spacing: Self.rowGap) {
            ForEach(tiles) { tile in
                Button {
                    guard let link = tile.link else { return }
                    MusicView.keepOnReturn = true
                    SpotifyLibrary.openInApp(link)
                } label: {
                    SpotifyThumbnail(url: tile.image, title: tile.title, round: artists, size: side)
                        .overlay {
                            RoundedRectangle(cornerRadius: artists ? side / 2 : max(4, side * 0.1), style: .continuous)
                                .strokeBorder(theme.notch.accent, lineWidth: 2).opacity(hovered == tile.id ? 1 : 0)
                        }
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { inside in
                    if inside { hovered = tile.id } else if hovered == tile.id { hovered = nil }
                }
                .help(tile.link == nil ? tile.title : "Show in Spotify")
                .accessibilityLabel("\(tile.id + 1), \(tile.title)\(tile.detail.map { ", \($0)" } ?? "")")
            }
        }
    }

}

/// The name of the tile pointed at on Stats, for the line under the wall.
@MainActor
final class MusicStatsCaption: ObservableObject {
    struct Line: Equatable {
        let rank: Int
        let title: String
        let detail: String?
    }

    static let shared = MusicStatsCaption()
    @Published var line: Line?
}

/// Three pieces under the wall while Stats shows: the number, the title and the artist of the
/// number one, or of the cover pointed at. They roll down one after another as Stats opens, then
/// stay up the whole time, so nothing moves under the pointer as it crosses the covers.
struct MusicStatsCaptionBar: View {
    static let height: CGFloat = 26
    /// How much taller the panel is on Stats: the name line and the full header, at the same cover size.
    static let panelGrowth: CGFloat = 48
    private static let gap: CGFloat = 5
    private static let rankWidth: CGFloat = 46
    private static let detailWidth: CGFloat = 190
    /// Between each piece as they roll down from under the Nook.
    private static let stagger = 0.05
    @ObservedObject private var caption = MusicStatsCaption.shared
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        if let line = caption.line {
            // Fixed pieces: the name changes as the pointer moves, never where anything sits.
            HStack(spacing: Self.gap) {
                pill(index: 0) {
                    Text("\(line.rank)")
                        .font(.system(size: 11, weight: .bold, design: .rounded)).monospacedDigit()
                        .foregroundStyle(theme.notch.accent)
                }
                .frame(width: Self.rankWidth)
                pill(index: 1) {
                    Text(line.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                }
                if let detail = line.detail {
                    pill(index: 2) {
                        Text(detail).font(.system(size: 12, weight: .medium)).lineLimit(1)
                    }
                    .frame(width: Self.detailWidth)
                }
            }
            .foregroundStyle(theme.nookForeground)
            .frame(maxWidth: .infinity)
            .clipped()
            .transition(.opacity)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

    private func pill<Content: View>(index: Int, @ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(.horizontal, 11)
            .frame(maxWidth: .infinity)
            .frame(height: Self.height)
            .background(theme.nookForeground.opacity(0.08), in: Capsule())
            .modifier(RollDown(distance: Self.height, delay: Double(index) * Self.stagger, still: theme.reduceMotion))
    }

    /// Each piece rolls itself up into place as it appears: a transition set on something inside the row
    /// wouldn't play, because it's the whole row that arrives.
    private struct RollDown: ViewModifier {
        let distance: CGFloat
        let delay: Double
        let still: Bool
        @State private var rolled = false

        func body(content: Content) -> some View {
            content
                .offset(y: rolled || still ? 0 : -distance)
                .opacity(rolled || still ? 1 : 0)
                .onAppear { withAnimation(Design.spring().delay(delay)) { rolled = true } }
        }
    }
}

// MARK: - Devices

/// Where the sound plays: every output the Mac already has, a tick on the current one. One click
/// moves the sound. It never scans for or connects anything.
struct MusicDevicesView: View {
    @ObservedObject private var outputs = AudioOutputs.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var holder = UUID()

    var body: some View {
        VStack(spacing: TerminalTabMetrics.gap) {
            MusicPageHeader("Devices") { EmptyView() }
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: TerminalTabMetrics.rowGap) {
                    ForEach(outputs.outputs) { output in
                        MusicDeviceRow(output: output, isCurrent: output.id == outputs.currentID, accent: theme.notch.accent) {
                            outputs.select(output.id)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { outputs.setNeeded(true, id: holder) }
        .onDisappear { outputs.setNeeded(false, id: holder) }
    }
}

private struct MusicDeviceRow: View {
    let output: AudioOutput
    let isCurrent: Bool
    let accent: Color
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: output.symbol).font(.system(size: 13))
                    .foregroundStyle(isCurrent ? accent : Color.secondary).frame(width: 18)
                Text(output.name).font(.system(size: 12, weight: .medium)).lineLimit(1)
                Spacer(minLength: 6)
                if isCurrent {
                    Image(systemName: "checkmark").font(.system(size: 10, weight: .bold)).foregroundStyle(accent)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: TerminalTabMetrics.rowHeight)
            .background(hovering ? Color.primary.opacity(0.09) : TerminalTabMetrics.fill,
                        in: RoundedRectangle(cornerRadius: TerminalTabMetrics.rowRadius, style: .continuous))
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(output.name)
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
    }
}

/// A song's cover or an artist's picture, or its first letter until it loads.
struct SpotifyThumbnail: View {
    let url: URL?
    let title: String
    let round: Bool
    var size: CGFloat = 26
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: round ? size / 2 : max(4, size * 0.1), style: .continuous)
        Group {
            // A file on this Mac (a demo's cover) draws at once; Spotify's load in the background.
            if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    shape.fill(theme.notch.accent.opacity(0.18))
                        .overlay(Text(String(title.prefix(1))).font(.system(size: max(10, size * 0.38), weight: .bold)).foregroundStyle(theme.notch.accent))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
    }
}

// MARK: - Backups

/// Your Spotify library as CSV files: Liked Songs, your playlists and the ones you follow.
struct MusicBackupsView: View {
    @ObservedObject private var spotify = SpotifyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    /// The backup whose changes are showing, in place of the list.
    @State private var comparing: SpotifyLibrary.Backup?
    @State private var difference: SpotifyBackupDiff?
    @State private var comparisonProblem: String?
    /// The earlier backup picked to compare with; unset is the one just before.
    @State private var baseline: SpotifyLibrary.Backup?
    /// The backup whose delete button is asking to be clicked again.
    @State private var confirmingDelete: SpotifyLibrary.Backup?

    var body: some View {
        if !spotify.isConnected {
            SpotifyConnectView(purpose: "Liked Songs and your playlists as CSV files, now or every week")
        } else {
            VStack(alignment: .leading, spacing: TerminalTabMetrics.gap) {
                MusicPageHeader("Backups") { EmptyView() }
                HStack(alignment: .top, spacing: TerminalTabMetrics.gap) {
                    Group {
                        if let comparing {
                            BackupChangesCard(title: changesTitle(comparing),
                                              earlier: older(comparing).map { ($0.id, Self.when($0.date)) },
                                              onPick: { id in baseline = older(comparing).first { $0.id == id } },
                                              difference: difference, problem: comparisonProblem) {
                                self.comparing = nil
                                baseline = nil
                            }
                        } else {
                            list
                        }
                    }
                    .frame(maxWidth: .infinity)
                    VStack(spacing: TerminalTabMetrics.gap) {
                        Button { Task { await spotify.backUp() } } label: {
                            Text(spotify.progress ?? "Back up now").lineLimit(1).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TerminalButtonStyle(prominent: true))
                        .disabled(spotify.progress != nil)
                        side
                    }
                    .frame(width: 210)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .task(id: "\(comparing?.id ?? "")|\(baseline?.id ?? "")") { await compare() }
            .onAppear { spotify.watchBackups() }
            .onDisappear { spotify.stopWatchingBackups() }
            .onChange(of: spotify.backups) { backups in
                // One deleted here or in Finder can't stay on screen.
                if let comparing, !backups.contains(comparing) { self.comparing = nil; baseline = nil }
                if let baseline, !backups.contains(baseline) { self.baseline = nil }
            }
        }
    }

    /// The backups before this one, nearest first: the list runs newest first.
    private func older(_ backup: SpotifyLibrary.Backup) -> [SpotifyLibrary.Backup] {
        spotify.backups.firstIndex(of: backup).map { Array(spotify.backups[($0 + 1)...]) } ?? []
    }

    /// What this backup is compared with: the one picked, else the one just before.
    private func previous(_ backup: SpotifyLibrary.Backup) -> SpotifyLibrary.Backup? {
        baseline.flatMap { older(backup).contains($0) ? $0 : nil } ?? older(backup).first
    }

    private func changesTitle(_ backup: SpotifyLibrary.Backup) -> String {
        guard let previous = previous(backup) else { return Self.when(backup.date) }
        return "\(Self.when(backup.date)), since \(Self.when(previous.date))"
    }

    private func compare() async {
        difference = nil
        comparisonProblem = nil
        guard let comparing else { return }
        guard let previous = previous(comparing) else {
            comparisonProblem = "This is your first backup, so there's nothing to compare it with yet."
            return
        }
        do {
            let result = try await SpotifyLibrary.changes(from: previous, to: comparing)
            guard !Task.isCancelled else { return }
            difference = result
        } catch {
            guard !Task.isCancelled else { return }
            comparisonProblem = (error as? SpotifyLibrary.SpotifyError)?.message ?? "Couldn't read these backups: \(error.localizedDescription)"
        }
    }

    /// Every backup, newest first: when, and what it holds, with its Changes, Finder and delete buttons.
    private var list: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(spotify.backups.isEmpty ? "No backups yet" : spotify.backups.count == 1 ? "1 backup" : "\(spotify.backups.count) backups")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            if spotify.backups.isEmpty {
                Text("Back up now saves Liked Songs, each playlist you own and the ones you follow as CSV files, in a dated folder.")
                    .font(.system(size: 11)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: TerminalTabMetrics.rowGap) {
                        ForEach(spotify.backups) { backup in row(backup) }
                    }
                }
            }
        }
        .padding(TerminalTabMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous))
    }

    private func row(_ backup: SpotifyLibrary.Backup) -> some View {
        HStack(spacing: 10) {
            HStack(spacing: 10) {
                    Image(systemName: "externaldrive").font(.system(size: 13)).foregroundStyle(theme.notch.accent).frame(width: 18)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(Self.when(backup.date)).font(.system(size: 12, weight: .medium))
                        Text(Self.contents(backup)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer(minLength: 4)
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Backup from \(Self.when(backup.date)), \(Self.contents(backup))")
            if !older(backup).isEmpty {
                Button("Changes") { confirmingDelete = nil; baseline = nil; comparing = backup }
                    .buttonStyle(TerminalButtonStyle())
                    .help("See what changed since the backup before it")
                    .accessibilityLabel("See what changed in this backup")
            }
            Button { spotify.show(backup) } label: {
                Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(.secondary).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Show in Finder")
            .accessibilityLabel("Show this backup in Finder")
            if confirmingDelete == backup {
                Button("Delete") { confirmingDelete = nil; spotify.trash(backup) }
                    .buttonStyle(TerminalButtonStyle())
                    .foregroundStyle(.red)
                    .help("Move this backup to the Trash")
            } else {
                Button { confirmingDelete = backup } label: {
                    Image(systemName: "trash").font(.system(size: 11)).foregroundStyle(.secondary).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete this backup")
                .accessibilityLabel("Delete this backup")
            }
        }
        .padding(.horizontal, 10)
        .frame(height: TerminalTabMetrics.rowHeight + 6)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.rowRadius, style: .continuous))
    }

    /// "3,290 songs · 30 playlists · 12 liked · 4 followed", leaving out what's empty.
    static func contents(_ backup: SpotifyLibrary.Backup) -> String {
        var parts = ["\(backup.songs.formatted()) songs"]
        if backup.playlists > 0 { parts.append(backup.playlists == 1 ? "1 playlist" : "\(backup.playlists) playlists") }
        if backup.likedSongs > 0 { parts.append("\(backup.likedSongs.formatted()) liked") }
        if backup.followed > 0 { parts.append("\(backup.followed) followed") }
        return parts.joined(separator: " · ")
    }

    private var side: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green).font(.system(size: 12))
                Text("Connected as \(spotify.account ?? "")").font(.system(size: 11, weight: .medium)).lineLimit(1)
                Spacer(minLength: 0)
            }
            Toggle("Back up every week", isOn: Binding(get: { spotify.weekly }, set: { spotify.weekly = $0 }))
                .toggleStyle(.switch).controlSize(.mini).font(.system(size: 11))
            HStack(spacing: 6) {
                Image(systemName: "folder.fill").foregroundStyle(.secondary).font(.system(size: 11))
                Text(SpotifyLibrary.folder.lastPathComponent).font(.system(size: 11)).lineLimit(1)
                Spacer(minLength: 0)
                Button("Show") { spotify.showFolder() }.buttonStyle(TerminalButtonStyle())
            }
            Text(spotify.problem ?? "A CSV per playlist: title, artists, album, date added, ISRC and link.")
                .font(.system(size: 10)).foregroundStyle(spotify.problem == nil ? .secondary : Color.orange).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            Button("Disconnect Spotify") { spotify.disconnect() }.buttonStyle(TerminalButtonStyle())
        }
        .padding(TerminalTabMetrics.cardPadding)
        .frame(width: 210, alignment: .topLeading)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous))
    }

    static func when(_ date: Date) -> String {
        let time = date.formatted(date: .omitted, time: .shortened)
        if Calendar.current.isDateInToday(date) { return "Today, \(time)" }
        if Calendar.current.isDateInYesterday(date) { return "Yesterday, \(time)" }
        return date.formatted(.dateTime.month(.abbreviated).day()) + ", " + time
    }
}

// MARK: - Connecting

/// Before Spotify is connected: a header, then one line per step with your own developer app.
struct SpotifyConnectView: View {
    let purpose: String
    @ObservedObject private var spotify = SpotifyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var clientID = SpotifyLibrary.shared.clientID
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: TerminalTabMetrics.gap) {
            TerminalTabHeader("Connect Spotify", details: [spotify.problem ?? purpose]) {
                EmptyView()
            } filters: { EmptyView() }
            VStack(spacing: TerminalTabMetrics.rowGap) {
                line(1, "Create an app in Spotify's dashboard, with Web API") {
                    Button("Open dashboard") { NSWorkspace.shared.open(SpotifyLibrary.dashboard) }.buttonStyle(TerminalButtonStyle())
                }
                line(2, "Add the redirect URI") {
                    Text(SpotifyLibrary.redirectURI).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(.secondary)
                        .lineLimit(1).textSelection(.enabled)
                    Button(copied ? "Copied" : "Copy") {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(SpotifyLibrary.redirectURI, forType: .string)
                        copied = true
                    }
                    .buttonStyle(TerminalButtonStyle())
                }
                line(3, "Paste its Client ID") {
                    TextField("Client ID", text: $clientID)
                        .textFieldStyle(.plain).font(.system(size: 11, design: .monospaced))
                        .padding(.horizontal, 10)
                        .frame(width: 230, height: TerminalTabMetrics.controlHeight)
                        .background(Color.primary.opacity(0.06), in: Capsule())
                        .onSubmit(connect)
                    Button(spotify.connecting ? "Waiting" : "Connect", action: connect)
                        .buttonStyle(TerminalButtonStyle(prominent: true))
                        .disabled(spotify.connecting || clientID.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
            Text("Your own app, so nothing goes through MacSpaces. Spotify asks its owner to have Premium.")
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func connect() {
        spotify.clientID = clientID
        spotify.connect()
    }

    private func line<Trailing: View>(_ number: Int, _ title: String, @ViewBuilder trailing: () -> Trailing) -> some View {
        HStack(spacing: 9) {
            Text("\(number)").font(.system(size: 10, weight: .bold)).foregroundStyle(theme.notch.accent)
                .frame(width: 20, height: 20).background(theme.notch.accent.opacity(0.14), in: Circle())
            Text(title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 8)
            trailing()
        }
        .padding(.horizontal, 10)
        .frame(height: TerminalTabMetrics.rowHeight + 4)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.rowRadius, style: .continuous))
    }
}
