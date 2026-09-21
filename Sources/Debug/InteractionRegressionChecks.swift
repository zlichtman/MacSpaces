#if DEBUG
import AppKit

@MainActor
enum InteractionRegressionChecks {
    static func run() {
        precondition(SettingsDestination.allCases.map(\.rawValue) == ["general", "widgets", "appearance", "activities", "about"])
        for widgets: [NookWidgetKind] in [[.media], [.weather, .clock], [.media, .weather, .clock], [.media, .weather, .clock, .notes]] {
            for width: CGFloat in [420, 585, 740, 1100] {
                let columns = widgets.nookLayoutItems()
                let fitted = widgets.fittedNookWidths(availableWidth: width)
                let actual = columns.reduce(CGFloat.zero) { $0 + (fitted[$1.kinds[0]] ?? 0) } + CGFloat(columns.count - 1) * 10
                let natural = columns.reduce(CGFloat.zero) { $0 + $1.width } + CGFloat(columns.count - 1) * 10
                precondition(abs(actual - max(width, natural)) < 0.01)
                for column in columns where column.isStack { precondition(fitted[column.kinds[0]] == fitted[column.kinds[1]]) }
            }
        }
        for kind in [NookWidgetKind.weather, .clipboard, .pomodoro, .quickActions] {
            precondition(try! JSONDecoder().decode(NookWidgetKind.self, from: JSONEncoder().encode(kind)) == kind)
        }
        for legacy in ["studio", "glass", "terminal", "soft", "signal", "orbit", "mono", "frame"] {
            let data = Data("\"\(legacy)\"".utf8)
            precondition(try! JSONDecoder().decode(WidgetVisualStyle.self, from: data) == .studio)
        }
        precondition(WidgetVisualStyle.allCases == [.studio])
        print("Nook fill layout, widget persistence, sidebar and legacy style migration checks passed")
    }
}
#endif
