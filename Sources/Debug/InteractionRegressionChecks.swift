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
        // Lyrics: only this song, and timed lyrics only from a cut of the same length.
        let exact = TeleprompterService.score(title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220, synced: true, hasLyrics: true,
                                              title: "Maps", artist: "Yeah Yeah Yeahs", duration: 219.6)
        let otherCut = TeleprompterService.score(title: "Maps (Live)", artist: "Yeah Yeah Yeahs", duration: 262, synced: true, hasLyrics: true,
                                                 title: "Maps", artist: "Yeah Yeah Yeahs", duration: 219.6)
        precondition(exact != nil && otherCut.map { $0 < exact! } ?? true, "The same-length recording wins")
        precondition(TeleprompterService.score(title: "Mapping", artist: "Someone Else", duration: 220, synced: true, hasLyrics: true,
                                               title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220) == nil, "A different song is rejected")
        precondition(TeleprompterService.score(title: "Seasons - Remastered 2024", artist: "Suki Waterhouse", duration: 200, synced: false, hasLyrics: true,
                                               title: "Seasons", artist: "Suki Waterhouse, Friend", duration: 201) != nil, "Edition suffixes and features still match")
        let lrc = TeleprompterService.parseLRC("[offset:+500]\n[00:01.00]\n[00:10.00]First\n[00:20.00]\n[00:21.00]\n[00:30.00]Second")
        precondition(lrc.map(\.text) == ["First", TeleprompterService.rest, "Second"] && abs(lrc[0].start - 9.5) < 0.001,
                     "Breaks become one rest and the offset shifts lines")
        // Converter wheel: window coordinates have their origin at the bottom left.
        let wheel = ConverterWheel.shared
        wheel.preview([URL(fileURLWithPath: "/tmp/sample.png")], tools: false, hovered: nil, thumbnail: nil)
        let middle = ConverterWheel.diameter / 2, reach = (ConverterWheel.innerRadius + ConverterWheel.outerRadius) / 2
        if wheel.actions.count >= 4 {
            precondition(wheel.segment(at: NSPoint(x: middle, y: middle + reach)) == 0, "Above the centre is the first segment")
            precondition(wheel.segment(at: NSPoint(x: middle + reach, y: middle)) == wheel.actions.count / 4 || wheel.actions.count % 4 != 0,
                         "Segments run clockwise")
        }
        print("Nook fill layout, widget sizes, widget persistence, sidebar and legacy style migration checks passed")
    }
}
#endif
