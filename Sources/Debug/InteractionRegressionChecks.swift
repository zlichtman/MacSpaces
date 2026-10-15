#if DEBUG
import AppKit

@MainActor
enum InteractionRegressionChecks {
    static func run() {
        // A saved place in this Mac's zone is the current place on the Map; others aren't.
        let here = TimeZone.current.identifier
        precondition(WidgetOptions.isCurrent(WidgetOptions.local) && WidgetOptions.isCurrent(here)
                     && WidgetOptions.isCurrent(WidgetOptions.namedPlace(zone: here, name: "Home", latitude: 0, longitude: 0)),
                     "A saved place in this time zone is the current place")
        let elsewhere = here == "Asia/Tokyo" ? "Europe/London" : "Asia/Tokyo"
        precondition(!WidgetOptions.isCurrent(elsewhere), "Other zones aren't the current place")
        let suite = "dev.opensource.MacSpaces.StartupCheck." + UUID().uuidString
        let isolated = UserDefaults(suiteName: suite)!
        defer { isolated.removePersistentDomain(forName: suite) }
        precondition(WidgetOptions.TemperatureUnit.preferred(in: Locale(identifier: "en_US")) == .fahrenheit)
        precondition(WidgetOptions.TemperatureUnit.preferred(in: Locale(identifier: "en_GB")) == .celsius)
        let systemUnit = WidgetOptions.TemperatureUnit.preferred()
        isolated.set(systemUnit == .celsius ? "fahrenheit" : "celsius", forKey: WidgetOptions.Keys.unit)
        precondition(WidgetOptions(defaults: isolated).temperatureUnit == systemUnit,
                     "Weather follows the system instead of a retired app preference")
        let fresh = NookSettings(defaults: isolated)
        precondition(fresh.showDockPin && fresh.showDockClose, "Existing installs keep both controls by default")
        precondition(fresh.dockPages.last == .nook && fresh.dockPages.filter { $0 == .nook }.count == 1, "Home is always one app page")
        fresh.showDockPin = false; fresh.showDockClose = false
        let dockReload = NookSettings(defaults: isolated)
        precondition(!dockReload.showDockPin && !dockReload.showDockClose, "Settings-only dock preference persists")
        fresh.widgets = []; fresh.flushPersistence()
        let existing = NookSettings(defaults: isolated)
        precondition(existing.widgets.isEmpty, "Do not overwrite an existing empty layout")
        precondition(existing.dockApps == fresh.dockApps, "The migrated dock persists")
        existing.setDockApp(.dictation, shown: false)
        precondition(!NookSettings(defaults: isolated).dockApps.contains(.dictation), "A removed communication page stays removed")
        existing.resetToDefaults()
        precondition(existing.widgets == NookSettings.starterWidgets)
        precondition(existing.showDockPin && existing.showDockClose, "Reset restores visible Pin and Close")
        isolated.set(["notes", "music"], forKey: "dockApps")
        isolated.removeObject(forKey: "dock.communicationPagesAdded")
        let customized = NookSettings(defaults: isolated)
        precondition(customized.dockApps == [.notes, .music, .meetings, .dictation], "Migration keeps the user's app order")
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
        // Profiles saved with the retired per-widget styles still open.
        let styled = Data(#"{"id":"\#(UUID().uuidString)","name":"Old","widgets":["clock"],"widgetStyles":{"clock":"orbit"}}"#.utf8)
        precondition(try! JSONDecoder().decode(NookProfile.self, from: styled).widgets == [.clock])
        let camera = NotchGeometry(width: 185, height: 32, isHardwareNotch: true)
        let regular = NotchViewModel.fittedSize(widgets: [.media, .timer, .clock, .mirror],
            tab: .nook, geometry: camera, availableWidth: 1440)
        let quickBars = NotchViewModel.fittedSize(widgets: [.media, .timer, .clock, .mirror, .notifications],
            tab: .nook, geometry: camera, availableWidth: 1440)
        precondition(quickBars.width == regular.width && quickBars.height > regular.height,
                     "Quick actions must be caption-height rows, not additional dashboard columns")
        for widgets: [NookWidgetKind] in [[.media], [.media, .timer, .weather], [.media, .weather, .clock, .notes]] {
            for available: CGFloat in [500, 1440] {
                let reference = NotchViewModel.fittedSize(widgets: widgets, tab: .weather, geometry: camera, availableWidth: available)
                for page in NotchTab.appPages {
                    let size = NotchViewModel.fittedSize(widgets: widgets, tab: page, geometry: camera, availableWidth: available)
                    precondition(size == reference, "Every app page shares Weather's geometry, independently of Home")
                }
            }
        }
        // Legacy size choices cannot change the new canonical Home presentation.
        for kind in NookWidgetKind.allCases {
            precondition(kind.supportedSizes == [kind.defaultSize])
            for legacy in NookWidgetSize.allCases { precondition(kind.resolvedSize(legacy) == kind.defaultSize) }
        }
        precondition(NookWidgetKind.media.defaultSize == .large && NookWidgetKind.clock.defaultSize == .small)
        let fixedColumns = [NookWidgetKind.media, .clock, .timer].nookLayoutItems(sizes: [.media: .small, .clock: .large])
        precondition(fixedColumns.count == 2 && fixedColumns[1].isStack, "Clock and timer retain their compact stack")
        let sizeSuite = "dev.opensource.MacSpaces.SizeCheck." + UUID().uuidString
        let sizeDefaults = UserDefaults(suiteName: sizeSuite)!
        defer { sizeDefaults.removePersistentDomain(forName: sizeSuite) }
        let sizedSettings = NookSettings(defaults: sizeDefaults)
        sizedSettings.setSize(.small, for: .media)
        sizedSettings.flushPersistence()
        let reloaded = NookSettings(defaults: sizeDefaults)
        precondition(reloaded.size(for: .media) == .large, "An unsupported legacy choice cannot shrink Music")
        let future = #"{"id":"00000000-0000-0000-0000-000000000002","name":"Future","widgets":["media"],"widgetSizes":{"media":"huge"}}"#
        precondition(try! JSONDecoder().decode(NookProfile.self, from: Data(future.utf8)).widgets == [.media],
                     "An unknown size must not discard the profile")
        let search = Data(#"[{"trackName":"Paul","artistName":"Big Thief","duration":184,"syncedLyrics":"[00:01.00]Fixture"},{"trackName":"Paul","artistName":"Big Thief","duration":null,"plainLyrics":"Fixture"},{"trackName":"Paul","artistName":"Big Thief","plainLyrics":"Fixture"},{"trackName":null,"artistName":"Big Thief","duration":184},{"trackName":"Another","artistName":"Artist","duration":200}]"#.utf8)
        let records = TeleprompterService.decodeLyricsRecords(search)
        precondition(records.count == 4 && records[0].duration == 184 && records[1].duration == nil && records[2].duration == nil && records[3].trackName == "Another", "Null or malformed results do not discard valid search matches")
        precondition(TeleprompterService.decodeLyricsRecords(Data(#"{"error":"unavailable"}"#.utf8)).isEmpty)
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
        precondition(TeleprompterService.score(title: "Maps", artist: "Yeah Yeah Yeahs", duration: 262, synced: true, hasLyrics: true,
                                               title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220) == nil, "Incompatible timed lyrics are rejected, even when alone")
        precondition(TeleprompterService.score(title: "Maps (feat. Yeah Yeah Yeahs)", artist: "Other Artist/Yeah Yeah Yeahs", duration: 220, synced: true, hasLyrics: true,
                                               title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220) == nil, "A featured artist cannot replace the lead artist")
        precondition(TeleprompterService.score(title: "Maps Again", artist: "Yeah Yeah Yeahs", duration: 220, synced: true, hasLyrics: true,
                                               title: "Maps", artist: "Yeah Yeah Yeahs", duration: 220) == nil, "A title prefix is not the same song")
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
        wheel.preview([URL(fileURLWithPath: "/tmp/sample.png")], tools: false, hovered: nil)
        let middle = ConverterWheel.diameter / 2, reach = (ConverterWheel.innerRadius + ConverterWheel.outerRadius) / 2
        if wheel.actions.count >= 4 {
            precondition(wheel.segment(at: NSPoint(x: middle, y: middle + reach)) == 0, "Above the centre is the first segment")
            let right = wheel.segment(at: NSPoint(x: middle + reach, y: middle)) ?? -1
            let left = wheel.segment(at: NSPoint(x: middle - reach, y: middle)) ?? -1
            precondition(0 < right && right < left, "Segments run clockwise from the top")
        }
        print("Nook fill layout, widget sizes, widget persistence, sidebar and legacy style migration checks passed")
    }
}
#endif
