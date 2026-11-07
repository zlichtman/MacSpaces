import SwiftUI

/// Who appears on Wisp's page: Wisp's eyes, or KemoSabe, Tsukumo's companion, in the look picked
/// for it (`KemoSabeLook`, Settings → Tsukumo). Only the face and name change: the page, its chat,
/// its model and its settings stay the same.
enum WispCharacter: String, CaseIterable, Identifiable {
    case wisp, kemosabe

    var id: String { rawValue }
    var title: String { self == .wisp ? "Wisp" : "KemoSabe" }

    static var current: WispCharacter {
        UserDefaults.standard.string(forKey: WidgetOptions.Keys.wispCharacter).flatMap(WispCharacter.init) ?? .wisp
    }

    /// 3.95 offered glass KemoSabe as a character of its own; it's now one of KemoSabe's looks,
    /// so that choice becomes KemoSabe wearing glass: the same picture.
    static func migrateGlass(_ defaults: UserDefaults = .standard) {
        guard defaults.string(forKey: WidgetOptions.Keys.wispCharacter) == "glass" else { return }
        defaults.set(WispCharacter.kemosabe.rawValue, forKey: WidgetOptions.Keys.wispCharacter)
        if defaults.string(forKey: WidgetOptions.Keys.kemoSabeLook) == nil {
            defaults.set(KemoSabeLook.glass.id, forKey: WidgetOptions.Keys.kemoSabeLook)
        }
    }
}

/// KemoSabe on Wisp's page: its painted art in its look, breathing while it waits and looking
/// through its things while an answer comes. The glass look has no searching picture, so it
/// breathes faster instead. It stands still under Reduce Motion, and when `still` (the picker's
/// tiles, of which there are many).
struct KemoSabeFace: View {
    var mood: WispMood
    var size: CGFloat
    var look: KemoSabeLook = .apricot
    /// A smaller painted picture, quicker to make, for tiles.
    var small = false
    var still = false
    @ObservedObject private var theme = ThemeStore.shared
    /// Set when a repainted picture is ready, to draw it.
    @State private var painted = false

    private var searching: Bool { mood == .thinking && !look.isGlass }

    var body: some View {
        Group {
            if theme.reduceMotion || still {
                art(breath: 0)
            } else {
                TimelineView(.periodic(from: .now, by: 1.0 / 30)) { context in
                    art(breath: sin(context.date.timeIntervalSinceReferenceDate * (look.isGlass && mood == .thinking ? 4.5 : 1.9)))
                }
            }
        }
        .frame(width: size, height: size)
        .accessibilityLabel(mood == .thinking ? "KemoSabe, looking for an answer" : "KemoSabe")
        .task(id: "\(look.id)|\(searching)|\(small)") {
            guard look != .apricot, !look.isGlass else { return }
            painted = await KemoSabeArt.make(searching: searching, look: look, small: small)
        }
    }

    private func art(breath: Double) -> some View {
        picture.resizable().interpolation(.high).scaledToFit()
            .scaleEffect(x: 1 + 0.012 * breath, y: 1 - 0.018 * breath, anchor: .bottom)
    }

    /// The look's picture; Apricot's own while another is still being painted.
    private var picture: Image {
        let _ = painted
        if look.isGlass { return Image("KemoSabeGlass") }
        if look != .apricot, let image = KemoSabeArt.cached(searching: searching, look: look, small: small) {
            return Image(decorative: image, scale: 1)
        }
        return Image(searching ? "KemoSabeSearching" : "KemoSabe")
    }
}
