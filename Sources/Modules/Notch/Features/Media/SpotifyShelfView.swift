import SwiftUI
import AppKit

/// The Music page's Shelf look: one source's songs (Liked Songs or the playlist you pick, or the
/// first playlist with songs when that has none) as a row of album covers you flip through, the
/// front one whole in the middle and the rest smaller and fainter to each side. The playing song's
/// record slides half out of its cover to the right and turns while it plays; flipping away slides
/// it back in. Under the row: the front song, the timeline and the transport; along the foot the
/// source and the lyric. Drawn flat in the theme's colours, always the real covers. Only the covers
/// near the front are drawn, and while a song plays only the record's label moves.
struct SpotifyShelfView: View {
    @ObservedObject var nowPlaying: NowPlayingController
    /// The playing song's lyrics, a line at a time beside the source.
    var lyrics: TeleprompterService?
    #if DEBUG
    /// Check renders: the row at this position and the record this far out of its sleeve
    /// (0 in, 1 out), held there.
    var previewPose: (position: CGFloat, out: CGFloat)?
    /// The hero video: how far the record is out of its sleeve, from the video's clock (read as
    /// the player's clock redraws the page each frame).
    @MainActor static var previewRecordOut: (@MainActor () -> CGFloat)?
    #endif
    @ObservedObject private var spotify = SpotifyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var options = WidgetOptions.shared
    /// Where the row is, in covers: between two whole numbers while it's moving.
    @State private var position: CGFloat = 0
    @State private var settle: DispatchWorkItem?
    /// You've flipped through, so songs arriving no longer take you to the playing one.
    @State private var scrolledByHand = false
    /// The sleeve at the front, so it stays there when songs arrive around it.
    @State private var anchor: (id: String, index: Int)?
    /// The record out of its cover: the playing song's, or the one before while it goes back.
    @State private var record: ShelfRecord?
    /// How far the record is out of its sleeve: 0 in, 1 out.
    @State private var recordOut: CGFloat = 1
    /// Counts record changes, so a slow one never lands after a newer one.
    @State private var swap = 0
    /// The cover under the pointer, a little larger.
    @State private var hovered: Int?

    /// The scrolling that moves the row by one cover.
    private static let pointsPerRow: CGFloat = 56
    /// The three columns under the row.
    private static let panelHeight: CGFloat = 72
    private static let gap: CGFloat = 10

    private var rows: [SpotifyLibrary.ShelfRow] { spotify.shelfRows }
    private var shownPosition: CGFloat {
        #if DEBUG
        if let previewPose { return previewPose.position }
        #endif
        return position
    }
    private var shownOut: CGFloat {
        #if DEBUG
        if let previewPose { return previewPose.out }
        if let out = Self.previewRecordOut { return out() }
        #endif
        return recordOut
    }
    private var focused: Int { Int(SongShelfPose.clamped(shownPosition, count: rows.count).rounded()) }
    private var playingKey: String {
        nowPlaying.info.hasTrack ? "\(nowPlaying.info.title)|\(nowPlaying.info.artist)" : ""
    }
    /// Album art as ASCII with the Vinyl scene: the record turns as the Vinyl look's.
    private var asciiRecord: Bool { options.asciiCover && options.asciiScene == .vinyl }
    /// The playing song's cover from Spotify: the record's label, so it's always this song's.
    private var playingImage: URL? { rows.first(where: { isPlaying($0.song) })?.song.image }

    var body: some View {
        if !spotify.isConnected {
            SpotifyConnectView(purpose: "Flip through your playlists and Liked Songs, and play any song")
        } else {
            // The row of covers, and under it three columns sharing one top line: the front cover's
            // song and its number, the timeline over the transport, and what's playing (its lyric,
            // or its song while the front cover is another) over the source.
            GeometryReader { proxy in
                let rowHeight = max(110, proxy.size.height - 4 - Self.panelHeight - Self.gap)
                VStack(spacing: Self.gap) {
                    deck.frame(height: rowHeight)
                    HStack(alignment: .top, spacing: 16) {
                        browsed.frame(width: 150, alignment: .leading)
                        VStack(spacing: 4) {
                            // Holds its place with nothing playing.
                            ZStack { Color.clear; PlaybackTimeline(nowPlaying: nowPlaying, onScrub: { lyrics?.scrub(to: $0) }) }
                                .frame(height: 26)
                            MusicTransportControls(nowPlaying: nowPlaying, width: 180)
                        }
                        .frame(maxWidth: .infinity)
                        playing.frame(width: 170, alignment: .leading)
                    }
                    .frame(height: Self.panelHeight, alignment: .top)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 4)
                .frame(width: proxy.size.width, height: proxy.size.height)
            }
            .background { ShelfKeys(handle: key) }
            .onAppear {
                spotify.loadShelf(spotify.shelfChoice)
                moveToPlaying(animated: false)
                arrived(at: focused)
                record = playingKey.isEmpty ? nil : ShelfRecord(key: playingKey, artwork: nowPlaying.info.artwork, image: playingImage)
                recordOut = record == nil ? 0 : 1
            }
            // A new song brings the row to it, unless you've flipped off to look around, and
            // swaps the record.
            .onChange(of: playingKey) { key in
                if !scrolledByHand { moveToPlaying(animated: true) }
                changeRecord(to: key)
            }
            .onChange(of: nowPlaying.info.artwork) { artwork in
                if record?.key == playingKey { record?.artwork = artwork }
            }
            .onChange(of: playingImage) { image in
                if record?.key == playingKey { record?.image = image }
            }
            .onChange(of: spotify.shelfSource) { _ in
                position = 0
                scrolledByHand = false
                anchor = nil
                arrived(at: 0)
            }
            .onChange(of: rows.count) { _ in rowsChanged() }
        }
    }

    // MARK: - The row

    private var deck: some View {
        GeometryReader { proxy in
            let size = proxy.size
            // The front cover fills the height, or less in a narrow page so its neighbours show.
            let side = max(60, min(size.height, size.width * 0.32))
            let owner = recordIndex
            let out = recordOut(for: owner)
            // The front cover and its record, together, sit in the middle.
            let middle = size.width / 2 - (owner == focused ? out * side * SongShelfPose.peek / 2 : 0)
            ZStack(alignment: .topLeading) {
                if rows.isEmpty {
                    Text(spotify.shelfLoading ? "Loading your songs" : spotify.problem ?? "No songs here yet")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: size.width, height: size.height)
                } else {
                    ForEach(visible, id: \.self) { index in
                        cover(index, side: side, middle: middle, height: size.height, out: out, owner: owner)
                    }
                    if let record, let owner {
                        let pose = SongShelfPose(distance: CGFloat(owner) - shownPosition, record: owner == focused ? out : 0)
                        let sleeve = side * pose.scale
                        let disc = sleeve * 0.92
                        let sleeveX = middle + pose.x * side
                        ShelfRecordView(record: record, diameter: disc, ascii: asciiRecord, turning: record.key == playingKey,
                                        nowPlaying: nowPlaying, onToggle: { nowPlaying.togglePlayPause() })
                            .position(x: sleeveX + (sleeve / 2 + SongShelfPose.peek * side - disc / 2) * out,
                                      y: size.height - sleeve / 2)
                            // Gone once it's back in its sleeve: side covers are faint, and it would show through.
                            .opacity(pose.opacity * Double(min(1, out * 4)))
                            .zIndex(-abs(Double(CGFloat(owner) - shownPosition)) - 0.5)
                    }
                }
            }
            .frame(width: size.width, height: size.height, alignment: .topLeading)
            // Covers fade out at the row's ends rather than being cut.
            .mask(LinearGradient(stops: [.init(color: .clear, location: 0), .init(color: .black, location: 0.06),
                                         .init(color: .black, location: 0.94), .init(color: .clear, location: 1)],
                                 startPoint: .leading, endPoint: .trailing))
        }
        .background {
            ScrollWheelCatcher(onScroll: scrolled, onEnded: {}, onlyInside: true)
        }
    }

    private var visible: [Int] {
        guard !rows.isEmpty else { return [] }
        let middle = focused
        return Array(max(0, middle - SongShelfPose.reach)...min(rows.count - 1, middle + SongShelfPose.reach))
    }

    /// The row holding the record: the nearest copy of its song to the front (a song can be in a
    /// playlist twice).
    private var recordIndex: Int? {
        guard let record else { return nil }
        let copies = rows.indices.filter { Self.matches(rows[$0].song, key: record.key) }
        return copies.min(by: { abs(CGFloat($0) - shownPosition) < abs(CGFloat($1) - shownPosition) })
    }

    /// How far the record is out: all the way at the front, sliding back in as you flip away.
    private func recordOut(for owner: Int?) -> CGFloat {
        guard let owner else { return 0 }
        return shownOut * max(0, 1 - abs(CGFloat(owner) - shownPosition))
    }

    @ViewBuilder private func cover(_ index: Int, side: CGFloat, middle: CGFloat, height: CGFloat, out: CGFloat, owner: Int?) -> some View {
        let distance = CGFloat(index) - shownPosition
        let pose = SongShelfPose(distance: distance, record: owner == focused ? out : 0)
        let size = side * pose.scale * (hovered == index && abs(distance) > 0.5 ? 1.04 : 1)
        let row = rows[index]
        Button {
            move(to: index, animated: true)
            play(row.song, in: row.source)
        } label: {
            ShelfSleeve(song: row.song, side: side * pose.scale)
                .equatable()
        }
        .buttonStyle(.plain)
        .scaleEffect(size / (side * pose.scale), anchor: .bottom)
        .position(x: middle + pose.x * side, y: height - side * pose.scale / 2)
        .opacity(pose.opacity)
        .zIndex(-abs(Double(distance)))
        .onHover { inside in
            withAnimation(theme.reduceMotion ? nil : .spring(response: 0.28, dampingFraction: 0.8)) {
                if inside { hovered = index } else if hovered == index { hovered = nil }
            }
        }
        .help("Play \(row.song.title)")
        .accessibilityLabel("Play \(row.song.title) by \(row.song.artists)")
        .accessibilityValue("\(index + 1) of \(rows.count)")
        .accessibilityAddTraits(index == focused ? .isSelected : [])
    }

    /// The record goes back into its sleeve and the new song's comes out of its own.
    private func changeRecord(to key: String) {
        swap &+= 1
        let ticket = swap
        let next = key.isEmpty ? nil : ShelfRecord(key: key, artwork: nowPlaying.info.artwork, image: playingImage)
        if theme.reduceMotion {
            record = next
            recordOut = next == nil ? 0 : 1
            return
        }
        func slideOut() {
            record = next
            guard next != nil else { return }
            withAnimation(.spring(response: 0.62, dampingFraction: 0.84)) { recordOut = 1 }
        }
        guard record != nil, recordOut > 0 else {
            recordOut = 0
            slideOut()
            return
        }
        withAnimation(.easeIn(duration: 0.26)) { recordOut = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            guard swap == ticket else { return }
            slideOut()
        }
    }

    // MARK: - Under the row

    /// Left: the front cover's song, with its place in the source under it.
    private var browsed: some View {
        VStack(alignment: .leading, spacing: 2) {
            if rows.indices.contains(focused) { songCaption(rows[focused].song, in: rows[focused].source, number: rows[focused].number) }
        }
    }

    /// Right: what's playing over the source. While the front cover is the playing song (named on
    /// the left) that's its lyric; flipped to another, it's the playing song, and a click goes back.
    private var playing: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if nowPlaying.info.hasTrack, !focusedIsPlaying {
                    playingChip
                } else if let lyrics, nowPlaying.info.hasTrack {
                    ShelfLyricLine(service: lyrics)
                } else {
                    Color.clear
                }
            }
            .frame(height: 32)
            sourceMenu
        }
    }

    private var focusedIsPlaying: Bool {
        guard rows.indices.contains(focused) else { return false }
        return isPlaying(rows[focused].song)
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
        Text(song.title).font(.system(size: 15, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
        Text(song.artists).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.8)
        Text(numbering(number, in: source) + (isPlaying(song) ? " · Playing" : ""))
            .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).monospacedDigit()
    }

    private func numbering(_ number: Int, in source: SpotifyLibrary.ShelfSource) -> String {
        if let total = source.total { return "\(number.formatted()) of \(total.formatted())" }
        return "\(number.formatted()) of \(rows.count.formatted())\(spotify.shelfLoading ? " so far" : "")"
    }

    /// What the shelf shows, as a pill at the bottom right you switch often: Liked Songs or a playlist, from a list
    /// that scrolls when there are many. The pill names what's showing, a fallback included.
    private var sourceMenu: some View {
        let sources = spotify.shelfSources
        // At the foot, so it opens upwards over the shelf.
        return NookMenu(arrowEdge: .top) {
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
        .fixedSize(horizontal: false, vertical: true)
        .help("Choose what the shelf shows")
        .accessibilityLabel("Songs from \(spotify.shelfSource.name)")
    }

    private static func symbol(for source: SpotifyLibrary.ShelfSource) -> String {
        source == .liked ? "heart.fill" : "music.note.list"
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

    /// A record's song, by the "title|artist" key it was made with.
    private static func matches(_ song: SpotifyLibrary.Song, key: String) -> Bool {
        let parts = key.split(separator: "|", maxSplits: 1).map(String.init)
        guard parts.count == 2, !parts[1].isEmpty else { return false }
        return song.title == parts[0] && song.artists.localizedCaseInsensitiveContains(parts[1])
    }

    /// To the playing song, the nearest copy of it: a song can be in several playlists.
    private func moveToPlaying(animated: Bool) {
        guard settle == nil else { return }
        let middle = focused
        let copies = rows.indices.filter { isPlaying(rows[$0].song) }
        guard let nearest = copies.min(by: { abs($0 - middle) < abs($1 - middle) }) else { return }
        move(to: nearest, animated: animated)
    }

    private func move(to index: Int, animated: Bool) {
        arrived(at: index)
        guard animated, !theme.reduceMotion else { position = CGFloat(index); return }
        withAnimation(Design.spring()) { position = CGFloat(index) }
    }

    /// Stopped on a row: remember it, so it stays in the middle as songs arrive.
    private func arrived(at index: Int) {
        anchor = rows.indices.contains(index) ? (rows[index].id, index) : nil
    }

    /// Rows arrived or went: the one in front stays there, then the shelf goes to the
    /// playing song unless you've scrolled off to look around.
    private func rowsChanged() {
        if let anchor, let index = rows.firstIndex(where: { $0.id == anchor.id }) {
            position += CGFloat(index - anchor.index)
            self.anchor = (anchor.id, index)
        } else {
            position = SongShelfPose.clamped(position, count: rows.count)
        }
        if !scrolledByHand { moveToPlaying(animated: false) }
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
        settle?.cancel()
        let work = DispatchWorkItem {
            settle = nil
            move(to: focused, animated: true)
        }
        settle = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    /// The arrow keys flip through the row and Return plays the front cover, while the Nook has the keys.
    private func key(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty, !rows.isEmpty else { return false }
        switch event.keyCode {
        case 123, 126, 124, 125:
            let step = event.keyCode == 123 || event.keyCode == 126 ? -1 : 1
            scrolledByHand = true
            move(to: min(rows.count - 1, max(0, focused + step)), animated: true)
        case 36, 76:
            guard rows.indices.contains(focused) else { return false }
            play(rows[focused].song, in: rows[focused].source)
        default:
            return false
        }
        return true
    }
}

/// The playing song's lyric beside the source, turning over with the song: two lines at most,
/// a little smaller rather than cut off.
private struct ShelfLyricLine: View {
    @ObservedObject var service: TeleprompterService
    @ObservedObject private var theme = ThemeStore.shared
    @State private var presentationID = UUID()

    var body: some View {
        Text(service.currentText)
            .font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).lineLimit(2).minimumScaleFactor(0.8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .id(service.lineID)
            .transition(.opacity)
            .animation(theme.reduceMotion ? nil : Design.timed(.easeOut(duration: 0.18)), value: service.lineID)
            // Mounted, it keeps the lookup running, as the Standard look's lyrics do.
            .onAppear { service.setPresentationVisible(true, id: presentationID) }
            .onDisappear { service.setPresentationVisible(false, id: presentationID) }
    }
}



/// The record out of its cover: whose it is and its cover, for the label.
struct ShelfRecord: Equatable {
    var key: String
    var artwork: NSImage?
    /// The song's cover from Spotify, the label's first choice.
    var image: URL?
}

/// One cover: the album art, flat, with a hairline edge.
private struct ShelfSleeve: View, Equatable {
    let song: SpotifyLibrary.Song
    let side: CGFloat

    nonisolated static func == (a: Self, b: Self) -> Bool { a.song == b.song && a.side == b.side }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ShelfCoverImage(url: song.image, title: song.title, side: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.25), radius: 3, y: 1)
        .contentShape(shape)
    }
}

/// A sleeve's cover, square: a file on this Mac draws at once, Spotify's load in the background.
private struct ShelfCoverImage: View {
    let url: URL?
    let title: String
    let side: CGFloat
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Group {
            if let url, url.isFileURL, let image = NSImage(contentsOf: url) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                AsyncImage(url: url) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    ZStack {
                        theme.notch.surface
                        theme.notch.accent.opacity(0.18)
                        Text(String(title.prefix(1))).font(.system(size: max(10, side * 0.38), weight: .bold))
                            .foregroundStyle(theme.notch.accent)
                    }
                }
            }
        }
        .frame(width: side, height: side)
    }
}

/// The record: half out of its cover, turning while its song plays. Clicking it plays or pauses.
/// Only the label turns (the grooves look the same at any angle), on a 30 fps timeline that runs
/// only while the song plays and motion is allowed. With `ascii`, it's the Vinyl look's record,
/// drawn live from the player's cover.
private struct ShelfRecordView: View {
    let record: ShelfRecord
    let diameter: CGFloat
    let ascii: Bool
    /// It's the playing song's (not the last one's, going back in).
    let turning: Bool
    @ObservedObject var nowPlaying: NowPlayingController
    let onToggle: () -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var options = WidgetOptions.shared

    /// 33⅓ turns a minute.
    private static let degreesPerSecond = 360 * 33.333 / 60

    var body: some View {
        let playing = nowPlaying.info.isPlaying && turning
        Button(action: onToggle) {
            disc(spinning: playing && !theme.reduceMotion)
                .frame(width: diameter, height: diameter)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(playing ? "Pause" : "Play")
        .accessibilityLabel(playing ? "Pause" : "Play")
    }

    @ViewBuilder private func disc(spinning: Bool) -> some View {
        if ascii {
            // The scene's record fills 94% of its square.
            AsciiCover(artwork: record.artwork, size: diameter / 0.94, style: options.asciiStyle, scene: .vinyl,
                       detail: options.asciiDetail,
                       position: { [nowPlaying] in
                           let info = nowPlaying.info
                           return info.elapsed + (info.isPlaying ? Date().timeIntervalSince(nowPlaying.elapsedReadAt) : 0)
                       },
                       playing: nowPlaying.info.isPlaying && turning, colouring: options.asciiColours, song: record.key,
                       duration: nowPlaying.info.duration, around: .off)
                .frame(width: diameter, height: diameter)
        } else {
            ZStack {
                ShelfVinyl(diameter: diameter, rim: theme.nookForeground).equatable()
                TimelineView(.periodic(from: .now, by: spinning ? 1.0 / 30 : 3600)) { context in
                    ShelfLabel(artwork: record.artwork, image: record.image, diameter: diameter * 0.38, accent: theme.notch.accent,
                               hole: theme.notch.surface)
                        .equatable()
                        .rotationEffect(.degrees(theme.reduceMotion ? 0 : angle(at: context.date)))
                }
            }
        }
    }

    private func angle(at date: Date) -> Double {
        (nowPlaying.estimatedElapsed(at: date) * Self.degreesPerSecond).truncatingRemainder(dividingBy: 360)
    }
}

/// The record without its label: black vinyl, its grooves and a fixed sheen, drawn once.
private struct ShelfVinyl: View, Equatable {
    let diameter: CGFloat
    let rim: Color

    var body: some View {
        ZStack {
            Circle().fill(Color(white: 0.06))
            Canvas { context, size in
                let middle = CGPoint(x: size.width / 2, y: size.height / 2), outer = size.width / 2
                var radius = outer * 0.42
                var ring = 0
                while radius < outer * 0.97 {
                    // A wider gap between tracks every so often, as on a real record.
                    let gap = ring % 9 == 8
                    context.stroke(Path(ellipseIn: CGRect(x: middle.x - radius, y: middle.y - radius, width: radius * 2, height: radius * 2)),
                                   with: .color(.white.opacity(gap ? 0.1 : 0.045)), lineWidth: gap ? 1.2 : 0.6)
                    radius += outer * 0.024
                    ring += 1
                }
            }
            AngularGradient(stops: [.init(color: .white.opacity(0), location: 0.02), .init(color: .white.opacity(0.13), location: 0.1),
                                    .init(color: .white.opacity(0), location: 0.2), .init(color: .white.opacity(0), location: 0.52),
                                    .init(color: .white.opacity(0.1), location: 0.6), .init(color: .white.opacity(0), location: 0.7)],
                            center: .center)
                .clipShape(Circle())
            Circle().strokeBorder(rim.opacity(0.2), lineWidth: 1)
        }
        .frame(width: diameter, height: diameter)
    }
}

/// The record's label: the song's cover in a circle, with the spindle through it. Its Spotify cover
/// comes first, so the label is always this song's, never the player's last artwork.
private struct ShelfLabel: View, Equatable {
    let artwork: NSImage?
    let image: URL?
    let diameter: CGFloat
    let accent: Color
    let hole: Color

    nonisolated static func == (a: Self, b: Self) -> Bool { a.artwork === b.artwork && a.image == b.image && a.diameter == b.diameter && a.accent == b.accent && a.hole == b.hole }

    var body: some View {
        ZStack {
            if let image {
                ShelfCoverImage(url: image, title: "", side: diameter)
            } else if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else {
                accent
                Image(systemName: "music.note").font(.system(size: diameter * 0.3, weight: .semibold)).foregroundStyle(.black.opacity(0.6))
                    .offset(y: -diameter * 0.18)
            }
            Circle().fill(hole).frame(width: max(4, diameter * 0.07), height: max(4, diameter * 0.07))
        }
        .frame(width: diameter, height: diameter)
        .clipShape(Circle())
        .overlay(Circle().strokeBorder(Color.black.opacity(0.35), lineWidth: 1))
    }
}

/// Takes the arrow keys and Return in the Nook while the Shelf shows, and hands the keys back
/// to whatever had them when it goes. Only in the Nook, never in Settings' preview.
private struct ShelfKeys: NSViewRepresentable {
    let handle: (NSEvent) -> Bool

    func makeNSView(context: Context) -> KeyView { KeyView() }
    func updateNSView(_ view: KeyView, context: Context) { view.handle = handle }

    final class KeyView: NSView {
        var handle: ((NSEvent) -> Bool)?
        private weak var previous: NSResponder?
        override var acceptsFirstResponder: Bool { window is NotchWindow }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window is NotchWindow else { return }
            DispatchQueue.main.async { [weak self, weak window] in
                guard let self, let window, self.window === window, window.firstResponder !== self else { return }
                self.previous = window.firstResponder
                window.makeFirstResponder(self)
            }
        }

        override func viewWillMove(toWindow newWindow: NSWindow?) {
            if newWindow == nil, let window, window.firstResponder === self {
                if let view = previous as? NSView, view.window === window { window.makeFirstResponder(view) }
                else { window.makeFirstResponder(nil) }
            }
            super.viewWillMove(toWindow: newWindow)
        }

        override func keyDown(with event: NSEvent) {
            if handle?(event) != true { super.keyDown(with: event) }
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
                    HStack(spacing: 4) {
                        if !difference.added.isEmpty { tally("+\(difference.added.count.formatted())", .green) }
                        if !difference.removed.isEmpty { tally("−\(difference.removed.count.formatted())", .red) }
                    }
                    .accessibilityElement(children: .ignore)
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
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(difference.groups) { group in
                            VStack(alignment: .leading, spacing: 3) {
                                heading(group)
                                ForEach(Array(group.added.enumerated()), id: \.offset) { row($0.element, added: true) }
                                ForEach(Array(group.removed.enumerated()), id: \.offset) { row($0.element, added: false) }
                            }
                        }
                    }
                    .padding(.top, 4)
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
            // The cover, the song over its artist, and a green plus or red minus at the end.
            HStack(spacing: 9) {
                SpotifyThumbnail(url: song.cover, title: song.title, round: false, size: 26)
                VStack(alignment: .leading, spacing: 1) {
                    Text(song.title).font(.system(size: 11.5, weight: .semibold)).lineLimit(1)
                    Text(song.artists).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 6)
                Image(systemName: added ? "plus" : "minus").font(.system(size: 8, weight: .heavy))
                    .foregroundStyle(added ? Color.green : Color.red)
                    .frame(width: 18, height: 18)
                    .background((added ? Color.green : Color.red).opacity(0.16), in: Circle())
            }
            .padding(.horizontal, 6)
            .frame(height: 34)
            .background(TerminalTabMetrics.fill, in: RoundedRectangle(cornerRadius: TerminalTabMetrics.rowRadius, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(added ? "Added" : "Removed"): \(song.title) by \(song.artists)")
    }

    /// A playlist's name, clear above its songs, with how many came and went.
    private func heading(_ group: SpotifyBackupDiff.Group) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: group.playlist == SpotifyBackupDiff.likedSongs ? "heart.fill" : "music.note.list")
                .font(.system(size: 10, weight: .semibold)).foregroundStyle(theme.notch.accent)
            Text(group.playlist).font(.system(size: 12, weight: .bold)).lineLimit(1)
            Spacer(minLength: 4)
            Text([group.added.isEmpty ? nil : "\(group.added.count) added", group.removed.isEmpty ? nil : "\(group.removed.count) removed"]
                .compactMap { $0 }.joined(separator: " · "))
                .font(.system(size: 9.5, weight: .medium)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 2)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private func tally(_ text: String, _ color: Color) -> some View {
        Text(text).font(.system(size: 10, weight: .bold)).monospacedDigit()
            .foregroundStyle(color)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(color.opacity(0.16), in: Capsule())
    }
}
