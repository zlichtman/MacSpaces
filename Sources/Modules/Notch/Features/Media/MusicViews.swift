import SwiftUI

/// The Music page's views, picked in the dock's middle group: the player, your Spotify stats
/// and your Spotify backups.
enum MusicView: String, CaseIterable, Identifiable {
    case playing, stats, backups
    static let defaultsKey = "music.view"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .playing: return "Playing"
        case .stats: return "Stats"
        case .backups: return "Backups"
        }
    }
    var symbol: String {
        switch self {
        case .playing: return "play.fill"
        case .stats: return "chart.bar"
        case .backups: return "externaldrive"
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
            }
        }
        // Stats and Backups are side trips: leaving the Music page (another tab, or the Nook
        // closing) brings it back to the player, so it always opens on what's playing.
        .onAppear { if view != .playing { view = .playing } }
        .onDisappear { if view != .playing { view = .playing } }
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

/// Spotify's own top songs (or artists) for the last 4 weeks, 6 months and year, side by side.
struct MusicStatsView: View {
    @ObservedObject private var spotify = SpotifyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @AppStorage("music.statsArtists") private var artists = false

    var body: some View {
        if !spotify.isConnected {
            SpotifyConnectView(purpose: "Your top songs and artists over 4 weeks, 6 months and a year")
        } else {
            VStack(alignment: .leading, spacing: TerminalTabMetrics.gap) {
                MusicPageHeader("Stats") {
                    HStack(spacing: 4) {
                        Button("Songs") { artists = false }.buttonStyle(WidgetChipStyle(prominent: !artists, height: 20))
                        Button("Artists") { artists = true }.buttonStyle(WidgetChipStyle(prominent: artists, height: 20))
                    }
                }
                if let top = spotify.top {
                    HStack(alignment: .top, spacing: TerminalTabMetrics.gap) {
                        ForEach(SpotifyLibrary.Range.allCases) { range in column(range, top) }
                    }
                    // Songs and artists are separate lists: switching rebuilds the columns
                    // (rows and pictures) rather than reusing the other list's rows.
                    .id(artists)
                } else {
                    EmptyTabMessage(systemImage: "chart.bar", title: spotify.loadingTop ? "Loading your stats" : "No stats yet",
                                    detail: spotify.problem ?? "Spotify needs a little listening history first.") { EmptyView() }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            // Opening Stats or switching lists fetches anew when what's saved is stale; the load
            // carries on in the background if you leave, and lands when it's done.
            .task(id: artists) { spotify.refreshTop() }
        }
    }

    private func column(_ range: SpotifyLibrary.Range, _ top: SpotifyLibrary.Top) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(range.title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
            // All 50 Spotify returns, scrolling within the column.
            ScrollView(.vertical, showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 4) {
                    if artists {
                        ForEach(Array((top.artists[range.rawValue] ?? []).enumerated()), id: \.offset) { index, artist in
                            row(index, artist.name, nil, artist.image, round: true, link: artist.link)
                        }
                    } else {
                        ForEach(Array((top.songs[range.rawValue] ?? []).enumerated()), id: \.offset) { index, song in
                            row(index, song.title, song.artists, song.image, round: false, link: song.link)
                        }
                    }
                }
            }
        }
        .padding(TerminalTabMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous))
    }

    private func row(_ index: Int, _ title: String, _ detail: String?, _ image: URL?, round: Bool, link: URL?) -> some View {
        Button { if let link { SpotifyLibrary.openInApp(link) } } label: {
            HStack(spacing: 7) {
                Text("\(index + 1)").font(.system(size: 10, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(.secondary).frame(width: 14, alignment: .trailing)
                SpotifyThumbnail(url: image, title: title, round: round)
                VStack(alignment: .leading, spacing: 0) {
                    Text(title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                    if let detail { Text(detail).font(.system(size: 9.5)).foregroundStyle(.secondary).lineLimit(1) }
                }
                Spacer(minLength: 0)
            }
            .frame(height: 26)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(link == nil ? title : "Show in Spotify")
    }
}

/// A song's cover or an artist's picture, or its first letter until it loads.
struct SpotifyThumbnail: View {
    let url: URL?
    let title: String
    let round: Bool
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: round ? 13 : 4, style: .continuous)
        Group {
            // A file on this Mac (a demo's cover) draws at once; Spotify's load in the background.
            if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    shape.fill(theme.notch.accent.opacity(0.18))
                        .overlay(Text(String(title.prefix(1))).font(.system(size: 10, weight: .bold)).foregroundStyle(theme.notch.accent))
                }
            }
        }
        .frame(width: 26, height: 26)
        .clipShape(shape)
    }
}

// MARK: - Backups

/// Your Spotify library as CSV files: Liked Songs, your playlists and the ones you follow.
struct MusicBackupsView: View {
    @ObservedObject private var spotify = SpotifyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        if !spotify.isConnected {
            SpotifyConnectView(purpose: "Liked Songs and your playlists as CSV files, now or every week")
        } else {
            VStack(alignment: .leading, spacing: TerminalTabMetrics.gap) {
                MusicPageHeader("Backups") { EmptyView() }
                HStack(alignment: .top, spacing: TerminalTabMetrics.gap) {
                    list.frame(maxWidth: .infinity)
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
        }
    }

    /// Every backup, newest first: when, and what it holds; clicking one shows its folder.
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
        Button { spotify.show(backup) } label: {
            HStack(spacing: 10) {
                Image(systemName: "externaldrive").font(.system(size: 13)).foregroundStyle(theme.notch.accent).frame(width: 18)
                VStack(alignment: .leading, spacing: 1) {
                    Text(Self.when(backup.date)).font(.system(size: 12, weight: .medium))
                    Text(Self.contents(backup)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 4)
                Image(systemName: "folder").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .frame(height: TerminalTabMetrics.rowHeight + 6)
            .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Show in Finder")
        .accessibilityLabel("Backup from \(Self.when(backup.date)), \(Self.contents(backup))")
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
