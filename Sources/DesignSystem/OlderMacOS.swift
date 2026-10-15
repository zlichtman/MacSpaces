import SwiftUI

/// Stand-ins for SwiftUI features newer than macOS 13, the oldest system
/// MacSpaces runs on. Each uses the newer API where it exists.
extension View {
    /// The arrow turns once per click: SF Symbols' rotate effect on macOS 15,
    /// an animated rotation before that.
    @ViewBuilder func refreshTurn(_ turns: Int, reduceMotion: Bool) -> some View {
        if #available(macOS 15.0, *) {
            symbolEffect(.rotate, options: .speed(1.4), value: reduceMotion ? 0 : turns)
        } else {
            rotationEffect(.degrees(reduceMotion ? 0 : Double(turns) * 360))
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.55), value: turns)
        }
    }

    /// Scroll content starts `top` points down but can scroll up under a title
    /// bar. Before macOS 14 the content is simply inset.
    @ViewBuilder func scrollContentTopMargin(_ top: CGFloat) -> some View {
        if #available(macOS 14.0, *) {
            contentMargins(.top, top, for: .scrollContent)
        } else {
            padding(.top, top)
        }
    }

    /// ↑ and ↓ in a text field (results, history) and optionally Escape. Before
    /// macOS 14 a text field keeps the arrow keys, so only Escape is handled there.
    @ViewBuilder func textFieldKeys(up: @escaping () -> Void, down: @escaping () -> Void,
                                    escape: (() -> Void)? = nil) -> some View {
        if #available(macOS 14.0, *) {
            onKeyPress(.downArrow) { down(); return .handled }
                .onKeyPress(.upArrow) { up(); return .handled }
                .onKeyPress(.escape) {
                    guard let escape else { return .ignored }
                    escape(); return .handled
                }
        } else if let escape {
            onExitCommand(perform: escape)
        } else {
            self
        }
    }
}

/// "No Results" for a search, as `ContentUnavailableView.search` draws it.
struct NoSearchResultsView: View {
    let text: String

    var body: some View {
        if #available(macOS 14.0, *) {
            ContentUnavailableView.search(text: text)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 34, weight: .regular))
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 4)
                Text("No Results for “\(text)”").font(.title3.weight(.semibold))
                Text("Check the spelling or try a new search.")
                    .font(.callout).foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 40)
        }
    }
}
