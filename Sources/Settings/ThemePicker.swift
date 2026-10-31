import SwiftUI
import AppKit

/// Settings → Appearance → Theme: three drawers, closed on entry. Terminal is one list
/// of our palettes and Ghostty's, every one the same colour pill, searchable and filtered
/// by Dark or Light; Live is the photographs and animated scenes, the whole pack at once,
/// marked with MacSpaces' icon; Custom builds your own. A drawer's contents are built only while it's open.
struct NookThemePicker: View {
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var library = GhosttyLibrary.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var open: Set<ThemeCollection> = NookThemePicker.initiallyOpen

    /// QA captures open drawers to review them.
    static var initiallyOpen: Set<ThemeCollection> = []
    static var startsFullyOpen: Bool {
        get { initiallyOpen == Set(ThemeCollection.allCases) }
        set { initiallyOpen = newValue ? Set(ThemeCollection.allCases) : [] }
    }
    #if DEBUG
    /// `theme-lag-legacy` draws 3.39's drawers (a SwiftUI grid of buttons for Terminal,
    /// scene cards that each observe the theme store, no photo warm-up) to compare.
    static var legacyViews = false
    /// `theme-lag` opens a drawer as a click would.
    static let qaToggle = Notification.Name("MacSpaces.QA.toggleThemeDrawer")
    #endif

    var body: some View {
        SettingsCard("Theme", systemImage: "paintpalette") {
            VStack(spacing: 0) {
                ForEach(ThemeCollection.allCases) { collection in
                    if collection != ThemeCollection.allCases.first { Divider() }
                    drawer(collection)
                }
            }
            .padding(.top, 4)
        }
        .onAppear {
            library.load()
            // The scenes' card photos decode off the main thread while the drawers are
            // still closed, so the scenes drawer opens with every photo in place.
            #if DEBUG
            if Self.legacyViews { return }
            #endif
            MotifThumbnails.shared.prepare(ThemeCollection.live.cardPhotos)
        }
        #if DEBUG
        .onReceive(NotificationCenter.default.publisher(for: Self.qaToggle)) { note in
            if let collection = note.object as? ThemeCollection { toggle(collection) }
        }
        #endif
    }

    /// A theme no drawer offers any more opens its drawer while it's the one in use, so
    /// nobody's theme disappears from Settings after an update.
    static func unlistedInUse(_ family: ThemeFamily, _ collection: ThemeCollection) -> [ThemeFamily] {
        !family.isOffered && family.collection == collection ? [family] : []
    }

    private func toggle(_ collection: ThemeCollection) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.22)) {
            if open.contains(collection) { open.remove(collection) } else { open.insert(collection) }
        }
    }

    private func drawer(_ collection: ThemeCollection) -> some View {
        let isOpen = open.contains(collection)
        let current: String? = {
            guard theme.family.collection == collection else { return nil }
            return theme.family == .custom ? "Using Custom, \(theme.customStyle.title.lowercased())" : "Using \(theme.family.title)"
        }()
        return VStack(alignment: .leading, spacing: 12) {
            Button {
                toggle(collection)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: collection.symbol)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 20)
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(spacing: 6) {
                            Text(collection.title).font(.system(size: 13, weight: .semibold))
                            if collection != .custom {
                                Text("\(collection.count)").font(.caption).foregroundStyle(.tertiary).monospacedDigit()
                            }
                        }
                        Text(current ?? collection.subtitle)
                            .font(.caption)
                            .foregroundStyle(current == nil ? AnyShapeStyle(.secondary) : AnyShapeStyle(theme.settings.accent))
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
                Group {
                    switch collection {
                    case .terminal: TerminalThemeList()
                    case .live: scenes
                    case .custom: CustomThemeEditor()
                    }
                }
                .padding(.bottom, 12)
                .transition(.opacity)
            }
        }
    }

    private static let sceneColumns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 5)

    /// Five to a row. Each card gets its selection and accent from here and observes nothing,
    /// so choosing a theme or any other Settings change redraws one picker, not 25 cards.
    @ViewBuilder private var scenes: some View {
        let families = Self.unlistedInUse(theme.family, .live) + ThemeCollection.live.families
        let current = theme.family, accent = theme.settings.accent
        LazyVGrid(columns: Self.sceneColumns, spacing: 14) {
            ForEach(families) { family in
                #if DEBUG
                if Self.legacyViews {
                    LegacyLiveThemeCard(family: family)
                } else {
                    LiveThemeCard(family: family, selected: family == current, accent: accent)
                }
                #else
                LiveThemeCard(family: family, selected: family == current, accent: accent)
                #endif
            }
        }
    }
}

/// The Terminal drawer: our palettes on top in their curated order, then Ghostty's library
/// in Ghostty's own order (alphabetical, so its families stay together), every one the same
/// compact row: a colour pill and the name, three to a line. Search and a Dark or Light
/// filter; an unlisted theme in use comes first. The list scrolls in its own frame, an
/// AppKit table (`TerminalThemeGrid`) that draws only the rows on screen and reuses them,
/// so 830 themes open, filter and scroll without SwiftUI laying out a grid.
struct TerminalThemeList: View {
    @ObservedObject private var library = GhosttyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = TerminalThemeList.initialQuery
    @State private var tone: GhosttyLibrary.Tone = TerminalThemeList.initialTone
    /// QA captures start with a search typed or a filter chosen.
    static var initialQuery = ""
    static var initialTone: GhosttyLibrary.Tone = .all
    #if DEBUG
    /// `themes-redesign` draws 3.37's swatch cards once to compare (`SwatchTerminalCard`).
    static var swatchPreview = false
    #endif

    /// The last list worked out, so a Settings update that changes nothing here (a theme
    /// chosen, a toggle elsewhere) doesn't search the library again.
    private static var cached: (key: String, items: [TerminalThemeItem])?

    private var items: [TerminalThemeItem] {
        let pinnedFamilies = NookThemePicker.unlistedInUse(theme.family, .terminal)
        let key = "\(query)|\(tone.rawValue)|\(library.themes.count)|\(pinnedFamilies.map(\.rawValue).joined())"
        if let cached = Self.cached, cached.key == key { return cached.items }
        let words = query.lowercased().split(separator: " ").map(String.init)
        // Our palettes are all dark.
        func matches(_ family: ThemeFamily) -> Bool { tone != .light && words.allSatisfy { family.title.lowercased().contains($0) } }
        let pinned = pinnedFamilies.filter(matches).map(TerminalThemeItem.own)
        let items = pinned + TerminalThemeItem.ordered(own: ThemeFamily.ownTerminal.filter(matches), ghostty: library.search(query, tone: tone))
        Self.cached = (key, items)
        return items
    }

    private var selectedID: String {
        if theme.family == .ghostty { return "ghostty." + (theme.ghosttyName ?? "") }
        return "own." + theme.family.rawValue
    }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsListSearchField("Search terminal themes", text: $query)
                Picker("", selection: $tone) {
                    ForEach(GhosttyLibrary.Tone.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 170)
            }
            list(items)
            .frame(height: 404)
            .overlay {
                if items.isEmpty && !library.themes.isEmpty {
                    Text("No themes match").font(.callout).foregroundStyle(.secondary)
                }
            }
            HStack {
                Text("\(items.count) themes").monospacedDigit()
                Spacer()
                Text("Ghostty's collection: iTerm2-Color-Schemes, MIT")
            }
            .font(.caption).foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder private func list(_ items: [TerminalThemeItem]) -> some View {
        #if DEBUG
        if Self.swatchPreview {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 14) {
                    ForEach(items) { item in SwatchTerminalCard(item: item) }
                }
                .padding(2)
            }
        } else if NookThemePicker.legacyViews {
            ScrollView { LegacyTerminalPills(items: items).padding(2) }
        } else {
            table(items)
        }
        #else
        table(items)
        #endif
    }

    private func table(_ items: [TerminalThemeItem]) -> some View {
        TerminalThemeGrid(items: items, ownPills: library.ownPills, filter: "\(query)|\(tone.rawValue)",
                          selectedID: selectedID, tint: NSColor(theme.settings.accent),
                          ink: NSColor(theme.settingsForeground), dark: colorScheme == .dark)
    }
}

/// A Live card: the scene's photo (a prebuilt 360-pixel copy) or its effect, still. Its
/// selection and accent are passed in, so a card observes nothing.
struct LiveThemeCard: View {
    let family: ThemeFamily
    let selected: Bool
    let accent: Color

    var body: some View {
        let palette = family.palette(.dark)
        return Button { ThemeStore.shared.selectFamily(family) } label: {
            VStack(alignment: .leading, spacing: 8) {
                SceneSwatch(family: family, palette: palette)
                    .frame(height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
                        selected ? accent : Color.primary.opacity(0.10), lineWidth: selected ? 2 : 1))
                HStack(spacing: 4) {
                    Text(family.title).font(.system(size: 12, weight: .medium))
                        .lineLimit(1).minimumScaleFactor(0.85)
                    Spacer(minLength: 0)
                    if selected { Image(systemName: "checkmark.circle.fill").foregroundStyle(accent) }
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(family.title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// A scene card: the theme's photo or effect, still.
struct SceneSwatch: View {
    let family: ThemeFamily
    let palette: FamilyPalette
    var body: some View {
        ZStack {
            palette.color(palette.background)
            if let motif = family.motif {
                ThemeMotifView(motif: motif, accent: palette.color(palette.accent),
                               ink: palette.color(palette.foreground), scale: 0.5, strength: 1.8,
                               softensCenter: false, thumbnail: true)
            }
            VStack {
                Spacer()
                HStack { Capsule().fill(palette.color(palette.accent)).frame(width: 18, height: 4); Spacer() }
            }
            .padding(.horizontal, 9).padding(.bottom, 11)
        }
    }
}

/// The Custom drawer: a live preview on the left; style, colours, glass and picture
/// controls on the right. Any change selects Custom.
struct CustomThemeEditor: View {
    @ObservedObject private var theme = ThemeStore.shared
    @State private var importing = false

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            CustomThemePreview()
                .frame(width: 270, height: 168)
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 6) {
                    ForEach(CustomThemeStyle.allCases) { style in styleButton(style) }
                }
                colours
                if theme.customStyle == .glass { glassControls }
                if theme.customStyle == .image { pictureControls }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func styleButton(_ style: CustomThemeStyle) -> some View {
        let on = theme.family == .custom && theme.customStyle == style
        return Button {
            theme.selectCustomStyle(style)
        } label: {
            VStack(spacing: 4) {
                Image(systemName: style.symbol).font(.system(size: 13))
                Text(style.title).font(.system(size: 11, weight: on ? .semibold : .medium))
            }
            .frame(maxWidth: .infinity).frame(height: 46)
        }
        .buttonStyle(SettingsChipStyle(selected: on))
        .accessibilityLabel(style.title)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    private var colours: some View {
        HStack(spacing: 16) {
            ColorPicker(theme.customStyle == .glass ? "Tint" : "Background",
                        selection: hexBinding(\.customThemeBackground), supportsOpacity: false)
                .fixedSize()  // never wraps ("Backgroun/d" beside three swatches); the spacer gives way
            if theme.customStyle == .twoTone {
                ColorPicker("Fades to", selection: hexBinding(\.customThemeSecond), supportsOpacity: false)
                    .fixedSize()
            }
            ColorPicker("Accent", selection: hexBinding(\.customThemeAccent), supportsOpacity: false)
                .fixedSize()
            Spacer(minLength: 0)
            resetButton
        }
        .font(.system(size: 12))
    }

    /// Returns the style on show to its default (Picture: to its picture's colours).
    private var resetButton: some View {
        let disabled = theme.customStyle == .image ? theme.customImageName == nil : theme.customStyleIsDefault
        return Button {
            theme.resetCustomStyle()
        } label: {
            Label("Reset", systemImage: "arrow.counterclockwise")
        }
        .buttonStyle(.settings(.quiet))
        .disabled(disabled)
        .help(theme.customStyle == .image ? "Take the colours from the picture again" : "Back to \(theme.customStyle.title)'s default look")
        .accessibilityLabel("Reset \(theme.customStyle.title)")
    }

    private var glassControls: some View {
        HStack(spacing: 10) {
            Text("Strength").font(.system(size: 12))
            Slider(value: Binding(get: { theme.customGlassStrength },
                                  set: { theme.customGlassStrength = $0; theme.selectFamily(.custom) }),
                   in: CustomTheme.strengthRange)
            Text(theme.customGlassStrength < 0.01 ? "Clear" : "\(Int((theme.customGlassStrength * 100).rounded()))%")
                .font(.system(size: 12)).monospacedDigit().foregroundStyle(.secondary).frame(width: 40, alignment: .trailing)
            Toggle("Blur", isOn: Binding(get: { theme.customGlassBlurs },
                                         set: { theme.customGlassBlurs = $0; theme.selectFamily(.custom) }))
                .toggleStyle(.checkbox).font(.system(size: 12))
        }
    }

    private var pictureControls: some View {
        HStack(spacing: 10) {
            Button(theme.customImageName == nil ? "Choose Picture" : "Change Picture") { choosePicture() }
                .buttonStyle(.settings(theme.customImageName == nil ? .primary : .secondary))
                .disabled(importing)
            if theme.customImageName != nil {
                Button("Remove Picture") { theme.removeCustomPicture() }
                    .buttonStyle(.settings(.destructive))
                    .disabled(importing)
            }
            if importing { ProgressView().controlSize(.small) }
            Text(theme.customImageName == nil ? "Colours come from your picture; change the accent any time."
                                              : "Background and accent come from your picture.")
                .font(.caption).foregroundStyle(.secondary).lineLimit(2)
        }
    }

    /// The picture is copied into Application Support from an explicit open panel, which
    /// grants access to that one file; nothing else is asked for.
    private func choosePicture() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.prompt = "Use Picture"
        SettingsWindowController.shared.runPanel(panel) { chosen in
            guard chosen, let url = panel.url else { return }
            importPicture(url)
        }
    }

    func importPicture(_ url: URL) {
        importing = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = CustomTheme.importImage(from: url)
            DispatchQueue.main.async {
                importing = false
                guard let result else { return }
                ThemeStore.shared.setCustomPicture(result.name, background: result.background, accent: result.accent)
            }
        }
    }

    private func hexBinding(_ key: ReferenceWritableKeyPath<ThemeStore, String>) -> Binding<Color> {
        Binding(
            get: { Color(themeHex: theme[keyPath: key]) ?? .gray },
            set: { color in
                guard let rgb = NSColor(color).usingColorSpace(.sRGB) else { return }
                theme[keyPath: key] = String(format: "%02X%02X%02X",
                    Int((rgb.redComponent * 255).rounded()), Int((rgb.greenComponent * 255).rounded()),
                    Int((rgb.blueComponent * 255).rounded()))
                if theme.family != .custom { theme.selectFamily(.custom) }
            })
    }
}

/// Custom as it looks in the Nook: its fill (or picture) over a stand-in desktop for Glass,
/// under the notch, and nothing else.
struct CustomThemePreview: View {
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var picture = CustomBackgroundImage.shared

    var body: some View {
        let palette = ThemeFamily.custom.palette(.dark)
        let ink = palette.color(palette.foreground)
        ZStack(alignment: .top) {
            if theme.customStyle == .glass {
                GlassPreviewDesktop(blur: theme.customGlassBlurs ? 9 : 0)
                palette.color(palette.background).opacity(theme.customGlassStrength)
                if theme.customGlassBlurs { GlassSheen(dark: CustomThemeColors.isDark(palette.background)) }
            } else {
                palette.color(palette.background)
                if theme.customStyle == .twoTone {
                    LinearGradient(colors: [Color(themeHex: theme.customThemeSecond) ?? .clear, .clear],
                                   startPoint: .topTrailing, endPoint: .bottomLeading)
                }
                if theme.customStyle == .image {
                    if let image = picture.image {
                        Image(decorative: image, scale: 1).resizable().aspectRatio(contentMode: .fill)
                            .opacity(0.62)
                    } else {
                        VStack(spacing: 6) {
                            Image(systemName: "photo").font(.system(size: 22))
                            Text("No picture yet").font(.caption)
                        }
                        .foregroundStyle(ink.opacity(0.6)).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
            UnevenRoundedRectangle(bottomLeadingRadius: 9, bottomTrailingRadius: 9)
                .fill(Color.black).frame(width: 92, height: 16)
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(Color.white.opacity(0.14)))
        .task(id: theme.customImageName) { picture.prepare() }
        .environment(\.colorScheme, .dark)
    }
}

/// A small, fixed stand-in for the desktop behind Glass previews, drawn in a Canvas so
/// its blur also shows in captures.
struct GlassPreviewDesktop: View {
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
