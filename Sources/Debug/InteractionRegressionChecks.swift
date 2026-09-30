#if DEBUG
import AppKit

@MainActor
enum InteractionRegressionChecks {
    static func run() {
        let suite = "dev.opensource.MacSpaces.StartupCheck." + UUID().uuidString
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let fresh = NookSettings(defaults: isolated)
        precondition(fresh.widgets == [.media, .timer, .clock, .mirror, .systemStats] && fresh.showTeleprompterBar)
        precondition(NookSettings(defaults: isolated).showTeleprompterBar, "Starter captions survive relaunch")
        fresh.widgets = []; fresh.showTeleprompterBar = false; fresh.flushPersistence()
        let existing = NookSettings(defaults: isolated)
        precondition(existing.widgets.isEmpty && !existing.showTeleprompterBar, "Do not overwrite an existing empty layout or caption preference")
        existing.resetToDefaults()
        precondition(existing.widgets == NookSettings.starterWidgets && existing.showTeleprompterBar)
        precondition(SettingsDestination.allCases.map(\.rawValue) == ["general", "widgets", "appearance", "permissions", "activities"])
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
        precondition(regular.height == 296 && regular.width <= 860)
        let lyrics = NotchViewModel.fittedSize(widgets: [.media, .timer, .clock, .mirror],
            tab: .nook, geometry: camera, availableWidth: 1440, showsLyrics: true)
        precondition(lyrics.height == regular.height + 46)
        let quickBars = NotchViewModel.fittedSize(widgets: [.media, .timer, .clock, .mirror, .notifications],
            tab: .nook, geometry: camera, availableWidth: 1440, showsLyrics: true)
        precondition(quickBars.width == regular.width && quickBars.height == lyrics.height + 46,
                     "Quick actions must be caption-height rows, not additional dashboard columns")
        let narrow = NotchViewModel.fittedSize(widgets: [.media],
            tab: .nook, geometry: camera, availableWidth: 500, showsLyrics: false)
        precondition(narrow.width == 452 && narrow.height == 296)
        let empty = NotchViewModel.fittedSize(widgets: [],
            tab: .nook, geometry: camera, availableWidth: 1440, showsLyrics: false)
        precondition(empty.height == 216)
        let tray = NotchViewModel.fittedSize(widgets: [],
            tab: .tray, geometry: camera, availableWidth: 1440, showsLyrics: true)
        precondition(tray == CGSize(width: empty.width, height: 296))
        for widgets: [NookWidgetKind] in [[.media], [.media, .timer, .weather], [.media, .weather, .clock, .notes]] {
            for available: CGFloat in [500, 1440] {
                let nookSize = NotchViewModel.fittedSize(widgets: widgets, tab: .nook, geometry: camera, availableWidth: available, showsLyrics: false)
                let traySize = NotchViewModel.fittedSize(widgets: widgets, tab: .tray, geometry: camera, availableWidth: available, showsLyrics: false)
                precondition(nookSize == traySize, "Tray must preserve the open Nook geometry")
            }
        }
        // Explicit sizes: adjacent smalls stack, a large widget widens, and
        // sizes persist per profile while unknown values fall back to defaults.
        let sized: [NookWidgetKind: NookWidgetSize] = [.media: .small, .calendar: .small, .weather: .large]
        let sizedColumns = [NookWidgetKind.media, .calendar, .weather].nookLayoutItems(sizes: sized)
        precondition(sizedColumns.count == 2 && sizedColumns[0].isStack && sizedColumns[1].width == 300)
        precondition(NookWidgetKind.mirror.resolvedSize(.small) == .medium, "Unsupported sizes fall back to the default")
        let sizeSuite = "dev.opensource.MacSpaces.SizeCheck." + UUID().uuidString
        let sizeDefaults = UserDefaults(suiteName: sizeSuite)!
        defer { sizeDefaults.removePersistentDomain(forName: sizeSuite) }
        let sizedSettings = NookSettings(defaults: sizeDefaults)
        sizedSettings.setSize(.large, for: .media)
        sizedSettings.setSize(.small, for: .timer)   // the default is not stored
        sizedSettings.flushPersistence()
        let reloaded = NookSettings(defaults: sizeDefaults)
        precondition(reloaded.size(for: .media) == .large && reloaded.activeProfile.widgetSizes == ["media": .large])
        let future = #"{"id":"00000000-0000-0000-0000-000000000002","name":"Future","widgets":["media"],"widgetSizes":{"media":"huge"}}"#
        precondition(try! JSONDecoder().decode(NookProfile.self, from: Data(future.utf8)).widgets == [.media],
                     "An unknown size must not discard the profile")
        print("Nook fill layout, widget sizes, widget persistence, sidebar and legacy style migration checks passed")
    }
}
#endif
