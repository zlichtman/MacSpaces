import SwiftUI

struct QuickActionsWidget: View {
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 6) {
                actionButton("circle.lefthalf.filled", "Toggle dark mode") {
                    QuickActions.toggleDarkMode()
                }
                actionButton("camera.viewfinder", "Screenshot selection to clipboard") {
                    QuickActions.captureScreenSelection()
                }
            }
            HStack(spacing: 6) {
                actionButton("lock.fill", "Lock screen") {
                    QuickActions.lockScreen()
                }
                actionButton("trash", "Empty Trash") {
                    QuickActions.emptyTrash()
                }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func actionButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 13, weight: .medium))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.primary.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
