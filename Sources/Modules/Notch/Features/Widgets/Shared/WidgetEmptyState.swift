import SwiftUI

/// Shared "icon over caption" placeholder shown when a widget has no content.
struct WidgetEmptyState: View {
    let systemImage: String
    let caption: String
    /// Point size for the symbol; nil keeps the environment's default font.
    var iconSize: CGFloat? = 16
    var captionSize: CGFloat = 9
    var tint: Color = .secondary

    var body: some View {
        VStack(spacing: 4) {
            if let iconSize {
                Image(systemName: systemImage)
                    .font(.system(size: iconSize))
            } else {
                Image(systemName: systemImage)
            }
            Text(caption)
                .font(.system(size: captionSize))
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(tint)
    }
}
