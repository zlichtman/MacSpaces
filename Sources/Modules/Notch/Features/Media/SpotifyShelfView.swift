import SwiftUI
import AppKit

/// The Music page's Shelf look: album covers and a turntable. One source's songs (Liked Songs or
/// the playlist you pick, or the first playlist with songs when that has none) stand as covers you
/// flip through; the one at the front stands up a little, described in the column on the right.
/// Always the real covers and a real record: ASCII art is the Vinyl look's. The playing song's record sits on the turntable and turns while it plays; a new song
/// slides the old record back towards the crate and the new one out onto the platter.
/// Only the sleeves near the front are drawn, and while a song plays only the record's label and
/// the tonearm move (`ShelfTurntable`).
struct SpotifyShelfView: View {
    @ObservedObject var nowPlaying: NowPlayingController
    /// The playing song's lyrics, a line at a time beside the source.
    var lyrics: TeleprompterService?
    #if DEBUG
    /// Check renders: the crate at this position and the record this far out of its sleeve
    /// (0 in, 1 on the platter), held there.
    var previewPose: (position: CGFloat, out: CGFloat)?
    #endif
    @ObservedObject private var spotify = SpotifyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var options = WidgetOptions.shared
    /// Where the crate is, in sleeves: between two whole numbers while it's moving.
    @State private var position: CGFloat = 0
    @State private var settle: DispatchWorkItem?
    /// You've flipped through, so songs arriving no longer take you to the playing one.
    @State private var scrolledByHand = false
    /// The sleeve at the front, so it stays there when songs arrive around it.
    @State private var anchor: (id: String, index: Int)?
    /// The record on the platter: the playing song's, or the one before while it goes back.
    @State private var record: ShelfRecord?
    /// How far the record is out of its sleeve: 0 in the crate, 1 on the platter.
    @State private var recordOut: CGFloat = 1
    /// Counts record changes, so a slow one never lands after a newer one.
    @State private var swap = 0
    /// The sleeve under the pointer, standing up a little.
    @State private var hovered: Int?

    /// The scrolling that moves the crate by one sleeve.
    private static let pointsPerRow: CGFloat = 56
    private static let footHeight: CGFloat = 32
    private static let footGap: CGFloat = 12

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
        #endif
        return recordOut
    }
    private var focused: Int { Int(SongShelfPose.clamped(shownPosition, count: rows.count).rounded()) }
    private var playingKey: String {
        nowPlaying.info.hasTrack ? "\(nowPlaying.info.title)|\(nowPlaying.info.artist)" : ""
    }
    /// Album art as ASCII with the Vinyl scene: the record turns as the Vinyl look's.
    private var asciiRecord: Bool { options.asciiCover && options.asciiScene == .vinyl }
    /// The playing song's cover from Spotify, for the record's label when the player has none.
    private var playingImage: URL? { rows.first(where: { isPlaying($0.song) })?.song.image }

    var body: some View {
        if !spotify.isConnected {
            SpotifyConnectView(purpose: "Flip through your playlists and Liked Songs, and play any song")
        } else {
            // The covers and the turntable, the front cover's details in a column on the right,
            // and along the foot the source, the playing song's lyric and, while the front sleeve
            // is another song, the way back to the playing one.
            GeometryReader { proxy in
                let gap: CGFloat = 18
                let column = max(140, min(180, (proxy.size.width - 40) * 0.28))
                let deckHeight = max(120, proxy.size.height - 4 - Self.footHeight - Self.footGap)
                VStack(spacing: Self.footGap) {
                    HStack(alignment: .center, spacing: gap) {
                        deck.frame(maxWidth: .infinity).frame(height: deckHeight)
                        details(width: column).frame(width: column)
                    }
                    .frame(maxHeight: .infinity)
                    HStack(alignment: .center, spacing: 12) {
                        sourceMenu
                        Group {
                            if let lyrics, nowPlaying.info.hasTrack { ShelfLyricLine(service: lyrics) } else { Color.clear }
                        }
                        .frame(maxWidth: .infinity)
                        if nowPlaying.info.hasTrack, !focusedIsPlaying {
                            playingChip.frame(maxWidth: 190)
                        }
                    }
                    .frame(height: Self.footHeight)
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
            // A new song brings the crate to it, unless you've flipped off to look around, and
            // swaps the record on the platter.
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

    // MARK: - The covers and the turntable

    private var deck: some View {
        GeometryReader { proxy in
            let layout = ShelfDeckLayout(size: proxy.size)
            ZStack(alignment: .topLeading) {
                // ASCII art with the Vinyl scene: the record is the Vinyl look's, arm and all, with no
                // turntable around it. Otherwise a real record on a platter, under a metal tonearm.
                if !asciiRecord {
                    ShelfPlatter(layout: layout).zIndex(-10)
                }
                if let record {
                    ShelfRecordView(layout: layout, record: record, out: shownOut, ascii: asciiRecord,
                                    nowPlaying: nowPlaying, onToggle: { nowPlaying.togglePlayPause() })
                        .zIndex(-0.5)
                }
                if !asciiRecord {
                    ShelfTonearm(layout: layout, down: record != nil && shownOut == 1 && nowPlaying.info.isPlaying,
                                 nowPlaying: nowPlaying)
                        .zIndex(6)
                }
                if rows.isEmpty {
                    Text(spotify.shelfLoading ? "Loading your songs" : spotify.problem ?? "No songs here yet")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(width: layout.frontRight, height: layout.sleeve)
                        .position(x: layout.frontRight / 2, y: layout.base - layout.sleeve / 2)
                        .zIndex(1)
                } else {
                    ForEach(visible, id: \.self) { index in
                        sleeve(index, layout: layout)
                    }
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
        }
        .background {
            ScrollWheelCatcher(onScroll: scrolled, onEnded: {}, onlyInside: true)
        }
    }

    private var visible: [Int] {
        guard !rows.isEmpty else { return [] }
        let middle = focused
        return Array(max(0, middle - 1)...min(rows.count - 1, middle + SongShelfPose.reach))
    }

    @ViewBuilder private func sleeve(_ index: Int, layout: ShelfDeckLayout) -> some View {
        let distance = CGFloat(index) - shownPosition
        let pose = SongShelfPose(distance: distance)
        let side = layout.sleeve
        // Under the pointer, a cover stands up a little to be seen.
        let lift = pose.lift + (hovered == index && distance > -0.5 ? 0.07 : 0)
        let row = rows[index]
        Button {
            move(to: index, animated: true)
            play(row.song, in: row.source)
        } label: {
            ShelfSleeve(song: row.song, side: side)
                .equatable()
                .overlay(RoundedRectangle(cornerRadius: 3, style: .continuous).fill(Color.black).opacity(pose.shade))
        }
        .buttonStyle(.plain)
        .scaleEffect(x: pose.scale, y: pose.scale * pose.tip, anchor: .bottom)
        .position(x: layout.frontRight - side / 2 + pose.x * side, y: layout.base - lift * side - side / 2)
        .opacity(pose.opacity)
        // Flipped past, a cover tips forward and fades; the rest stand behind it, nearest in front.
        .zIndex(distance < 0 ? 10 : -Double(distance))
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

    /// The record goes back into its sleeve and the new song's comes out onto the platter.
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

    // MARK: - The column and the foot

    /// The front sleeve's song, then the transport and the timeline for what's playing.
    private func details(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            if rows.indices.contains(focused) {
                VStack(alignment: .leading, spacing: 3) {
                    songCaption(rows[focused].song, in: rows[focused].source, number: rows[focused].number)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            MusicTransportControls(nowPlaying: nowPlaying, width: width).padding(.top, 12)
            PlaybackTimeline(nowPlaying: nowPlaying, onScrub: { lyrics?.scrub(to: $0) }).padding(.top, 6)
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
        Text(song.title).font(.system(size: 18, weight: .bold)).lineLimit(2).minimumScaleFactor(0.7)
        Text(song.artists).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.75)
        Text(song.album).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).minimumScaleFactor(0.75)
        Text(numbering(number, in: source) + (isPlaying(song) ? " · Playing" : ""))
            .font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
    }

    private func numbering(_ number: Int, in source: SpotifyLibrary.ShelfSource) -> String {
        if let total = source.total { return "\(number.formatted()) of \(total.formatted())" }
        return "\(number.formatted()) of \(rows.count.formatted())\(spotify.shelfLoading ? " so far" : "")"
    }

    /// What the shelf shows, as a pill at the foot you switch often: Liked Songs or a playlist, from a list
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
        .fixedSize()
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

    /// Rows arrived or went: the one in the middle stays there, then the shelf goes to the
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

    /// The arrow keys flip through the crate and Return plays the front sleeve, while the Nook has the keys.
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



/// The record on the Shelf's turntable: whose it is and its cover, for the label.
struct ShelfRecord: Equatable {
    var key: String
    var artwork: NSImage?
    /// The song's cover from Spotify, used when the player shares no artwork.
    var image: URL?
}

/// Where the Shelf's crate and turntable sit in the room they have: the turntable on the right,
/// its platter to the left of the tonearm, and the crate on the left, its front sleeve just short
/// of the platter, all standing on one line.
struct ShelfDeckLayout {
    let size: CGSize
    /// The turntable's base.
    let plinth: CGRect
    let platterCenter: CGPoint
    let platter: CGFloat
    /// The record's diameter on the platter.
    let disc: CGFloat
    let pivot: CGPoint
    /// The tonearm, from the pivot to the needle.
    let arm: CGFloat
    /// A sleeve's side at the front of the crate.
    let sleeve: CGFloat
    /// The front sleeve's right edge.
    let frontRight: CGFloat
    /// Where the sleeves stand.
    let base: CGFloat
    /// The line everything stands on.
    let ground: CGFloat

    init(size: CGSize) {
        self.size = size
        let width = max(size.width, 160), height = max(size.height, 100)
        let plinthWidth = min(height * 0.95, width * 0.47)
        platter = min(height * 0.86, plinthWidth * 0.8)
        let plinthHeight = min(height, platter + plinthWidth * 0.14)
        ground = (height + plinthHeight) / 2
        plinth = CGRect(x: width - plinthWidth, y: ground - plinthHeight, width: plinthWidth, height: plinthHeight)
        platterCenter = CGPoint(x: plinth.minX + plinthWidth * 0.07 + platter / 2, y: plinth.midY)
        disc = platter * 0.95
        pivot = CGPoint(x: plinth.minX + plinthWidth * 0.895, y: plinth.minY + plinthWidth * 0.13)
        arm = hypot(platterCenter.x - pivot.x, platterCenter.y - pivot.y) * 0.97
        frontRight = plinth.minX - 12
        sleeve = max(40, min(height * 0.8, frontRight / 1.5, disc * 0.95))
        base = ground - 2
    }

    /// The front sleeve's middle, where the record goes back in.
    var sleeveCenter: CGPoint { CGPoint(x: frontRight - sleeve / 2, y: base - sleeve / 2) }

    /// The tonearm's turn from straight down (clockwise, onto the record) that puts the needle
    /// `radius` from the record's middle.
    func armAngle(radius: CGFloat) -> CGFloat {
        let toward = atan2(-(platterCenter.x - pivot.x), platterCenter.y - pivot.y)
        func gap(_ angle: CGFloat) -> CGFloat {
            hypot(pivot.x - sin(angle) * arm - platterCenter.x, pivot.y + cos(angle) * arm - platterCenter.y) - radius
        }
        var low = Self.restAngle, high = toward
        for _ in 0..<24 {
            let middle = (low + high) / 2
            if gap(middle) > 0 { low = middle } else { high = middle }
        }
        return (low + high) / 2
    }

    /// The tonearm at rest, beside the platter.
    static let restAngle: CGFloat = -0.12
}

/// One cover: the album art on card, with a little light on its top edge.
private struct ShelfSleeve: View, Equatable {
    let song: SpotifyLibrary.Song
    let side: CGFloat

    nonisolated static func == (a: Self, b: Self) -> Bool { a.song == b.song && a.side == b.side }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: 3, style: .continuous)
        ZStack {
            ShelfCoverImage(url: song.image, title: song.title, side: side)
            LinearGradient(stops: [.init(color: .white.opacity(0.16), location: 0), .init(color: .clear, location: 0.18)],
                           startPoint: .top, endPoint: .bottom)
        }
        .frame(width: side, height: side)
        .clipShape(shape)
        .overlay(shape.strokeBorder(Color.white.opacity(0.1), lineWidth: 0.5))
        .shadow(color: .black.opacity(0.45), radius: 6, y: 3)
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

/// The platter the record sits on: a dark mat in a brushed-metal rim, with a soft shadow. No
/// base around it, so the record and arm stand on the Nook's own surface.
private struct ShelfPlatter: View {
    let layout: ShelfDeckLayout

    var body: some View {
        let size = layout.platter
        ZStack {
            Circle().fill(Color(white: 0.09))
            Circle().strokeBorder(
                AngularGradient(colors: [Color(white: 0.78), Color(white: 0.42), Color(white: 0.85), Color(white: 0.38), Color(white: 0.78)],
                                center: .center),
                lineWidth: max(2, size * 0.022))
            Circle().strokeBorder(Color.black.opacity(0.5), lineWidth: 1).padding(max(2, size * 0.022))
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
        .position(layout.platterCenter)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// The record: out on the platter, turning while the song plays, or on its way into or out of
/// the front sleeve (`out`, 0 in the sleeve to 1 on the platter), smaller as it goes back into
/// the crate. Clicking it plays or pauses. Only the label turns (the grooves and their sheen look
/// the same at any angle), on a 30 fps timeline that runs only while the song plays and motion is
/// allowed. With `ascii`, it's the Vinyl look's record, its own arm included, drawn live from the
/// player's cover.
private struct ShelfRecordView: View {
    let layout: ShelfDeckLayout
    let record: ShelfRecord
    let out: CGFloat
    let ascii: Bool
    @ObservedObject var nowPlaying: NowPlayingController
    let onToggle: () -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var options = WidgetOptions.shared

    /// 33⅓ turns a minute.
    private static let degreesPerSecond = 360 * 33.333 / 60

    var body: some View {
        let playing = nowPlaying.info.isPlaying
        let spinning = playing && !theme.reduceMotion
        let start = layout.sleeveCenter, end = layout.platterCenter
        let scale = layout.sleeve * 0.9 / layout.disc + (1 - layout.sleeve * 0.9 / layout.disc) * out
        Button(action: onToggle) {
            disc(spinning: spinning)
                .frame(width: layout.disc, height: layout.disc)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .shadow(color: .black.opacity(ascii ? 0 : 0.4), radius: 5, y: 2)
        .scaleEffect(scale)
        .position(x: start.x + (end.x - start.x) * out, y: start.y + (end.y - start.y) * out)
        .help(playing ? "Pause" : "Play")
        .accessibilityLabel(playing ? "Pause" : "Play")
    }

    @ViewBuilder private func disc(spinning: Bool) -> some View {
        if ascii {
            // The scene's record fills 94% of its square; the arm reaches into the corners.
            AsciiCover(artwork: record.artwork, size: layout.disc / 0.94, style: options.asciiStyle, scene: .vinyl,
                       detail: options.asciiDetail,
                       position: { [nowPlaying] in
                           let info = nowPlaying.info
                           return info.elapsed + (info.isPlaying ? Date().timeIntervalSince(nowPlaying.elapsedReadAt) : 0)
                       },
                       playing: nowPlaying.info.isPlaying, colouring: options.asciiColours, song: record.key,
                       duration: nowPlaying.info.duration, around: .off)
                .frame(width: layout.disc, height: layout.disc)
        } else {
            plainDisc(spinning: spinning)
        }
    }

    private func plainDisc(spinning: Bool) -> some View {
        ZStack {
            ShelfVinyl(diameter: layout.disc, rim: theme.nookForeground).equatable()
            TimelineView(.periodic(from: .now, by: spinning ? 1.0 / 30 : 3600)) { context in
                ShelfLabel(artwork: record.artwork, image: record.image, diameter: layout.disc * 0.38, accent: theme.notch.accent,
                           hole: theme.notch.surface)
                    .equatable()
                    .rotationEffect(.degrees(theme.reduceMotion ? 0 : angle(at: context.date)))
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

/// The record's label: the song's cover in a circle, with the spindle through it.
private struct ShelfLabel: View, Equatable {
    let artwork: NSImage?
    let image: URL?
    let diameter: CGFloat
    let accent: Color
    let hole: Color

    nonisolated static func == (a: Self, b: Self) -> Bool { a.artwork === b.artwork && a.image == b.image && a.diameter == b.diameter && a.accent == b.accent && a.hole == b.hole }

    var body: some View {
        ZStack {
            if let artwork {
                Image(nsImage: artwork).resizable().scaledToFill()
            } else if let image {
                ShelfCoverImage(url: image, title: "", side: diameter)
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

/// The tonearm: at rest beside the platter, or down on the record while the song plays, moving
/// from the outside in as the song goes on (stepping once a second, only while it plays).
private struct ShelfTonearm: View {
    let layout: ShelfDeckLayout
    /// The needle's on the record.
    let down: Bool
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        let moving = down && !theme.reduceMotion
        TimelineView(.periodic(from: .now, by: moving ? 1 : 3600)) { context in
            arm.rotationEffect(.radians(angle(at: context.date)))
        }
        .frame(width: layout.arm * 2 + 40, height: layout.arm * 2 + 40)
        .position(layout.pivot)
        .animation(theme.reduceMotion ? nil : .spring(response: 0.6, dampingFraction: 0.86).delay(down ? 0.35 : 0), value: down)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private func angle(at date: Date) -> CGFloat {
        guard down else { return ShelfDeckLayout.restAngle }
        let info = nowPlaying.info
        let progress = info.duration > 0 ? min(1, max(0, nowPlaying.estimatedElapsed(at: date) / info.duration)) : 0
        let outer = layout.armAngle(radius: layout.disc * 0.46), inner = layout.armAngle(radius: layout.disc * 0.24)
        return outer + (inner - outer) * CGFloat(progress)
    }

    /// Brushed metal, the same in every theme: a pivot on its base, a counterweight behind it,
    /// the tube, and a graphite headshell with its cartridge at the needle.
    private var arm: some View {
        let length = layout.arm
        let metal = LinearGradient(colors: [Color(white: 0.62), Color(white: 0.96), Color(white: 0.7)],
                                   startPoint: .leading, endPoint: .trailing)
        return ZStack {
            // The tube, from the pivot to the headshell.
            Capsule().fill(metal).frame(width: 3.4, height: length - 14).offset(y: (length - 14) / 2)
            // The counterweight, behind the pivot.
            RoundedRectangle(cornerRadius: 3, style: .continuous).fill(LinearGradient(colors: [Color(white: 0.22), Color(white: 0.42), Color(white: 0.2)], startPoint: .leading, endPoint: .trailing))
                .frame(width: 13, height: 15).offset(y: -17)
            // The headshell and its cartridge, angled like a real one.
            ZStack {
                RoundedRectangle(cornerRadius: 2.5, style: .continuous).fill(Color(white: 0.16))
                    .overlay(RoundedRectangle(cornerRadius: 2.5, style: .continuous).strokeBorder(Color.white.opacity(0.25), lineWidth: 0.6))
                    .frame(width: 10, height: 18)
                RoundedRectangle(cornerRadius: 1, style: .continuous).fill(Color(white: 0.75)).frame(width: 5, height: 6).offset(y: 5)
            }
            .rotationEffect(.degrees(-20))
            .offset(x: 1.5, y: length - 8)
            // The pivot on its base.
            Circle().fill(RadialGradient(colors: [Color(white: 0.9), Color(white: 0.45)], center: .topLeading, startRadius: 1, endRadius: 16))
                .frame(width: 22, height: 22)
            Circle().fill(Color(white: 0.2)).frame(width: 9, height: 9)
        }
        .shadow(color: .black.opacity(0.45), radius: 3, y: 2)
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
