import SwiftUI
import AppKit

/// The Music page's Shelf look: your Spotify songs as a row of covers to scroll through and play,
/// with the one in the middle described beside them. It opens on All: every playlist in a row,
/// each starting at a divider you feel as you cross it. Only the covers near the middle are drawn.
struct SpotifyShelfView: View {
    @ObservedObject var nowPlaying: NowPlayingController
    /// The playing song's lyrics, a line at a time under the covers.
    var lyrics: TeleprompterService?
    @ObservedObject private var spotify = SpotifyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var options = WidgetOptions.shared
    /// Where the shelf is, in rows: between two whole numbers while it's moving.
    @State private var position: CGFloat = 0
    @State private var settle: DispatchWorkItem?
    /// You've scrolled, so songs arriving no longer take you to the playing one.
    @State private var scrolledByHand = false
    /// The row in the middle, so it stays there when rows arrive around it.
    @State private var anchor: (id: String, index: Int)?
    @State private var crossedInto: String?

    /// The scrolling that moves the shelf by one row.
    private static let pointsPerRow: CGFloat = 56
    private static let lyricHeight: CGFloat = 30
    private static let lyricGap: CGFloat = 8

    private var rows: [SpotifyLibrary.ShelfRow] { spotify.shelfRows }
    private var focused: Int { Int(SongShelfPose.clamped(position, count: rows.count).rounded()) }

    var body: some View {
        if !spotify.isConnected {
            SpotifyConnectView(purpose: "Scroll through your playlists and Liked Songs, and play any song")
        } else {
            // The same columns as the Standard look, so the controls stay put between looks:
            // the words above the transport, the covers above the timeline, with the playing
            // song's lyric between them. The controls are always there.
            GeometryReader { proxy in
                let gap: CGFloat = 24
                let column = max(120, min(180, (proxy.size.width - 40 - gap) * 0.4, proxy.size.height - 56))
                VStack(spacing: 16) {
                    VStack(spacing: Self.lyricGap) {
                        HStack(alignment: .top, spacing: gap) {
                            caption.frame(width: column)
                            shelf.frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                        // Level with each other above the controls: what's playing, while the
                        // shelf shows something else, and the playing song's lyric.
                        HStack(alignment: .center, spacing: gap) {
                            Group {
                                if nowPlaying.info.hasTrack, !focusedIsPlaying { playingChip } else { Color.clear }
                            }
                            .frame(width: column, height: Self.lyricHeight)
                            Group {
                                if let lyrics, nowPlaying.info.hasTrack { ShelfLyricLine(service: lyrics) } else { Color.clear }
                            }
                            .frame(maxWidth: .infinity).frame(height: Self.lyricHeight)
                        }
                    }
                    .frame(maxHeight: .infinity)
                    HStack(alignment: .center, spacing: gap) {
                        MusicTransportControls(nowPlaying: nowPlaying, width: column).frame(width: column)
                        PlaybackTimeline(nowPlaying: nowPlaying, onScrub: { lyrics?.scrub(to: $0) }).frame(maxWidth: .infinity)
                    }
                    .frame(height: 40)
                }
                .padding(.horizontal, 20)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .onAppear {
                spotify.loadShelf(spotify.shelfSource)
                moveToPlaying(animated: false)
                arrived(at: focused)
            }
            // A new song brings the shelf to it, unless you've scrolled off to look around.
            .onChange(of: nowPlaying.info.title) { _ in if !scrolledByHand { moveToPlaying(animated: true) } }
            .onChange(of: spotify.shelfSource) { _ in
                position = 0
                scrolledByHand = false
                anchor = nil
                arrived(at: 0)
            }
            .onChange(of: rows.count) { _ in rowsChanged() }
        }
    }

    private var shelf: some View {
        GeometryReader { proxy in
            let side = max(90, min(proxy.size.height, proxy.size.width * 0.56))
            // The song in the middle stands at the left of the column, the next ones behind it to
            // the right, all on the bottom line, level with the words beside them.
            ZStack(alignment: .bottomLeading) {
                if rows.isEmpty {
                    Text(spotify.shelfLoading ? "Loading your playlists" : spotify.problem ?? "No songs here yet")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                } else {
                    ForEach(visible, id: \.self) { index in
                        place(index, side: side)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .bottomLeading)
            .clipped()
            .contentShape(Rectangle())
        }
        .background {
            ScrollWheelCatcher(onScroll: scrolled, onEnded: {}, onlyInside: true)
        }
        .mask {
            LinearGradient(stops: [.init(color: .black, location: 0), .init(color: .black, location: 0.9),
                                   .init(color: .clear, location: 1)],
                           startPoint: .leading, endPoint: .trailing)
        }
    }

    private var visible: [Int] {
        guard !rows.isEmpty else { return [] }
        let middle = focused
        return Array(max(0, middle - SongShelfPose.reach)...min(rows.count - 1, middle + SongShelfPose.reach))
    }

    @ViewBuilder private func place(_ index: Int, side: CGFloat) -> some View {
        let distance = CGFloat(index) - position
        let pose = SongShelfPose(distance: distance, side: side)
        Group {
            switch rows[index] {
            case .divider(let source): divider(source, index: index, side: side)
            case .song(let song, let source, _): cover(song, in: source, index: index, side: side)
            }
        }
        .scaleEffect(pose.scale, anchor: .bottom)
        .offset(x: pose.x)
        // Songs scrolled past fade as they slide off to the left.
        .opacity(pose.opacity * Double(max(0, min(1, 1 + distance))))
        .zIndex(-Double(abs(distance)))
        .accessibilityValue("\(index + 1) of \(rows.count)")
        .accessibilityAddTraits(index == focused ? .isSelected : [])
    }

    private func cover(_ song: SpotifyLibrary.Song, in source: SpotifyLibrary.ShelfSource, index: Int, side: CGFloat) -> some View {
        Button {
            move(to: index, animated: true)
            play(song, in: source)
        } label: {
            art(url: song.image, title: song.title, side: side, playing: isPlaying(song))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help("Play \(song.title)")
        .accessibilityLabel("Play \(song.title) by \(song.artists)")
    }

    /// Where a playlist starts: its cover, darkened at the foot under its name.
    private func divider(_ source: SpotifyLibrary.ShelfSource, index: Int, side: CGFloat) -> some View {
        Button {
            move(to: index, animated: true)
            if let first = firstSong(after: index) { play(first, in: source) }
        } label: {
            art(url: source.image, title: source.name, side: side, playing: false)
                .overlay {
                    LinearGradient(stops: [.init(color: .clear, location: 0.45), .init(color: .black.opacity(0.8), location: 1)],
                                   startPoint: .top, endPoint: .bottom)
                }
                .overlay(alignment: .bottomLeading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(source.name).font(.system(size: 15, weight: .bold)).lineLimit(2)
                        if let total = source.total {
                            Text(Self.songCount(total)).font(.system(size: 11)).opacity(0.8).monospacedDigit()
                        }
                    }
                    .foregroundStyle(.white)
                    .padding(12)
                }
                .clipShape(RoundedRectangle(cornerRadius: max(4, side * 0.1), style: .continuous))
                .shadow(color: .black.opacity(0.45), radius: 8, y: 3)
        }
        .buttonStyle(.plain)
        .help("Play \(source.name)")
        .accessibilityLabel("Play \(source.name), playlist\(source.total.map { ", \(Self.songCount($0))" } ?? "")")
    }

    private static func songCount(_ total: Int) -> String { "\(total.formatted()) song\(total == 1 ? "" : "s")" }

    private func firstSong(after index: Int) -> SpotifyLibrary.Song? {
        guard rows.indices.contains(index + 1), case .song(let song, _, _) = rows[index + 1] else { return nil }
        return song
    }

    /// A cover: the picture, or ASCII art of it when Settings → Album art says so.
    @ViewBuilder private func art(url: URL?, title: String, side: CGFloat, playing: Bool) -> some View {
        if options.asciiCover {
            ShelfAsciiCover(url: url, title: title, side: side, style: options.asciiStyle, scene: options.asciiScene,
                            detail: options.asciiDetail, colouring: options.asciiColours, around: options.asciiAround,
                            follows: playing, moving: playing && nowPlaying.info.isPlaying,
                            duration: playing ? nowPlaying.info.duration : 0, nowPlaying: nowPlaying)
                .equatable()
        } else {
            SpotifyThumbnail(url: url, title: title, round: false, size: side)
        }
    }

    /// The source at the top; what's in the middle at the foot, level with the bottom of the covers.
    private var caption: some View {
        VStack(alignment: .leading, spacing: 4) {
            sourceMenu
            Spacer(minLength: 0)
            if rows.indices.contains(focused) {
                switch rows[focused] {
                case .divider(let source): dividerCaption(source)
                case .song(let song, let source, let number): songCaption(song, in: source, number: number)
                }
            }
            if spotify.shelfWaiting {
                Text("Spotify asked for a pause. More songs soon.").font(.system(size: 10)).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var focusedIsPlaying: Bool {
        guard rows.indices.contains(focused), case .song(let song, _, _) = rows[focused] else { return false }
        return isPlaying(song)
    }

    /// What's playing, with its cover, while the shelf shows something else: click to go back to it.
    private var playingChip: some View {
        Button {
            scrolledByHand = false
            moveToPlaying(animated: true)
        } label: {
            HStack(spacing: 8) {
                Group {
                    if let artwork = nowPlaying.info.artwork {
                        Image(nsImage: artwork).resizable().scaledToFill()
                    } else {
                        theme.nookForeground.opacity(0.12)
                            .overlay(Image(systemName: "music.note").font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary))
                    }
                }
                .frame(width: 30, height: 30)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                VStack(alignment: .leading, spacing: 1) {
                    Text(nowPlaying.info.title).font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    Text(nowPlaying.info.artist).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Back to \(nowPlaying.info.title)")
        .accessibilityLabel("Playing \(nowPlaying.info.title) by \(nowPlaying.info.artist). Show it on the shelf")
    }

    @ViewBuilder private func songCaption(_ song: SpotifyLibrary.Song, in source: SpotifyLibrary.ShelfSource, number: Int) -> some View {
        Text(song.title).font(.system(size: 18, weight: .bold)).lineLimit(2)
        Text(song.artists).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
        Text(song.album).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1)
        if spotify.shelfSource == .all {
            Text(source.name).font(.system(size: 10, weight: .medium)).foregroundStyle(theme.notch.accent).lineLimit(1)
                .padding(.top, 4)
        }
        Text(numbering(number, in: source) + (isPlaying(song) ? " · Playing" : ""))
            .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
    }

    @ViewBuilder private func dividerCaption(_ source: SpotifyLibrary.ShelfSource) -> some View {
        Text(source.name).font(.system(size: 18, weight: .bold)).lineLimit(2)
        if let total = source.total {
            Text(Self.songCount(total)).font(.system(size: 12)).foregroundStyle(.secondary).monospacedDigit()
        }
    }

    private func numbering(_ number: Int, in source: SpotifyLibrary.ShelfSource) -> String {
        if let total = source.total { return "\(number.formatted()) of \(total.formatted())" }
        return "\(number.formatted()) of \(rows.count.formatted())\(spotify.shelfLoading ? " so far" : "")"
    }

    /// What the shelf shows, as a pill you switch often: All, Liked Songs or a playlist, from a
    /// list that scrolls when there are many.
    private var sourceMenu: some View {
        let sources = spotify.shelfSources
        return NookMenu {
            ScrollView(.vertical, showsIndicators: sources.count > 10) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(sources) { source in
                        NookMenuRow(source.name, systemImage: Self.symbol(for: source), selected: source == spotify.shelfSource) {
                            spotify.loadShelf(source)
                        }
                    }
                }
            }
            .frame(width: 220, height: min(CGFloat(sources.count) * 28 + 4, 300))
        } label: {
            HStack(spacing: 6) {
                Image(systemName: Self.symbol(for: spotify.shelfSource)).font(.system(size: 10, weight: .semibold))
                Text(spotify.shelfSource.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).opacity(0.7)
            }
            .padding(.horizontal, 10).frame(height: 26)
            .background(theme.nookForeground.opacity(0.1), in: Capsule())
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help("Choose what the shelf shows")
        .accessibilityLabel("Songs from \(spotify.shelfSource.name)")
    }

    private static func symbol(for source: SpotifyLibrary.ShelfSource) -> String {
        source == .all ? "square.stack.fill" : source == .liked ? "heart.fill" : "music.note.list"
    }

    /// Plays it, and the shelf follows what plays from here on.
    private func play(_ song: SpotifyLibrary.Song, in source: SpotifyLibrary.ShelfSource) {
        scrolledByHand = false
        spotify.play(song, in: source)
    }

    private func isPlaying(_ song: SpotifyLibrary.Song) -> Bool {
        let info = nowPlaying.info
        return info.title == song.title && !info.artist.isEmpty && song.artists.localizedCaseInsensitiveContains(info.artist)
    }

    /// To the playing song, the nearest copy of it: a song can be in several playlists.
    private func moveToPlaying(animated: Bool) {
        guard settle == nil else { return }
        let middle = focused
        let copies = rows.indices.filter { index in
            if case .song(let song, _, _) = rows[index] { return isPlaying(song) }
            return false
        }
        guard let nearest = copies.min(by: { abs($0 - middle) < abs($1 - middle) }) else { return }
        move(to: nearest, animated: animated)
    }

    private func move(to index: Int, animated: Bool) {
        arrived(at: index)
        guard animated, !theme.reduceMotion else { position = CGFloat(index); return }
        withAnimation(Design.spring()) { position = CGFloat(index) }
    }

    /// Stopped on a row: remember it, and let the songs around it be read.
    private func arrived(at index: Int) {
        anchor = rows.indices.contains(index) ? (rows[index].id, index) : nil
        crossedInto = rows.indices.contains(index) ? rows[index].source.id : nil
        spotify.shelfFocused(index)
    }

    /// Rows arrived or went: the one in the middle stays there. A playlist's songs come all at
    /// once, so it then goes to the playing song; All fills in playlist by playlist, so it stays
    /// put rather than jumping when the playing song turns up (the line under the menu goes there).
    private func rowsChanged() {
        if let anchor, let index = rows.firstIndex(where: { $0.id == anchor.id }) {
            position += CGFloat(index - anchor.index)
            self.anchor = (anchor.id, index)
        } else {
            position = SongShelfPose.clamped(position, count: rows.count)
        }
        if !scrolledByHand, spotify.shelfSource != .all { moveToPlaying(animated: false) }
        arrived(at: focused)
    }

    /// Follows the Mac's scroll direction, as the song swipe does. A mouse wheel moves in lines,
    /// so each counts for more. Once scrolling stops the shelf settles on the nearest row.
    private func scrolled(_ event: NSEvent) {
        let sideways = abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY)
        var delta = sideways ? event.scrollingDeltaX : event.scrollingDeltaY
        if !event.hasPreciseScrollingDeltas { delta *= 10 }
        position = SongShelfPose.clamped(position - delta / Self.pointsPerRow, count: rows.count)
        scrolledByHand = true
        feelNewPlaylist()
        settle?.cancel()
        let work = DispatchWorkItem {
            settle = nil
            move(to: focused, animated: true)
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// A tap on the trackpad as you scroll from one playlist into another.
    private func feelNewPlaylist() {
        guard rows.indices.contains(focused) else { return }
        let source = rows[focused].source.id
        if let crossedInto, crossedInto != source {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        crossedInto = source
    }
}

/// The playing song's lyric, one line under the covers, turning over with the song.
private struct ShelfLyricLine: View {
    @ObservedObject var service: TeleprompterService
    @ObservedObject private var theme = ThemeStore.shared
    @State private var presentationID = UUID()

    var body: some View {
        Text(service.currentText)
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(service.lineID)
            .transition(.opacity)
            .animation(theme.reduceMotion ? nil : Design.timed(.easeOut(duration: 0.18)), value: service.lineID)
            // Mounted, it keeps the lookup running, as the Standard look's lyrics do.
            .onAppear { service.setPresentationVisible(true, id: presentationID) }
            .onDisappear { service.setPresentationVisible(false, id: presentationID) }
    }
}

/// One Shelf cover as ASCII art. Equatable, so scrolling the shelf moves it without drawing it
/// again: it's drawn once unless it's the playing song, which follows your Scene and Around and
/// moves with the music. The others show their cover standing still, so each stays recognisable.
private struct ShelfAsciiCover: View, Equatable {
    let url: URL?
    let title: String
    let side: CGFloat
    let style: AsciiStyle
    let scene: AsciiScene
    let detail: AsciiDetail
    let colouring: AsciiColouring
    let around: AsciiAround
    let follows: Bool
    let moving: Bool
    let duration: Double
    let nowPlaying: NowPlayingController
    @ObservedObject private var theme = ThemeStore.shared
    /// Set when a cover arrives, to draw it. What's drawn is always looked up by this cover's
    /// address, so a reused view can never show the last song's art.
    @State private var arrived: URL?

    nonisolated static func == (a: Self, b: Self) -> Bool {
        a.url == b.url && a.side == b.side && a.style == b.style && a.scene == b.scene && a.detail == b.detail
            && a.colouring == b.colouring && a.around == b.around && a.follows == b.follows && a.moving == b.moving
            && a.duration == b.duration
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: max(4, side * 0.1), style: .continuous)
        let _ = arrived
        Group {
            if let url, let ready = ShelfAsciiCovers.shared.known(url) {
                AsciiCover(artwork: nil, size: side, style: style, scene: follows ? scene : .cover, detail: detail,
                           position: { [nowPlaying, follows] in
                               guard follows else { return 0 }
                               let info = nowPlaying.info
                               return info.elapsed + (info.isPlaying ? Date().timeIntervalSince(nowPlaying.elapsedReadAt) : 0)
                           },
                           playing: moving, colouring: colouring, song: title, duration: duration,
                           around: follows ? around : .off, ready: ready)
            } else {
                // The picture until its ASCII art is ready, and for good if there's no cover.
                SpotifyThumbnail(url: url, title: title, round: false, size: side)
            }
        }
        .frame(width: side, height: side)
        // Solid: covers overlap, and one mustn't show through another.
        .background(Color(nsColor: NSColor(theme.notch.surface).withAlphaComponent(1)))
        .clipShape(shape)
        .task(id: url) {
            guard let url, await ShelfAsciiCovers.shared.cover(for: url) != nil else { return }
            arrived = url
        }
    }
}

/// A backup's changes from the one before it, by playlist. Clicking a song plays it in Spotify.
struct BackupChangesCard: View {
    let title: String
    /// The earlier backups it can be compared with, for the menu in its title.
    var earlier: [(id: String, name: String)] = []
    var onPick: (String) -> Void = { _ in }
    let difference: SpotifyBackupDiff?
    let problem: String?
    let onBack: () -> Void
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Button(action: onBack) { Image(systemName: "chevron.left").font(.system(size: 10, weight: .semibold)) }
                    .buttonStyle(TerminalButtonStyle())
                    .accessibilityLabel("All backups")
                if earlier.count > 1 {
                    Menu {
                        ForEach(earlier, id: \.id) { option in
                            Button("Since \(option.name)") { onPick(option.id) }
                        }
                    } label: {
                        Text(title).font(.system(size: 10, weight: .semibold)).lineLimit(1)
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .help("Compare with another backup")
                } else {
                    Text(title).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
                if let difference, !difference.isEmpty {
                    Text("+\(difference.added.count.formatted()) −\(difference.removed.count.formatted())")
                        .font(.system(size: 10, weight: .semibold)).monospacedDigit()
                        .accessibilityLabel("\(difference.added.count) added, \(difference.removed.count) removed")
                }
            }
            content
        }
        .padding(TerminalTabMetrics.cardPadding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.cardRadius, style: .continuous))
    }

    @ViewBuilder private var content: some View {
        if let problem {
            Text(problem).font(.system(size: 11)).foregroundStyle(.orange).fixedSize(horizontal: false, vertical: true)
        } else if let difference {
            if difference.isEmpty {
                Text("Nothing changed: the same songs in the same playlists.").font(.system(size: 11)).foregroundStyle(.secondary)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(difference.groups) { group in
                            VStack(alignment: .leading, spacing: 2) {
                            Text(group.playlist).font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.notch.accent)
                                .padding(.top, 6)
                            ForEach(Array(group.added.enumerated()), id: \.offset) { row($0.element, added: true) }
                            ForEach(Array(group.removed.enumerated()), id: \.offset) { row($0.element, added: false) }
                            }
                        }
                    }
                }
            }
        } else {
            Text("Comparing").font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }

    private func row(_ song: SpotifyBackupSong, added: Bool) -> some View {
        Button {
            guard let link = URL(string: song.link), !song.link.isEmpty else { return }
            MusicView.keepOnReturn = true
            SpotifyLibrary.openInApp(link)
        } label: {
            HStack(spacing: 6) {
                Image(systemName: added ? "plus" : "minus").font(.system(size: 8, weight: .bold))
                    .foregroundStyle(added ? Color.green : Color.red).frame(width: 12)
                Text(song.title).font(.system(size: 11, weight: .medium)).lineLimit(1)
                Text(song.artists).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                Spacer(minLength: 0)
            }
            .frame(height: 20)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(added ? "Added" : "Removed"): \(song.title) by \(song.artists)")
    }
}
