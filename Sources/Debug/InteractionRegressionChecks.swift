#if DEBUG
import AppKit

@MainActor
enum InteractionRegressionChecks {
    static func run() {
        let suite = "dev.opensource.MacSpaces.StartupCheck." + UUID().uuidString
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        let fresh = NookSettings(defaults: isolated)
        precondition(fresh.widgets == [.media, .timer, .clock])
        precondition(fresh.size(for: .media) == .large, "Fresh installs start with Music at full size")
        precondition(fresh.dockApps == [.music, .weather, .calendar, .system, .terminal, .tray, .timers, .mirror])
        fresh.widgets = []; fresh.flushPersistence()
        let existing = NookSettings(defaults: isolated)
        precondition(existing.widgets.isEmpty, "Do not overwrite an existing empty layout")
        precondition(existing.dockApps == NotchTab.legacyDock, "Installs that never changed the dock keep the one they had")
        existing.resetToDefaults()
        precondition(existing.widgets == NookSettings.starterWidgets)
        // Stickers follow the line's meaning: the headline, then concrete nouns, then common words.
        let stickerCases: [(String, LyricSticker)] = [
            ("Made you smile and look away", .smile), ("I took your picture", .camera),
            ("Under the streetlights", .streetlight), ("Don't go breaking my heart", .brokenHeart),
            ("Look into my eyes", .eyes), ("I love the city at night", .city), ("Smoking cigarettes on the roof", .smoke),
            ("Folded paper planes that fly away", .plane), ("We were only kids back then", .kid),
            ("I'll bring you a bouquet tonight", .flower), ("Petals on the floor", .flower),
            ("A toddler on the stairs", .kid),
        ]
        for (line, sticker) in stickerCases {
            precondition(LyricSticker.match(line) == sticker, "\(line) → \(String(describing: LyricSticker.match(line)))")
        }
        precondition(LyricSticker.allCases.allSatisfy { NSImage(systemSymbolName: $0.symbol, accessibilityDescription: nil) != nil },
                     "Every sticker's symbol exists")
        // Every widget can be added from the Add Widgets sheet, in a named group.
        precondition(Set(NookWidgetKind.libraryGroups.flatMap(\.1)) == Set(NookWidgetKind.allCases)
                     && !NookWidgetKind.libraryGroups.contains { $0.0 == "More" }, "A widget is missing from the Add Widgets groups")
        precondition(SettingsDestination.allCases.map(\.rawValue) == ["general", "widgets", "clipboard", "appearance", "permissions", "activities"])
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
            tab: .nook, geometry: camera, availableWidth: 1440)
        precondition(regular.height == 296 && regular.width <= 860)
        let quickBars = NotchViewModel.fittedSize(widgets: [.media, .timer, .clock, .mirror, .notifications],
            tab: .nook, geometry: camera, availableWidth: 1440)
        precondition(quickBars.width == regular.width && quickBars.height == regular.height + 46,
                     "Quick actions must be caption-height rows, not additional dashboard columns")
        let narrow = NotchViewModel.fittedSize(widgets: [.media],
            tab: .nook, geometry: camera, availableWidth: 500)
        precondition(narrow.width == 452 && narrow.height == 296)
        let empty = NotchViewModel.fittedSize(widgets: [],
            tab: .nook, geometry: camera, availableWidth: 1440)
        precondition(empty.height == 216)
        let tray = NotchViewModel.fittedSize(widgets: [],
            tab: .tray, geometry: camera, availableWidth: 1440)
        precondition(tray == CGSize(width: empty.width, height: 296))
        for widgets: [NookWidgetKind] in [[.media], [.media, .timer, .weather], [.media, .weather, .clock, .notes]] {
            for available: CGFloat in [500, 1440] {
                let nookSize = NotchViewModel.fittedSize(widgets: widgets, tab: .nook, geometry: camera, availableWidth: available)
                let traySize = NotchViewModel.fittedSize(widgets: widgets, tab: .tray, geometry: camera, availableWidth: available)
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
        // Other languages: the artist or title in another script or spelling still matches the right song.
        precondition(TeleprompterService.score(title: "Бумеранг", artist: "Vtoroi Ka", duration: 149, synced: false, hasLyrics: true,
                                               title: "Бумеранг", artist: "Второй Ка", duration: 149) != nil, "Cyrillic artist matches its Latin spelling")
        precondition(TeleprompterService.score(title: "Bumerang", artist: "Второй Ка", duration: 149, synced: false, hasLyrics: true,
                                               title: "Бумеранг", artist: "Второй Ка", duration: 149) != nil, "A transliterated title matches")
        precondition(TeleprompterService.score(title: "Titi Me Pregunto", artist: "Bad Bunny", duration: 243, synced: true, hasLyrics: true,
                                               title: "Tití Me Preguntó", artist: "Bad Bunny", duration: 243) != nil, "Accents don't matter")
        precondition(TeleprompterService.score(title: "Бумеранг", artist: "Слава", duration: 193, synced: true, hasLyrics: true,
                                               title: "Бумеранг", artist: "Второй Ка", duration: 149) == nil, "Another artist's song of the same name is rejected")
        // Blanked-out words in LRCLIB lines come back from the full lyrics; real dashes stay.
        let full = "The weather ain't been bad If you're into masochistic bullshit It's bullshit, all of it I said no".split(separator: " ").map(String.init)
        precondition(TeleprompterService.uncensor("The weather ain't been bad if you're into masochistic -", using: full)
                     == "The weather ain't been bad if you're into masochistic bullshit")
        precondition(TeleprompterService.uncensor("It's b******t, all of it", using: full) == "It's bullshit, all of it")
        precondition(TeleprompterService.uncensor("I said - no", using: full) == "I said - no", "A dash used as punctuation stays")
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
