import SwiftUI

/// The caption-height bar style shared by quick bars such as Messages.
private struct QuickActionBarStyle: ViewModifier {
    @ObservedObject private var theme = ThemeStore.shared
    func body(content: Content) -> some View {
        content.font(.system(size: 11)).buttonStyle(.borderless)
            .padding(.horizontal, 10).frame(maxWidth: .infinity).frame(height: 38)
            .foregroundStyle(theme.nookForeground).tint(theme.notch.accent)
            .background(theme.notch.control.opacity(0.92), in: RoundedRectangle(cornerRadius: 12))
    }
}
extension View {
    func quickActionBar() -> some View { modifier(QuickActionBarStyle()) }
}
