#if DEBUG
import AppKit

@MainActor
enum InteractionRegressionChecks {
    static func run() {
        precondition(SettingsDestination.allCases.map(\.rawValue) == ["general", "widgets", "appearance", "activities"])
        // Repeated widgets from hand-edited or corrupted profiles must not crash layout.
        precondition([NookWidgetKind.weather, .weather, .clock].fittedNookWidths(availableWidth: 600).count == 2)
        let repeated = #"{"id":"00000000-0000-0000-0000-000000000001","name":"Repeated","widgets":["weather","weather","clock","weather"]}"#
        let decoded = try! JSONDecoder().decode(NookProfile.self, from: Data(repeated.utf8))
        precondition(decoded.widgets == [.weather, .clock])
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
        let camera = NotchGeometry(width: 185, height: 32, isHardwareNotch: true)
        let regular = NotchViewModel.fittedSize(widgets: [.media, .timer, .clock, .mirror],
            tab: .nook, geometry: camera, availableWidth: 1440, showsLyrics: false)
        precondition(regular.height == 250 && regular.width <= 860)
        let lyrics = NotchViewModel.fittedSize(widgets: [.media, .timer, .clock, .mirror],
            tab: .nook, geometry: camera, availableWidth: 1440, showsLyrics: true)
        precondition(lyrics.height == regular.height + 46)
        let narrow = NotchViewModel.fittedSize(widgets: [.media],
            tab: .nook, geometry: camera, availableWidth: 500, showsLyrics: false)
        precondition(narrow.width == 452 && narrow.height == 281)
        let empty = NotchViewModel.fittedSize(widgets: [],
            tab: .nook, geometry: camera, availableWidth: 1440, showsLyrics: false)
        precondition(empty.height == 170)
        let tray = NotchViewModel.fittedSize(widgets: [],
            tab: .tray, geometry: camera, availableWidth: 1440, showsLyrics: true)
        precondition(tray == CGSize(width: empty.width, height: 250))
        print("Nook fill layout, widget persistence, sidebar and legacy style migration checks passed")
    }
}
#endif
