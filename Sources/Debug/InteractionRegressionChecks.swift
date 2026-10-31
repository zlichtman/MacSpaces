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
        // Messages was removed in 3.21: a saved dock that lists it simply drops it.
        isolated.set(["music", "messages", "tray"], forKey: "dockApps")
        precondition(NookSettings(defaults: isolated).dockApps == [.music, .tray], "A retired page drops out of the saved dock")
        // ASCII album art: full brightness fills every braille dot and the densest characters; dark stays blank.
        precondition(AsciiArt.convert([Float](repeating: 1, count: 8), style: .braille, columns: 1, rows: 1, tick: 0).first?.dots == 0xFF)
        precondition(AsciiArt.convert([Float](repeating: 1, count: 8), style: .classic, columns: 1, rows: 1, tick: 0).first?.character == "@")
        precondition(AsciiArt.convert([Float](repeating: 0, count: 32), style: .braille, columns: 2, rows: 2, tick: 0).allSatisfy(\.isBlank))
        precondition(AsciiArt.contrast(0.03) == 0 && AsciiArt.contrast(1) == 1 && AsciiArt.beat(position: 0, tempo: 120) == 1)
        // Spotify backups: quoting, formula-safe fields and file names.
        precondition(SpotifyCSV.line(["A, B", "say \"hi\"", "=1+1", "plain"]) == "\"A, B\",\"say \"\"hi\"\"\",'=1+1,plain",
                     "CSV fields are quoted and never run as formulas")
        precondition(SpotifyCSV.fileName("AC/DC: live.") == "AC-DC- live" && SpotifyCSV.fileName(" .. ") == "Untitled", "Playlist file names are safe")
        let ranked = SpotifyLibrary.artists(fromSongs: [
            ["artists": [["name": "Fog Lake"]]], ["artists": [["name": "Blue"], ["name": "Fog Lake"]]], ["artists": [["name": "Blue"]]],
        ])
        precondition(ranked.map(\.name) == ["Fog Lake", "Blue"] && ranked[0].link?.absoluteString == "https://open.spotify.com/search/Fog%20Lake",
                     "Top artists rank from top songs when Spotify sends none")
        // Clear look: a song keeps its cover and sound around the camera; a timer sits outside the cover.
        precondition(ClearBubbles([.music]) == ClearBubbles([.music]) && ClearBubbles([.music]).left == [.activity(.music)]
                     && ClearBubbles([.music]).right == [.sound], "A song alone is cover and sound")
        let withTimer = ClearBubbles([.timer, .music])
        precondition(withTimer.left == [.activity(.timer), .activity(.music)] && withTimer.right == [.sound],
                     "A timer beside a song keeps the song's sound")
        precondition(ClearBubbles([.timer, .keepAwake]).left == [.activity(.timer)]
                     && ClearBubbles([.timer, .keepAwake]).right == [.activity(.keepAwake)], "Without a song, one each side")
        // Wisp is offered again but never added on its own: a new dock leaves it out, and adding it stays.
        precondition(NotchTab.appPages.contains(.wisp) && !NotchTab.defaultDock.contains(.wisp), "Wisp is offered, not in a new dock")
        isolated.set(["music", "tray"], forKey: "dockApps")
        NookSettings(defaults: isolated).setDockApp(.wisp, shown: true)
        precondition(NookSettings(defaults: isolated).dockApps == [.music, .tray, .wisp], "Wisp added to the dock stays")
        // The agent bubble shows while agents work only when chosen (before 3.30 it never did).
        isolated.removeObject(forKey: "agentActivity.peekWhileWorking")
        precondition(!AgentActivityMonitor(defaults: isolated).peekWhileWorking, "The bubble while working is off unless chosen")
        isolated.set(true, forKey: "agentActivity.peekWhileWorking")
        precondition(AgentActivityMonitor(defaults: isolated).peekWhileWorking, "A chosen bubble while working is kept")
        // Scenes draw only what a line is clearly about: one naming word, a headline, or a
        // word in no list that means the same thing on-device ("lilac", "snowstorm", "brandy").
        let sceneCases: [(String, LyricSubject)] = [
            ("Coins in my pocket and we're spending it all", .money), ("Lay your cards down on the table", .cards),
            ("Smoking cigarettes on the roof", .smoke), ("Folded paper planes that fly away", .plane),
            ("Dancing queen, young and sweet", .dance), ("Don't go breaking my heart", .heartbreak),
            ("Look into my eyes", .eyes), ("I'll bring you a bouquet tonight", .rose), ("Petals on the floor", .rose),
            ("Blizzard in my chest", .snow), ("The sun rose over the bay", .sun), ("Tick tock on the clock", .time),
            ("Sipping on that lean, a rebellious child(rebellious child)", .cup),
            ("Smoke hit my brain, I can feel it in my eyelids(yo-yo-yo-yo-yo", .smoke),
            ("Pull up in my whip", .drive), ("Counting racks", .money), ("Ice on my wrist", .diamond),
            ("Back in the hood", .city), ("In the club", .dance), ("Fresh kicks on my feet", .sneakers),
            ("Guitar beside the bed", .guitar), ("Take the mic", .microphone),
            ("A lilac by the door", .rose), ("Caught in the snowstorm", .snow), ("Pour me a brandy", .drink),
        ]
        for (line, subject) in sceneCases {
            precondition(LyricSubject.match(line) == subject, "\(line) → \(String(describing: LyricSubject.match(line)))")
        }
        // Common words alone draw nothing (better nothing than wrong), and a broken heart needs the words together.
        for line in ["I hold on", "Can you see me", "I lost my mind", "I rose above it all", "Call it love, love, love",
                     "Drive me crazy", "Running out of time", "Ring ring, it's me again", "Hold the evening light a little longer",
                     "Lean on me", "Bread and cheese in a bag", "Ice in the water", "Whip the cream",
                     "We started a book club", "Baby girl, shawty, stay with me", "I hold on (cash diamonds)",
                     "Chain me to the past", "Drip from the faucet", "She kicks me when I am down"] {
            precondition(LyricSubject.match(line) == nil, "\(line) → \(String(describing: LyricSubject.match(line)))")
        }
        precondition(LyricSubject.match("The broken window filled my heart with fear") != .heartbreak, "Broken and heart far apart")
        precondition(LyricSubject.match("My heart is broken") == .heartbreak)
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
        // So does a profile with the retired Messages widget, without changing Home's size.
        let retired = Data(#"{"id":"\#(UUID().uuidString)","name":"Old","widgets":["media","notifications","timer","clock","mirror"]}"#.utf8)
        let withoutMessages = try! JSONDecoder().decode(NookProfile.self, from: retired).widgets
        precondition(withoutMessages == [.media, .timer, .clock, .mirror], "A retired widget drops out of a saved profile")
        precondition(NotchViewModel.fittedSize(widgets: withoutMessages, tab: .nook, geometry: camera, availableWidth: 1440) == regular)
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
        // Lyric matching, LRC parsing and timing: Scripts/check-lyrics.sh.
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
