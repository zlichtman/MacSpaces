import SwiftUI
import AppKit

/// Settings → Appearance → Themes: one list of every theme, with one search (`TerminalThemeList`).
/// A saved Custom or retired theme keeps working and shows at the top of the list while in use.
struct NookThemePicker: View {
    @ObservedObject private var library = GhosttyLibrary.shared

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
        SettingsDrawerCard("Themes", systemImage: "paintpalette", openKey: WidgetOptions.Keys.themeDrawer, startsOpen: true) {
            TerminalThemeList()
                .padding(.top, 4)
        }
        .background(ThemeArrowKeys())
        .onAppear {
            library.load()
            // The scenes' card photos decode off the main thread while the drawers are
            // still closed, so the scenes drawer opens with every photo in place.
            #if DEBUG
            if Self.legacyViews { return }
            #endif
            MotifThumbnails.shared.prepare(ThemeCollection.live.cardPhotos)
        }
    }

    /// A theme no drawer offers any more opens its drawer while it's the one in use, so
    /// nobody's theme disappears from Settings after an update.
    static func unlistedInUse(_ family: ThemeFamily, _ collection: ThemeCollection) -> [ThemeFamily] {
        !family.isOffered && family.collection == collection ? [family] : []
    }
}

/// Every theme in one list, with one search: live scenes with pictures, those without, Editorial's
/// colours, then the Classics and the library with each theme's versions together (a search mixes them), every one
/// the same compact row, three to a line. Search and the Dark or Light and pack filters narrow it;
/// a saved Custom or retired theme in use comes first. It scrolls in its own frame, an AppKit table
/// (`TerminalThemeGrid`) that draws only the rows on screen, so 1,400 themes open, filter and
/// scroll without SwiftUI laying out a grid.
struct TerminalThemeList: View {
    @ObservedObject private var library = GhosttyLibrary.shared
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var thumbnails = MotifThumbnails.shared
    @Environment(\.colorScheme) private var colorScheme
    @State private var query = TerminalThemeList.initialQuery
    @State private var tone: GhosttyLibrary.Tone = TerminalThemeList.initialTone
    @State private var pack: PackFilter = TerminalThemeList.initialPack
    /// All packs, our own palettes, or one library pack.
    enum PackFilter: Hashable, CaseIterable {
        case all, editorial, classics, ghostty, base16, gogh

        var title: String {
            switch self {
            case .all: return "All Packs"
            case .editorial: return "Editorial"
            case .classics: return "Classics"
            case .ghostty: return GhosttyLibrary.Pack.ghostty.title
            case .base16: return GhosttyLibrary.Pack.base16.title
            case .gogh: return GhosttyLibrary.Pack.gogh.title
            }
        }

        var libraryPack: GhosttyLibrary.Pack? {
            switch self {
            case .ghostty: return .ghostty
            case .base16: return .base16
            case .gogh: return .gogh
            case .all, .editorial, .classics: return nil
            }
        }
    }

    /// QA captures start with a search typed or a filter chosen.
    static var initialQuery = ""
    static var initialTone: GhosttyLibrary.Tone = .all
    static var initialPack: PackFilter = .all
    #if DEBUG
    /// `themes-redesign` draws 3.37's swatch cards once to compare (`SwatchTerminalCard`).
    static var swatchPreview = false
    #endif

    /// The last list worked out, so a Settings update that changes nothing here (a theme
    /// chosen, a toggle elsewhere) doesn't search the library again.
    private static var cached: (key: String, items: [TerminalThemeItem])?

    private var items: [TerminalThemeItem] {
        let pinnedFamilies = theme.family == .custom ? [.custom] : NookThemePicker.unlistedInUse(theme.family, theme.family.collection)
        let key = "\(query)|\(tone.rawValue)|\(pack.title)|\(library.themes.count)|\(library.editRevision)|\(pinnedFamilies.map(\.rawValue).joined())"
        if let cached = Self.cached, cached.key == key { return cached.items }
        let words = query.lowercased().folding(options: .diacriticInsensitive, locale: nil).split(separator: " ").map(String.init)
        func matches(_ family: ThemeFamily) -> Bool {
            let live = family.collection == .live
            let title = family.title.lowercased().folding(options: .diacriticInsensitive, locale: nil) + (live ? " live scene" : "")
            let dark = TerminalThemeItem.own(family).isDark
            return (tone == .all || (tone == .dark) == dark) && words.allSatisfy { title.contains($0) }
        }
        func inPack(_ family: ThemeFamily) -> Bool {
            let classic = GhosttyThemes.originals[family] != nil
            switch pack {
            case .all: return true
            case .editorial: return !classic
            case .classics: return classic
            default: return false
            }
        }
        let pinned = pinnedFamilies.filter(matches).map(TerminalThemeItem.own)
        // Live scenes with pictures, then those without, then Editorial's colours, then the Classics.
        let terminal = ThemeFamily.ownTerminal, live = ThemeCollection.live.families
        let hasPicture = { (family: ThemeFamily) in TerminalThemeItem.own(family).photo != nil }
        let ordered = live.filter(hasPicture) + live.filter { !hasPicture($0) }
            + terminal.filter { GhosttyThemes.originals[$0] == nil } + terminal.filter { GhosttyThemes.originals[$0] != nil }
        let own = ordered.filter { inPack($0) && matches($0) }
        let others = pack == .editorial ? [] : library.search(query, tone: tone, pack: pack.libraryPack, classicsOnly: pack == .classics)
        let items = pinned + TerminalThemeItem.ordered(own: own, ghostty: others, searching: !words.isEmpty || pack == .classics)
        Self.cached = (key, items)
        return items
    }

    static func listHeight(_ count: Int) -> CGFloat {
        let rows = (count + TerminalThemeLayout.columns - 1) / TerminalThemeLayout.columns
        return min(404, max(60, CGFloat(rows) * TerminalThemeLayout.pitch + 2 * TerminalThemeLayout.edge))
    }

    private var selectedID: String {
        if theme.family == .ghostty {
            // A recoloured palette of ours runs as a theme under its own title.
            if let name = theme.ghosttyName, let own = ThemeFamily.ownTerminal.first(where: { $0.title == name }),
               library.isEdited(.own(own)) { return "own." + own.rawValue }
            return "ghostty." + library.shownName(theme.ghosttyName ?? "")
        }
        return "own." + theme.family.rawValue
    }

    var body: some View {
        let items = items
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                SettingsListSearchField("Search", text: $query) { ThemeArrowKeyRouter.shared.themeSearchHasFocus = $0 }
                SettingsSegmentedPicker("", selection: $tone, options: GhosttyLibrary.Tone.allCases, compact: true,
                                        symbol: { $0 == .dark ? "moon.fill" : $0 == .light ? "sun.max.fill" : nil }) { $0.title }
                    .fixedSize()
                SettingsSegmentedPicker("", selection: $pack, options: PackFilter.allCases, compact: true) { $0.title }
                    .fixedSize()
            }
            list(items)
            // As tall as the matches need, up to 404 pt: a narrow search leaves no empty
            // box pushing the rest of Settings down.
            .frame(height: Self.listHeight(items.count))
            .overlay {
                if items.isEmpty && !library.themes.isEmpty {
                    Text("No themes match").font(.callout).foregroundStyle(.secondary)
                }
            }
            Divider()
            if theme.family == .custom { CustomThemeColours() }
            // One line: the colours, then the look. A scene brings its own look.
            HStack(spacing: 16) {
                if let selected = library.item(id: selectedID) {
                    ThemeColourStrip(item: selected)
                }
                if theme.family.collection != .live {
                    ThemeLookPanel(custom: theme.family == .custom)
                }
                Spacer(minLength: 0)
            }
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
        TerminalThemeGrid(items: items, ownPills: library.ownPills, revision: library.editRevision + thumbnails.images.count, filter: "\(query)|\(tone.rawValue)|\(pack.title)", showsPack: pack == .all,
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

/// Custom's two colours, shown above the look while a saved Custom is in use.
struct CustomThemeColours: View {
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        HStack(spacing: 16) {
            ColorPicker("Background", selection: hexBinding(\.customThemeBackground), supportsOpacity: false)
                .fixedSize()  // never wraps; the spacer gives way
            ColorPicker("Accent", selection: hexBinding(\.customThemeAccent), supportsOpacity: false)
                .fixedSize()
            Spacer(minLength: 0)
        }
        .font(.system(size: 12))
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

/// The colours of the theme in use, above its look: click one to change it, and Reset takes
/// the theme back to how it came. A live scene shows its colours without changing them.
private struct ThemeColourStrip: View {
    let item: TerminalThemeItem
    @ObservedObject private var library = GhosttyLibrary.shared
    @State private var editing: ThemeColourSlot?

    var body: some View {
        if let current = library.current(item) {
            HStack(spacing: 5) {
                Text("Colours").font(.system(size: 12)).padding(.trailing, 3)
                ForEach(ThemeColourSlot.allCases) { slot in
                    Button { if library.isEditable(item) { editing = slot } } label: {
                        Circle().fill(Color(themeHex: slot.hex(in: current)) ?? .gray)
                            .overlay(Circle().strokeBorder(Color.primary.opacity(0.28), lineWidth: 1))
                            .frame(width: 16, height: 16)
                            .contentShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .help(slot.title)
                    .accessibilityLabel("\(slot.title) colour")
                    .popover(isPresented: Binding(get: { editing == slot }, set: { if !$0 { editing = nil } }), arrowEdge: .bottom) {
                        ThemeColourEditor(item: item, slot: slot)
                    }
                }
                if library.isEdited(item) {
                    Button { library.resetColours(item) } label: {
                        Image(systemName: "arrow.counterclockwise").font(.system(size: 11, weight: .semibold))
                            .frame(width: 18, height: 18).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Reset colours")
                    .accessibilityLabel("Reset colours")
                }
            }
            .fixedSize()
        }
    }
}

/// How a theme sits on the Nook, in one line: how much glass, blur, a fade to a second
/// colour and a picture. Terminal themes share these as you move between them.
struct ThemeLookPanel: View {
    let custom: Bool
    @ObservedObject private var theme = ThemeStore.shared
    @State private var importing = false
    @State private var editingFade = false

    private var look: ThemeLook { custom ? ThemeLook.custom : ThemeLook.terminal }

    private func binding<Value>(_ key: WritableKeyPath<ThemeLook, Value>) -> Binding<Value> {
        Binding(get: { look[keyPath: key] }, set: { value in theme.changeLook(custom: custom) { $0[keyPath: key] = value } })
    }

    private var hasPicture: Bool { look.picture && theme.customImageName != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                HStack(spacing: 6) {
                    Text("Glass")
                    Slider(value: binding(\.seeThrough), in: 0...1)
                        .controlSize(.mini)
                        .accessibilityLabel("Glass")
                        .frame(width: 64)
                    Text("\(Int((look.seeThrough * 100).rounded()))%")
                        .monospacedDigit().foregroundStyle(.secondary)
                        .frame(width: 30, alignment: .trailing)
                }
                LookDot(title: "Blur", isOn: binding(\.blur))
                    .disabled(look.seeThrough < 0.01)
                    .opacity(look.seeThrough < 0.01 ? 0.4 : 1)
                HStack(spacing: 6) {
                    LookDot(title: "Fade", isOn: binding(\.fade))
                    if look.fade { fadeSwatch }
                }
                HStack(spacing: 6) {
                    LookDot(title: "Picture", isOn: Binding(get: { hasPicture }, set: { on in
                        if on { choosePicture() } else { theme.changeLook(custom: custom) { $0.picture = false } }
                    }))
                    if hasPicture {
                        Button { choosePicture() } label: {
                            Image(systemName: "photo").font(.system(size: 11)).frame(width: 18, height: 18).contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Change picture")
                        .accessibilityLabel("Change picture")
                    }
                    if importing { ProgressView().controlSize(.small) }
                }
                .disabled(importing)
            }
            .font(.system(size: 12))
            if !custom, theme.activeLook == nil {
                Text("Shows on Terminal themes.").font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    /// The colour it fades to; opens the same wheel and hex field as a theme's dots.
    private var fadeSwatch: some View {
        Button { editingFade = true } label: {
            Circle().fill(Color(themeHex: look.second) ?? .gray)
                .overlay(Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1))
                .frame(width: 14, height: 14)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Fade colour")
        .popover(isPresented: $editingFade, arrowEdge: .bottom) {
            ThemeColourEditor(title: "Fades to", current: { look.second.trimmingCharacters(in: CharacterSet(charactersIn: "#")).uppercased() }, apply: { value in
                theme.changeLook(custom: custom) { $0.second = value }
            })
        }
    }

    /// A small round switch and its word, so the row reads as one line.
    private struct LookDot: View {
        let title: String
        @Binding var isOn: Bool
        @ObservedObject private var theme = ThemeStore.shared

        var body: some View {
            Button { isOn.toggle() } label: {
                HStack(spacing: 5) {
                    Circle()
                        .strokeBorder(isOn ? theme.settings.accent : Color.secondary, lineWidth: 1.5)
                        .background(Circle().fill(isOn ? theme.settings.accent : Color.clear).padding(3))
                        .frame(width: 12, height: 12)
                    Text(title).fixedSize()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isOn ? [.isSelected] : [])
            .accessibilityHint("Turns \(title) on or off")
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
                let store = ThemeStore.shared
                // Custom takes its colours from the picture; a Terminal theme keeps its own.
                if custom {
                    store.customThemeBackground = result.background
                    store.customThemeAccent = result.accent
                }
                store.customImageName = result.name
                store.changeLook(custom: custom) { $0.picture = true }
                CustomBackgroundImage.shared.prepare()
            }
        }
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
            let look = ThemeLook.custom
            if let tint = look.tint {
                GlassPreviewDesktop(blur: look.blurs ? 9 : 0)
                palette.color(palette.background).opacity(tint)
                if look.blurs { GlassSheen(dark: CustomThemeColors.isDark(palette.background)) }
            } else {
                palette.color(palette.background)
            }
            if look.fade {
                LinearGradient(colors: [Color(themeHex: look.second) ?? .clear, .clear],
                               startPoint: .topTrailing, endPoint: .bottomLeading)
            }
            if look.picture {
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

/// Arrow keys flip through the open drawer's themes, applying each at once, so you can look through
/// a lot of them quickly. Only in Settings' own window, and never while a text field has the keys.
/// Each open grid registers what a key does (`ThemeArrowTarget`); the drawer of the theme in use
/// wins when two are open.
@MainActor
final class ThemeArrowKeyRouter {
    static let shared = ThemeArrowKeyRouter()
    typealias Move = (GridMove.Direction) -> Bool
    private var targets: [ThemeCollection: Move] = [:]
    private var monitor: Any?
    weak var window: NSWindow?
    /// The Terminal list's search box has the keys: up or down leaves it for the results.
    var themeSearchHasFocus = false

    func set(_ move: Move?, for collection: ThemeCollection) { targets[collection] = move }

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            MainActor.assumeIsolated { ThemeArrowKeyRouter.shared.handle(event) ? nil : event }
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let window, event.window === window,
              event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else { return false }
        if window.firstResponder is NSText {
            // Any other text box keeps its keys, and left and right still move the caret here.
            guard themeSearchHasFocus, event.keyCode == 125 || event.keyCode == 126,
                  let move = targets[.terminal] else { return false }
            window.makeFirstResponder(nil)
            return move(event.keyCode == 125 ? .down : .up)
        }
        let direction: GridMove.Direction
        switch event.keyCode {
        case 123: direction = .left
        case 124: direction = .right
        case 125: direction = .down
        case 126: direction = .up
        default: return false
        }
        let current = ThemeStore.shared.family.collection
        guard let move = targets[current] ?? targets.values.first else { return false }
        return move(direction)
    }
}

/// Listens for the arrow keys while the theme picker is on screen.
private struct ThemeArrowKeys: NSViewRepresentable {
    final class Anchor: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let window {
                ThemeArrowKeyRouter.shared.window = window
                ThemeArrowKeyRouter.shared.start()
            } else {
                ThemeArrowKeyRouter.shared.stop()
            }
        }
    }

    func makeNSView(context: Context) -> Anchor { Anchor() }
    func updateNSView(_ view: Anchor, context: Context) {}
}

/// Registers a grid's arrow-key move while it's on screen, always the latest one.
struct ThemeArrowTarget: View {
    let collection: ThemeCollection
    let move: ThemeArrowKeyRouter.Move

    var body: some View {
        Color.clear
            .onAppear { ThemeArrowKeyRouter.shared.set(move, for: collection) }
            .onDisappear { ThemeArrowKeyRouter.shared.set(nil, for: collection) }
            .task(id: UUID()) { ThemeArrowKeyRouter.shared.set(move, for: collection) }
    }
}
