import SwiftUI
import AppKit

/// Quick emoji access: click any emoji to copy it; recently used float to the
/// front. The grid button opens the full system character palette.
struct EmojiWidget: View {
    @StateObject private var model = EmojiModel()
    @State private var showingGrid = false

    var body: some View {
        Button {
            showingGrid.toggle()
        } label: {
            VStack(spacing: 3) {
                HStack(spacing: 3) {
                    ForEach(model.recents.prefix(3), id: \.self) { emoji in
                        Text(emoji).font(.system(size: 14))
                    }
                }
                Text("Emoji")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingGrid, arrowEdge: .top) {
            grid
        }
    }

    private var grid: some View {
        VStack(spacing: 8) {
            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28)), count: 8), spacing: 4) {
                ForEach(model.displayed, id: \.self) { emoji in
                    Button {
                        model.copy(emoji)
                        showingGrid = false
                    } label: {
                        Text(emoji)
                            .font(.system(size: 18))
                            .frame(width: 26, height: 26)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Button("More… (Character Palette)") {
                NSApp.orderFrontCharacterPalette(nil)
                showingGrid = false
            }
            .controlSize(.small)
        }
        .padding(12)
    }
}

@MainActor
private final class EmojiModel: ObservableObject {
    @Published private(set) var recents: [String]

    private let defaultsKey = "recentEmojis"
    private let defaultSet = [
        "😀", "😂", "🥹", "😍", "😎", "🤔", "😅", "🙌",
        "👍", "👎", "👏", "🙏", "💪", "🔥", "✨", "🎉",
        "❤️", "💯", "🚀", "☕️", "🍕", "🐛", "✅", "❌",
    ]

    init() {
        recents = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? ["😀", "👍", "🔥"]
    }

    /// Recents first, then the default set (deduplicated).
    var displayed: [String] {
        var seen = Set<String>()
        return (recents + defaultSet).filter { seen.insert($0).inserted }
    }

    func copy(_ emoji: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(emoji, forType: .string)

        recents.removeAll { $0 == emoji }
        recents.insert(emoji, at: 0)
        if recents.count > 8 {
            recents.removeLast(recents.count - 8)
        }
        UserDefaults.standard.set(recents, forKey: defaultsKey)
    }
}
