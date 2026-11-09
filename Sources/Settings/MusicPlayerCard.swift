import SwiftUI

/// Settings → Heartable → Music Player: how the Music page looks. One live preview on top (the
/// real Music page, small, with the playing song or a sample), then the look, the album art (the
/// cover, or live ASCII art with its style, scene, what moves around it, detail and colours; the
/// Vinyl look is always ASCII), the cover tint, and Vinyl's colour map folded under Customise.
/// Every setting here changes the preview.
struct MusicPlayerCard: View {
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var nowPlaying = AppServices.shared.nowPlaying

    var body: some View {
        SettingsCard("Music Player", systemImage: "music.note") {
            preview
            SettingsSegmentedPicker("Look", selection: $options.musicLook, options: MusicLook.allCases) { $0.title }
            if options.musicLook == .shelf {
                SettingsCaption("Your Spotify songs as covers to flip through, and a record player. Needs Spotify connected.")
            }
            Divider()
            albumArt
            Divider()
            Toggle("Tint the Music page with the playing cover", isOn: $options.albumTint)
            if options.musicLook == .terminal {
                Divider()
                SettingsDisclosure("Customise", detail: "Vinyl's colours") { vinylColours }
            }
        }
    }

    // MARK: - Sections

    private var albumArt: some View {
        SettingsSection("Album art") {
            // Vinyl always draws the cover as ASCII art: the switch shows on and is locked there;
            // Standard and Shelf leave it to you (what you chose is kept for them).
            Toggle("Show the cover as ASCII art",
                   isOn: Binding(get: { showsAscii },
                                 set: { if options.musicLook != .terminal { options.asciiCover = $0 } }))
                .disabled(options.musicLook == .terminal)
                .help(options.musicLook == .terminal ? "The Vinyl look always shows the cover as ASCII art" : "")
            Group {
                HStack(spacing: 20) {
                    menu("Style", AsciiStyle.allCases, selection: $options.asciiStyle) { $0.title }
                    menu("Scene", AsciiScene.allCases, selection: $options.asciiScene) { $0.title }
                    menu("Around", AsciiAround.allCases, selection: $options.asciiAround) { $0.title }
                    Spacer(minLength: 0)
                }
                HStack(spacing: 20) {
                    SettingsSegmentedPicker("Detail", selection: $options.asciiDetail, options: AsciiDetail.allCases) { $0.title }
                        .fixedSize()
                    SettingsSegmentedPicker("Colours", selection: $options.asciiColours, options: AsciiColouring.allCases) { $0.title }
                        .fixedSize()
                    Spacer(minLength: 0)
                }
            }
            .disabled(!showsAscii)
            SettingsCaption(options.musicLook == .shelf
                            ? "With the Vinyl scene, the Shelf's record turns as ASCII art; the covers stay pictures."
                            : "Made from the playing cover. It moves only while the song plays.")
        }
    }

    /// Pick a part, then which of the theme's colours it uses. It stays linked as themes change.
    private var vinylColours: some View {
        VStack(alignment: .leading, spacing: 10) {
            VinylColourLinks()
            HStack(spacing: 8) {
                SettingsCaption("Drag a part to a colour, or click one and then the other.",
                                help: "Colours too faint to read on the theme are lifted automatically.")
                Spacer(minLength: 8)
                if !options.vinylLinks.isEmpty {
                    Button("Reset") { options.vinylLinks = [:] }.buttonStyle(.settings(.quiet))
                }
            }
        }
    }

    // MARK: - Preview

    /// The Nook's Music page as it is drawn, at 60%: the playing song, or a sample when nothing
    /// plays (its cover still, so the preview costs nothing while it waits).
    private var preview: some View {
        let player = nowPlaying.info.hasTrack ? nowPlaying : samplePlayer
        let page = CGSize(width: 600, height: 300), scale: CGFloat = 0.6
        return SettingsPreview {
            ZStack {
                if options.albumTint, theme.activeMotif == nil, theme.activeLook?.picture != true {
                    ArtworkAmbience(artwork: player.info.artwork ?? Self.sample(accent: NSColor(theme.accent)).image).blur(radius: 18)
                }
                MediaPlayerView(nowPlaying: player, largeArtwork: true)
                    .frame(width: page.width, height: page.height)
                    .scaleEffect(scale)
                    .frame(width: page.width * scale, height: page.height * scale)
            }
        }
    }

    /// The page draws the cover as ASCII art: the switch is on, or the look is Terminal.
    private var showsAscii: Bool { options.asciiCover || options.musicLook == .terminal }

    // MARK: - Pieces

    /// A dropdown for a choice of more than three, its label on the left like a segmented row's.
    private func menu<Choice: Hashable & Identifiable>(_ title: String, _ choices: [Choice], selection: Binding<Choice>,
                                                      label text: @escaping (Choice) -> String) -> some View {
        Picker(title, selection: selection) {
            ForEach(choices) { Text(text($0)).tag($0) }
        }
        .pickerStyle(.menu)
        .fixedSize()
    }

    /// Inert sample content for the preview while nothing plays: no providers start. Its cover
    /// is drawn from the theme's accent, so the sample and its tint match the theme.
    private var samplePlayer: NowPlayingController {
        let cover = Self.sample(accent: NSColor(theme.accent))
        if let player = Self.samplePlayers[cover.key] { return player }
        var info = NowPlayingInfo()
        info.title = "Your music"; info.artist = "Artist"; info.album = "Album"
        info.sourceName = "Music"; info.sourceBundleID = "com.apple.Music"
        info.duration = 240; info.elapsed = 72
        info.capabilities = [.playPause, .previous, .next, .seek]
        info.artwork = cover.image
        let player = NowPlayingController(preview: info)
        Self.samplePlayers[cover.key] = player
        return player
    }
    @MainActor private static var samplePlayers: [String: NowPlayingController] = [:]
    @MainActor private static var samples: [String: NSImage] = [:]

    /// A quiet cover for the preview when nothing plays: the accent as a soft wash, deepening to
    /// a dark corner, with a record and its label. Drawn once per accent.
    @MainActor static func sample(accent: NSColor) -> (key: String, image: NSImage) {
        let colour = accent.usingColorSpace(.sRGB) ?? .systemPink
        let key = String(format: "%.3f-%.3f-%.3f", colour.redComponent, colour.greenComponent, colour.blueComponent)
        if let image = samples[key] { return (key, image) }
        let light = colour.blended(withFraction: 0.55, of: .white) ?? colour
        let deep = colour.blended(withFraction: 0.78, of: .black) ?? colour
        let image = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
            NSGradient(colors: [light, colour, deep])?.draw(in: rect, angle: -45)
            let record = NSRect(x: 92, y: 20, width: 210, height: 210)
            NSColor(white: 0.06, alpha: 0.88).setFill()
            NSBezierPath(ovalIn: record).fill()
            NSColor(white: 1, alpha: 0.07).setStroke()
            for inset in stride(from: CGFloat(14), through: 70, by: 9) {
                let groove = NSBezierPath(ovalIn: record.insetBy(dx: inset, dy: inset)); groove.lineWidth = 1; groove.stroke()
            }
            light.setFill()
            NSBezierPath(ovalIn: record.insetBy(dx: 78, dy: 78)).fill()
            NSColor(white: 0.06, alpha: 1).setFill()
            NSBezierPath(ovalIn: record.insetBy(dx: 101, dy: 101)).fill()
            return true
        }
        samples[key] = image
        return (key, image)
    }
}

/// Settings → Heartable → Local files: covers and lyrics for songs Spotify plays from your own
/// files, read from a folder you choose. Off by default; turning it on asks for the folder.
struct LocalFilesCard: View {
    /// Off by default. Turning it on asks for the music folder; cancelling leaves it off.
    @AppStorage(LocalCovers.enabledKey) private var localFileCovers = false
    /// The chosen folder's bookmark; unset with the switch on reads the folders Spotify names.
    @AppStorage(LocalCovers.folderKey) private var musicFolder: Data?

    var body: some View {
        SettingsCard("Local files", systemImage: "folder") {
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
            SettingsCaption("For songs Spotify plays from your own files. Nothing is sent anywhere.",
                            help: "Covers and lyrics are read from the folder you choose, on this Mac.")
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
                SettingsCaption("Reading the folders Spotify lists.")
                Spacer()
                Button("Choose Folder") { chooseMusicFolder { _ in } }
                    .buttonStyle(.settings())
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
}

/// The Vinyl look's parts on the left, the theme's colours on the right, and a line in its colour
/// from each part to the colour it uses, so every pairing shows at once.
private struct VinylColourLinks: View {
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @State private var selected: VinylPart?
    @State private var drag: (part: VinylPart, point: CGPoint)?

    private static let rowHeight: CGFloat = 24
    private static let columnWidth: CGFloat = 84
    private static let dot: CGFloat = 14
    private static let height = rowHeight * CGFloat(VinylPart.allCases.count)
    private static let inkHeight = height / CGFloat(VinylInk.allCases.count)
    private static let space = "vinylColourLinks"

    private func ink(of part: VinylPart) -> VinylInk {
        options.vinylLinks[part.rawValue].flatMap(VinylInk.init) ?? part.standard
    }

    private func link(_ part: VinylPart, to ink: VinylInk) {
        options.vinylLinks[part.rawValue] = ink == part.standard ? nil : ink.rawValue
    }

    private func partY(_ part: VinylPart) -> CGFloat {
        Self.rowHeight * (CGFloat(VinylPart.allCases.firstIndex(of: part) ?? 0) + 0.5)
    }

    private func inkY(_ ink: VinylInk) -> CGFloat {
        Self.inkHeight * (CGFloat(VinylInk.allCases.firstIndex(of: ink) ?? 0) + 0.5)
    }

    var body: some View {
        let inks = ThemeInks.current(theme)
        GeometryReader { proxy in
            let startX = Self.columnWidth
            let endX = proxy.size.width - Self.columnWidth
            ZStack(alignment: .topLeading) {
                Canvas { context, _ in
                    func line(from: CGPoint, to: CGPoint, colour: Color, width: CGFloat) {
                        let bend = max(24, (to.x - from.x) / 2)
                        var path = Path()
                        path.move(to: from)
                        path.addCurve(to: to, control1: CGPoint(x: from.x + bend, y: from.y), control2: CGPoint(x: to.x - bend, y: to.y))
                        context.stroke(path, with: .color(colour), style: StrokeStyle(lineWidth: width, lineCap: .round))
                    }
                    for part in VinylPart.allCases where part != drag?.part {
                        let quiet = selected != nil && selected != part
                        line(from: CGPoint(x: startX, y: partY(part)), to: CGPoint(x: endX, y: inkY(ink(of: part))),
                             colour: inks.colour(ink(of: part)).opacity(quiet ? 0.3 : 0.9), width: selected == part ? 2.5 : 1.5)
                    }
                    if let drag {
                        line(from: CGPoint(x: startX, y: partY(drag.part)), to: drag.point,
                             colour: inks.colour(ink(of: drag.part)), width: 2.5)
                    }
                }
                .allowsHitTesting(false)
                VStack(spacing: 0) {
                    ForEach(VinylPart.allCases) { part in partRow(part, inks: inks, endX: endX) }
                }
                .frame(width: Self.columnWidth)
                VStack(spacing: 0) {
                    ForEach(VinylInk.allCases) { ink in inkRow(ink, inks: inks) }
                }
                .frame(width: Self.columnWidth)
                .offset(x: endX)
            }
            .coordinateSpace(name: Self.space)
        }
        .frame(maxWidth: 460)
        .frame(height: Self.height)
    }

    private func partRow(_ part: VinylPart, inks: ThemeInks, endX: CGFloat) -> some View {
        Button { selected = selected == part ? nil : part } label: {
            HStack(spacing: 8) {
                Text(part.label)
                    .font(.system(size: 12, weight: selected == part ? .semibold : .regular))
                    .foregroundStyle(theme.settingsForeground)
                Spacer(minLength: 0)
                swatch(inks.colour(ink(of: part)), ringed: selected == part)
            }
            .frame(height: Self.rowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .simultaneousGesture(DragGesture(minimumDistance: 3, coordinateSpace: .named(Self.space))
            .onChanged { drag = (part, $0.location) }
            .onEnded { value in
                drag = nil
                guard value.location.x > endX - 30 else { return }
                let index = Int(value.location.y / Self.inkHeight)
                link(part, to: VinylInk.allCases[min(max(index, 0), VinylInk.allCases.count - 1)])
            })
        .help("\(part.label) uses \(ink(of: part).title)")
        .accessibilityLabel("\(part.label), linked to \(ink(of: part).title)")
        .accessibilityAddTraits(selected == part ? .isSelected : [])
    }

    private func inkRow(_ ink: VinylInk, inks: ThemeInks) -> some View {
        let chosen = selected.map { self.ink(of: $0) == ink } ?? false
        return Button {
            if let selected { link(selected, to: ink) }
        } label: {
            HStack(spacing: 8) {
                swatch(inks.colour(ink), ringed: chosen)
                Text(ink.title)
                    .font(.system(size: 12, weight: chosen ? .semibold : .regular))
                    .foregroundStyle(theme.settingsForeground)
                Spacer(minLength: 0)
            }
            .frame(height: Self.inkHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(selected == nil)
        .accessibilityLabel(ink.title)
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func swatch(_ colour: Color, ringed: Bool) -> some View {
        Circle().fill(colour)
            .overlay(Circle().strokeBorder(Color.primary.opacity(0.28), lineWidth: 1))
            .frame(width: Self.dot, height: Self.dot)
            .padding(2)
            .overlay(Circle().strokeBorder(theme.settingsForeground.opacity(ringed ? 0.9 : 0), lineWidth: 1.5))
    }
}
