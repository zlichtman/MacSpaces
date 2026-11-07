import SwiftUI

/// Settings → Heartable → Music Player: everything about how the
/// Music page looks, top to bottom: its look, the album art (the cover, or live ASCII art with its
/// style, scene, what moves around it, detail and colours; the Vinyl look is always ASCII) and the
/// background's cover tint. The preview on the right moves while the pointer is on the card.
struct MusicPlayerCard: View {
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var nowPlaying = AppServices.shared.nowPlaying
    @State private var hovering = false
    @State private var start = Date()

    var body: some View {
        SettingsCard("Music Player", systemImage: "music.note") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 18) {
                    chips("Look", MusicLook.allCases, selection: $options.musicLook) { $0.title }
                    if options.musicLook == .terminal { vinylColours }
                    if options.musicLook == .shelf { caption("Your Spotify songs and playlists to scroll through and play. It needs Spotify connected, in Music's Backups view.") }
                    albumArt
                    section("Background") {
                        Toggle("Tint the Music page with the playing cover", isOn: $options.albumTint)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                preview
            }
        }
        .onHover { hovering = $0; if $0 { start = Date() } }
    }

    // MARK: - Sections

    private var albumArt: some View {
        section("Album art") {
            // Terminal always draws the cover as ASCII art: the switch shows on and is locked
            // there; Standard and Shelf leave it to you (what you chose is kept for them).
            Toggle("Show the cover as ASCII art",
                   isOn: Binding(get: { showsAscii },
                                 set: { if options.musicLook != .terminal { options.asciiCover = $0 } }))
                .disabled(options.musicLook == .terminal)
                .help(options.musicLook == .terminal ? "The Vinyl look always shows the cover as ASCII art" : "")
            Group {
                chips("Style", AsciiStyle.allCases, selection: $options.asciiStyle) { $0.title }
                chips("Scene", AsciiScene.allCases, selection: $options.asciiScene) { $0.title }
                chips("Around", AsciiAround.allCases, selection: $options.asciiAround) { $0.title }
                chips("Detail", AsciiDetail.allCases, selection: $options.asciiDetail) { $0.title }
                chips("Colours", AsciiColouring.allCases, selection: $options.asciiColours) { $0.title }
            }
            .opacity(showsAscii ? 1 : 0.45)
            .allowsHitTesting(showsAscii)
            caption(options.musicLook == .shelf
                    ? "Every cover on the Shelf, with your Scene and Around on the playing song."
                    : "Made from the playing cover. It moves only while the song plays.")
        }
    }

    /// Pick a part, then which of the theme's colours it uses. It stays linked as themes change.
    private var vinylColours: some View {
        section("Player colours") {
            VinylColourLinks()
            HStack(spacing: 8) {
                caption("Drag a part to a colour, or click one and then the other. Colours too faint to read are lifted automatically.")
                if !options.vinylLinks.isEmpty {
                    Spacer(minLength: 8)
                    Button("Reset") { options.vinylLinks = [:] }.buttonStyle(.settings(.quiet))
                }
            }
        }
    }

    // MARK: - Preview

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.notch.surface)
            if showsAscii {
                AsciiCover(artwork: nowPlaying.info.artwork ?? Self.sample, size: 150, style: options.asciiStyle,
                           scene: options.asciiScene, detail: options.asciiDetail,
                           position: { [start] in Date().timeIntervalSince(start) }, playing: hovering,
                           colouring: options.asciiColours, around: options.asciiAround)
            } else {
                RecordArtwork(artwork: nowPlaying.info.artwork ?? Self.sample, accent: theme.notch.accent,
                              control: theme.notch.control, size: 150)
            }
        }
        .frame(width: 182, height: 182)
        .accessibilityHidden(true)
    }

    /// The page draws the cover as ASCII art: the switch is on, or the look is Terminal.
    private var showsAscii: Bool { options.asciiCover || options.musicLook == .terminal }

    // MARK: - Pieces

    private func label(_ title: String) -> some View {
        Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
    }

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            label(title)
            content()
        }
    }

    private func chips<Choice: Hashable & Identifiable>(_ title: String, _ choices: [Choice], selection: Binding<Choice>,
                                                       label text: @escaping (Choice) -> String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            label(title)
            ChipFlow(spacing: 5) {
                ForEach(choices) { choice in
                    Button { selection.wrappedValue = choice } label: {
                        Text(text(choice)).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).frame(height: 24)
                    }
                    .buttonStyle(SettingsChipStyle(selected: selection.wrappedValue == choice))
                }
            }
        }
    }

    /// A cover for the preview when nothing is playing: a striped sun over the sea.
    static let sample: NSImage = NSImage(size: NSSize(width: 256, height: 256), flipped: false) { rect in
        NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.55, blue: 0.4, alpha: 1), NSColor(srgbRed: 0.12, green: 0.07, blue: 0.25, alpha: 1)])?
            .draw(in: rect, angle: 90)
        NSColor(srgbRed: 1, green: 0.93, blue: 0.75, alpha: 1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 58, y: 96, width: 140, height: 140)).fill()
        NSColor(srgbRed: 0.12, green: 0.07, blue: 0.25, alpha: 1).setFill()
        for index in 0..<6 { NSRect(x: 0, y: 118 + index * 16, width: 256, height: 3 + index).fill() }
        NSRect(x: 0, y: 0, width: 256, height: 100).fill()
        return true
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
            caption("For songs Spotify plays from your own files, read from the folder you choose. Nothing is sent anywhere.")
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
                Text("Reading the folders Spotify lists.")
                    .font(.caption).foregroundStyle(.secondary)
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

    private func caption(_ text: String) -> some View {
        Text(text).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
    }
}

/// Chips in rows, starting a new row when the next chip doesn't fit the width.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    private func rows(_ subviews: Subviews, width: CGFloat) -> [[(index: Int, size: CGSize)]] {
        var rows: [[(index: Int, size: CGSize)]] = [[]]
        var x: CGFloat = 0
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0, x + size.width > width {
                rows.append([])
                x = 0
            }
            rows[rows.count - 1].append((index, size))
            x += size.width + spacing
        }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width.flatMap { $0.isFinite ? $0 : nil } ?? .infinity
        let rows = rows(subviews, width: width)
        let widest = rows.map { row in row.reduce(0) { $0 + $1.size.width } + spacing * CGFloat(max(0, row.count - 1)) }.max() ?? 0
        let height = rows.reduce(0) { $0 + ($1.map(\.size.height).max() ?? 0) } + spacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: width.isFinite ? min(width, widest) : widest, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            let height = row.map(\.size.height).max() ?? 0
            for item in row {
                subviews[item.index].place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(item.size))
                x += item.size.width + spacing
            }
            y += height + spacing
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
