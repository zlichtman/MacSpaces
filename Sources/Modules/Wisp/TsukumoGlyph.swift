import SwiftUI

/// Tsukumo's mark, for the agents' page in the dock and Settings: one colour, from the surrounding
/// foreground, like an SF Symbol.
struct TsukumoGlyph: View {
    var size: CGFloat = 14

    var body: some View {
        Image("TsukumoMark").resizable().renderingMode(.template).interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }
}
