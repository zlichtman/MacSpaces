import SwiftUI

/// A Refresh control whose arrow turns once each time it's clicked, so the click
/// visibly does something even when the refresh itself is instant.
struct RefreshButton: View {
    var title: String?
    let action: () -> Void
    @State private var turns = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(_ title: String? = nil, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button {
            action()
            turns += 1
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.clockwise")
                    .symbolEffect(.rotate, options: .speed(1.4), value: reduceMotion ? 0 : turns)
                if let title { Text(title) }
            }
        }
        .accessibilityLabel(title ?? "Refresh")
    }
}
