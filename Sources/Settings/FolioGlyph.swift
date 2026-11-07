import SwiftUI

/// Folio's mark: three rounded squares and a circle, in the surrounding foreground.
struct FolioGlyph: View {
    var size: CGFloat = 14

    var body: some View {
        let gap = size * 0.14, cell = (size - gap) / 2
        let square = RoundedRectangle(cornerRadius: cell * 0.24, style: .continuous)
        VStack(spacing: gap) {
            HStack(spacing: gap) {
                square.frame(width: cell, height: cell)
                Circle().frame(width: cell, height: cell)
            }
            HStack(spacing: gap) {
                square.frame(width: cell, height: cell)
                square.frame(width: cell, height: cell)
            }
        }
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}
