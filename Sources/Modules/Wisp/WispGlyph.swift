import SwiftUI

/// Wisp's icon in the dock and Settings: its two eyes alone, tall rounded shapes in the
/// surrounding foreground colour like an SF Symbol, with nothing round them.
struct WispGlyph: View {
    var size: CGFloat = 14

    var body: some View {
        HStack(spacing: size * 0.16) {
            eye
            eye
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }

    private var eye: some View {
        RoundedRectangle(cornerRadius: size * 0.13, style: .continuous)
            .frame(width: size * 0.3, height: size * 0.62)
    }
}
