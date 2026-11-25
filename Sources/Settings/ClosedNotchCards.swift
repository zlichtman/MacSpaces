import SwiftUI

/// Settings → Appearance → Closed Notch: how the Nook looks while closed: nothing around the
/// camera, each activity its own bubble. Here: the pill, and each bubble's shape.
struct ClosedNotchCard: View {
    @ObservedObject private var settings = NookSettings.shared
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        SettingsDrawerCard("Closed Notch", systemImage: "circle.dashed", openKey: WidgetOptions.Keys.closedNotchDrawer) {
            Text("Nothing drawn around the camera. Each activity is its own bubble beside it.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show a faint pill on external displays", isOn: $settings.notchlessHint)
                .help("Displays without a camera have nothing to point at to open the Nook. The pill marks the spot; off leaves the top of those displays clear.")
            Divider()
            // A table: a header that sets its whole column, then one row per bubble.
            HStack(spacing: 0) {
                Text("Bubbles").font(.system(size: 12, weight: .semibold)).frame(maxWidth: .infinity, alignment: .leading)
                ForEach(NotchBubbleShape.allCases, id: \.self) { shape in
                    Button(shape.title) { setAll(shape) }.buttonStyle(.settings(.secondary)).frame(width: Self.shapeColumn)
                }
                Button("Theme") { setAllFollow(!allFollow) }.buttonStyle(.settings(.secondary)).frame(width: Self.shapeColumn)
                    .help(allFollow ? "Give every bubble its own colour" : "Give every bubble the theme's colour")
            }
            ForEach(NotchPopOut.allCases) { popOut in
                HStack(spacing: 0) {
                    HStack(spacing: 10) {
                        NotchBubble(side: 24, ring: .clear, squircle: settings.isSquircle(popOut)) {
                            Image(systemName: popOut.symbol)
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(ThemeInks.bubbleColour(popOut, theme))
                        }
                        Text(popOut.title)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    ForEach(NotchBubbleShape.allCases, id: \.self) { shape in
                        shapeDot(popOut, shape).frame(width: Self.shapeColumn)
                    }
                    themeBox(isOn: settings.followsTheme(popOut)) { on in
                        if on { settings.popOutsFollowingTheme.insert(popOut.rawValue) } else { settings.popOutsFollowingTheme.remove(popOut.rawValue) }
                    }
                    .accessibilityLabel("\(popOut.title) follows the theme")
                    .frame(width: Self.shapeColumn)
                }
            }
            Text("Theme gives a bubble the theme's colour. Unticked, it keeps its own.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private static let shapeColumn: CGFloat = 92

    private var allFollow: Bool {
        NotchPopOut.allCases.allSatisfy(settings.followsTheme)
    }

    private func setAllFollow(_ on: Bool) {
        settings.popOutsFollowingTheme = on ? Set(NotchPopOut.allCases.map(\.rawValue)) : []
    }

    private func themeBox(isOn: Bool, set: @escaping (Bool) -> Void) -> some View {
        Toggle("", isOn: Binding(get: { isOn }, set: set)).labelsHidden().toggleStyle(.checkbox)
    }

    /// One shape's cell in a row: a round switch under its column's heading.
    private func shapeDot(_ popOut: NotchPopOut, _ shape: NotchBubbleShape) -> some View {
        let chosen = settings.shape(of: popOut) == shape
        return Button { settings.popOutShapes[popOut.rawValue] = shape.rawValue } label: {
            Circle()
                .strokeBorder(chosen ? theme.settings.accent : Color.secondary, lineWidth: 1.5)
                .background(Circle().fill(chosen ? theme.settings.accent : Color.clear).padding(3))
                .frame(width: 14, height: 14)
                .frame(width: Self.shapeColumn, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(popOut.title), \(shape.title)")
        .accessibilityAddTraits(chosen ? .isSelected : [])
    }

    private func setAll(_ shape: NotchBubbleShape) {
        settings.popOutShapes = Dictionary(uniqueKeysWithValues: NotchPopOut.allCases.map { ($0.rawValue, shape.rawValue) })
    }
}
