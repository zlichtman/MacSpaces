import SwiftUI

/// Settings → Appearance → Album art, next to Lyrics: the Music page's cover as the artwork
/// or as live ASCII art, with its style, scene, detail and colours and a preview; and whether
/// the cover tints the Music page; and the page's look (Standard or Terminal, which is always ASCII).
/// The preview moves while the pointer is on the card; it holds still otherwise.
struct AsciiArtPicker: View {
    @ObservedObject private var options = WidgetOptions.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var nowPlaying = AppServices.shared.nowPlaying
    @State private var hovering = false
    @State private var start = Date()

    var body: some View {
        SettingsCard("Album art", systemImage: "square.grid.3x3") {
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 12) {
                    // The page's look applies whatever the cover is, so it's never dimmed.
                    chips("Look", MusicLook.allCases, selection: $options.musicLook, dims: false) { $0.title }
                    Toggle("Show the Music page's cover as ASCII art", isOn: $options.asciiCover)
                        // Terminal always draws the cover as ASCII art.
                        .disabled(options.musicLook == .terminal)
                    chips("Style", AsciiStyle.allCases, selection: $options.asciiStyle) { $0.title }
                    chips("Scene", AsciiScene.allCases, selection: $options.asciiScene) { $0.title }
                    chips("Detail", AsciiDetail.allCases, selection: $options.asciiDetail) { $0.title }
                    chips("Colours", AsciiColouring.allCases, selection: $options.asciiColours) { $0.title }
                    Text("Made from the playing song's cover, in your theme's colours or the cover's own. It moves only while the song plays. The Terminal look always shows it as ASCII art.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                preview
            }
        }
        .onHover { hovering = $0; if $0 { start = Date() } }
        // The tint applies to the artwork too, so it sits outside the ASCII card's switches.
        Toggle("Tint the Music page with the playing cover", isOn: $options.albumTint)
            .padding(.horizontal, 4)
    }

    private var preview: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 14, style: .continuous).fill(theme.notch.surface)
            if showsAscii {
                AsciiCover(artwork: nowPlaying.info.artwork ?? Self.sample, size: 150, style: options.asciiStyle,
                           scene: options.asciiScene, detail: options.asciiDetail,
                           position: { [start] in Date().timeIntervalSince(start) }, playing: hovering,
                           colouring: options.asciiColours)
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

    private func chips<Choice: Hashable & Identifiable>(_ title: String, _ choices: [Choice], selection: Binding<Choice>,
                                                       dims: Bool = true,
                                                       label: @escaping (Choice) -> String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            HStack(spacing: 5) {
                ForEach(choices) { choice in
                    Button { selection.wrappedValue = choice } label: {
                        Text(label(choice)).font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 10).frame(height: 24)
                    }
                    .buttonStyle(SettingsChipStyle(selected: selection.wrappedValue == choice))
                }
            }
        }
        .opacity(!dims || showsAscii ? 1 : 0.45)
        .allowsHitTesting(!dims || showsAscii)
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
