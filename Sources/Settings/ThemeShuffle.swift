import Foundation

/// Shuffle, the button beside the theme list's filters: while it's on, the Nook takes another
/// theme each time it closes, so it opens on a new one. It draws from the list as it was
/// filtered when Shuffle was last touched (Dark or Light, and the pack); a search isn't part of it.
enum ThemeShuffle {
    static let onKey = "theme.shuffle"
    private static let toneKey = "theme.shuffleTone"
    private static let packKey = "theme.shufflePack"

    static var isOn: Bool { UserDefaults.standard.bool(forKey: onKey) }
    static var tone: GhosttyLibrary.Tone {
        UserDefaults.standard.string(forKey: toneKey).flatMap(GhosttyLibrary.Tone.init(rawValue:)) ?? .all
    }
    static var pack: TerminalThemeList.PackFilter {
        UserDefaults.standard.string(forKey: packKey).flatMap(TerminalThemeList.PackFilter.init(rawValue:)) ?? .all
    }

    /// The filters Shuffle draws from, saved as they're chosen while it's on.
    static func remember(tone: GhosttyLibrary.Tone, pack: TerminalThemeList.PackFilter) {
        UserDefaults.standard.set(tone.rawValue, forKey: toneKey)
        UserDefaults.standard.set(pack.rawValue, forKey: packKey)
    }

    /// Any theme but the one in use, when there's another.
    static func pick<Generator: RandomNumberGenerator>(_ ids: [String], current: String?, using generator: inout Generator) -> String? {
        let others = ids.filter { $0 != current }
        return (others.isEmpty ? ids : others).randomElement(using: &generator)
    }

    /// The Nook has closed: the next theme. The library is read once, off the main thread, so
    /// until it's in a library pack has nothing to offer and the theme stays for this round.
    @MainActor static func next() {
        guard isOn else { return }
        let library = GhosttyLibrary.shared
        library.load()
        let items = TerminalThemeList.listed(query: "", tone: tone, pack: pack, library: library)
        var generator = SystemRandomNumberGenerator()
        let current = TerminalThemeList.selectedID(theme: .shared, library: library)
        guard let id = pick(items.map(\.id), current: current, using: &generator),
              let item = items.first(where: { $0.id == id }) else { return }
        library.use(item)
    }
}
