import SwiftUI
import AppKit

/// Everyday Mac actions with labels, so each button says what it does.
struct QuickActionsWidget: View {
    var columns = 2
    /// Shows all six actions even in two columns (the Shortcuts page has the height).
    var showsAll = false

    private struct Action: Identifiable {
        let title: String
        let symbol: String
        let help: String
        let perform: @MainActor () -> Void
        var id: String { title }
    }

    private let actions: [Action] = [
        Action(title: "Appearance", symbol: "circle.lefthalf.filled", help: "Switch between light and dark mode") { QuickActions.toggleDarkMode() },
        Action(title: "Screenshot", symbol: "camera.viewfinder", help: "Capture a selection to the clipboard") { QuickActions.captureScreenSelection() },
        Action(title: "Lock", symbol: "lock.fill", help: "Lock the screen") { QuickActions.lockScreen() },
        Action(title: "Display off", symbol: "moon.fill", help: "Turn the displays off") { QuickActions.sleepDisplays() },
        Action(title: "Screen saver", symbol: "sparkles.tv", help: "Start the screen saver") { QuickActions.openScreenSaver() },
        Action(title: "Empty Trash", symbol: "trash", help: "Empty the Trash (asks first)") { QuickActions.emptyTrash() }
    ]

    var body: some View {
        let visible = columns >= 3 || showsAll ? actions : Array(actions.prefix(4))
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columns), spacing: 6) {
            ForEach(visible) { action in
                Button { action.perform() } label: {
                    VStack(spacing: 5) {
                        Image(systemName: action.symbol).font(.system(size: 14, weight: .medium))
                        Text(action.title).font(.system(size: 9, weight: .medium)).lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(Color.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .contentShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(PremiumPressButtonStyle())
                .help(action.help)
            }
        }
        .padding(.horizontal, 9)
        .padding(.bottom, 9)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
