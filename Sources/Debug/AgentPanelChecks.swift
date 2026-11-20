import SwiftUI

#if DEBUG
/// Check renders for the Agent card's theme list, KemoSabe's glass and motion and Wisp in glass
/// (`MACSPACES_DEMO_KIND=tools`, stopping here with `MACSPACES_DEMO_ONLY=agent`). Never published.
/// The original glass art to compare with comes from `MACSPACES_KEMOSABE_REFERENCE` (a folder
/// holding KemoSabeGlass.png), so it's never committed.
extension WebsiteDemoClips {
    static func agentPanelChecks(shoot: (AnyView, NSSize, String) -> Void) async {
        let theme = ThemeStore.shared
        let defaults = UserDefaults.standard
        let keys = [WidgetOptions.Keys.wispCharacter, WidgetOptions.Keys.agentPalette, WidgetOptions.Keys.agentThemeColours,
                    WidgetOptions.Keys.agentGlass, WidgetOptions.Keys.agentGlassLevel, WidgetOptions.Keys.agentCustomBody,
                    WidgetOptions.Keys.agentCustomFace, WidgetOptions.Keys.kemoSabeLook, WidgetOptions.Keys.agentColoursDrawer]
        let savedFamily = theme.family
        let library = GhosttyLibrary.shared
        library.load()
        for _ in 0..<100 where library.themes.isEmpty { try? await Task.sleep(nanoseconds: 100_000_000) }
        MotifThumbnails.shared.prepare(ThemeCollection.live.cardPhotos)

        // The themes the renders show, and their agent colours.
        func ghostty(_ name: String) -> TerminalThemeItem? { library.theme(named: name).map(TerminalThemeItem.ghostty) }
        let picks: [TerminalThemeItem] = [.own(.macspaces), .own(.tokyoNight), .own(.everforest), .own(.matchaLatte), .own(.ink),
                                          .own(.paper), .own(.blossom), .own(.starlight), .own(.synthwave)]
            + ["Catppuccin Latte", "iTerm2 Solarized Light", "Dracula", "GitHub Light Default", "Gruvbox Dark"].compactMap(ghostty)
        let palettes = picks.map { AgentColours.palette(for: $0) }
        let levels: [Double] = [0, 0.25, 0.5, 0.75, 1]
        var looks: [KemoSabeLook] = []
        for palette in palettes { looks.append(KemoSabeLook(palette)) }
        for palette in [AgentPalette.apricot, AgentPalette.named("lavender"), palettes[1], palettes[5]] {
            for level in levels { looks.append(KemoSabeLook(palette, glass: level)) }
        }
        for look in looks {
            _ = await KemoSabeArt.make(.felt, look: look, small: false)
            _ = await KemoSabeArt.make(.glass, look: look, small: false)
        }

        func label(_ text: String) -> some View {
            Text(text).font(.system(size: 10, weight: .medium, design: .rounded)).foregroundStyle(.secondary).lineLimit(1)
        }

        // Each theme's agent colours, KemoSabe and Wisp, on a dark Nook (Noir) and a light one (Paper).
        for (name, family) in [("dark", ThemeFamily.macspaces), ("light", .paper)] {
            theme.selectFamily(family)
            let sheet = VStack(alignment: .leading, spacing: 6) {
                ForEach(0..<picks.count, id: \.self) { index in
                    let palette = palettes[index]
                    HStack(spacing: 10) {
                        label("\(picks[index].title)  \(palette.body) \(palette.accent) \(palette.eye ?? "")").frame(width: 250, alignment: .leading)
                        KemoSabeFace(mood: .idle, size: 64, look: KemoSabeLook(palette), at: 0.5)
                        WispFaceArt(pose: WispPose(mood: .idle), size: 40,
                                    style: .current(theme, tint: KemoSabeRGB(hex: palette.eye ?? palette.accent)))
                            .frame(width: 70)
                        WispFaceArt(pose: WispPose(mood: .idle), size: 40,
                                    style: .current(theme, tint: KemoSabeRGB(hex: palette.eye ?? palette.accent), glass: 1))
                            .frame(width: 70)
                    }
                }
            }
            .padding(14).background(theme.notch.surface)
            shoot(AnyView(sheet), NSSize(width: 560, height: CGFloat(picks.count) * 70 + 28), "check-agent-themes-\(name)")
        }

        // KemoSabe at 0, 25, 50, 75 and 100% glass in four colours, on a dark Nook and a light one,
        // with the original glass art at the end of each row at the same size.
        let referenceFolder = ProcessInfo.processInfo.environment["MACSPACES_KEMOSABE_REFERENCE"]
        let reference: NSImage? = referenceFolder.flatMap { NSImage(contentsOfFile: $0 + "/KemoSabeGlass.png") }
        let side: CGFloat = 132
        for (name, family) in [("dark", ThemeFamily.macspaces), ("light", .paper)] {
            theme.selectFamily(family)
            let sheet = VStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { row in
                    HStack(spacing: 6) {
                        ForEach(0..<levels.count, id: \.self) { column in
                            KemoSabeFace(mood: .idle, size: side, look: looks[palettes.count + row * levels.count + column], at: 0.5)
                        }
                        if let reference {
                            Image(nsImage: reference).resizable().interpolation(.high).frame(width: side, height: side)
                        } else {
                            label("no reference").frame(width: side, height: side)
                        }
                    }
                }
            }
            .padding(12).background(theme.notch.surface)
            shoot(AnyView(sheet), NSSize(width: 6 * (side + 6) + 24, height: 4 * (side + 4) + 24), "check-agent-glass-\(name)")
        }

        // Every mood at a telling moment of its motion, felt and half glass, and a blink.
        theme.selectFamily(.macspaces)
        let moods: [WispMood] = [.idle, .listening, .thinking, .speaking, .happy, .celebrating, .surprised, .sleepy, .confused, .love]
        func moment(_ mood: WispMood) -> Double {
            var best = 0.0, score = -1.0
            for step in 0..<2000 {
                let t = Double(step) * 0.01
                let m = KemoSabeMotion.at(t, mood: mood)
                let s = Double(m.lift) * 10 + abs(m.tilt) / 10 + abs(Double(m.squashY) - 1) * 5 - Double(m.lid) * (mood == .sleepy ? 0 : 2)
                if s > score { score = s; best = t }
            }
            return best
        }
        var blinkAt = 0.0
        for step in 0..<4000 where KemoSabeMotion.at(Double(step) * 0.01, mood: .idle).lid > 0.97 { blinkAt = Double(step) * 0.01; break }
        var halfAt = 0.0
        for step in 0..<4000 {
            let lid = KemoSabeMotion.at(Double(step) * 0.01, mood: .idle).lid
            if lid > 0.45 && lid < 0.6 { halfAt = Double(step) * 0.01; break }
        }
        let lavender = AgentPalette.named("lavender")
        _ = await KemoSabeArt.make(.felt, look: KemoSabeLook(lavender), small: false)
        _ = await KemoSabeArt.make(.glass, look: KemoSabeLook(lavender), small: false)
        _ = await KemoSabeArt.makeBlend(look: KemoSabeLook(lavender, glass: 0.5), small: false)
        _ = await KemoSabeArt.make(.glass, look: .apricot, small: false)
        let moodSheet = VStack(alignment: .leading, spacing: 8) {
            ForEach([0.0, 0.5, 1.0], id: \.self) { level in
                HStack(spacing: 4) {
                    ForEach(0..<moods.count, id: \.self) { index in
                        VStack(spacing: 2) {
                            KemoSabeFace(mood: moods[index], size: 80, look: KemoSabeLook(lavender, glass: level), at: moment(moods[index]))
                            label(String(describing: moods[index]))
                        }
                    }
                }
            }
            HStack(spacing: 4) {
                ForEach([(halfAt, "half shut"), (blinkAt, "blink"), (0.5, "open")], id: \.1) { item in
                    VStack(spacing: 2) {
                        KemoSabeFace(mood: .idle, size: 120, look: .apricot, at: item.0)
                        label(item.1)
                    }
                }
                ForEach([(halfAt, "glass half shut"), (blinkAt, "glass blink")], id: \.1) { item in
                    VStack(spacing: 2) {
                        KemoSabeFace(mood: .idle, size: 120, look: KemoSabeLook(.apricot, glass: 1), at: item.0)
                        label(item.1)
                    }
                }
                ForEach([(0.0, "still sleepy"), (1.0, "still confused")], id: \.1) { item in
                    VStack(spacing: 2) {
                        KemoSabeFace(mood: item.0 == 0 ? .sleepy : .confused, size: 120, look: KemoSabeLook(.apricot, glass: 1), still: true)
                        label(item.1)
                    }
                }
            }
        }
        .padding(12).background(theme.notch.surface)
        shoot(AnyView(moodSheet), NSSize(width: 10 * 84 + 24, height: 3 * 100 + 150 + 48), "check-agent-moods")

        // Wisp in glass: 0, 50 and 100% in Automatic and two themes, on a dark Nook and a light one.
        for (name, family) in [("dark", ThemeFamily.macspaces), ("light", .paper)] {
            theme.selectFamily(family)
            let tints: [KemoSabeRGB?] = [nil, KemoSabeRGB(hex: palettes[1].eye ?? palettes[1].accent), KemoSabeRGB(hex: palettes[6].eye ?? palettes[6].accent)]
            let sheet = VStack(spacing: 6) {
                ForEach(0..<tints.count, id: \.self) { row in
                    HStack(spacing: 10) {
                        ForEach([0.0, 0.5, 1.0], id: \.self) { level in
                            WispFaceArt(pose: WispPose(mood: row == 2 ? .love : .idle), size: 56, style: .current(theme, tint: tints[row], glass: level))
                                .frame(width: 100, height: 80)
                        }
                    }
                }
            }
            .padding(12).background(theme.notch.surface)
            shoot(AnyView(sheet), NSSize(width: 3 * 110 + 24, height: 3 * 86 + 24), "check-agent-wisp-glass-\(name)")
        }

        // The Agent card with its theme list: Wisp in Tokyo Night, then KemoSabe in Matcha at 40% glass.
        theme.selectFamily(.macspaces)
        defaults.set(true, forKey: WidgetOptions.Keys.agentColoursDrawer)
        defaults.set(WispCharacter.wisp.rawValue, forKey: WidgetOptions.Keys.wispCharacter)
        AgentColours.choose(TerminalThemeItem.own(.tokyoNight))
        func card(_ name: String, _ family: ThemeFamily) {
            theme.selectFamily(family)
            let view = AgentSettingsCard(character: .constant(WispCharacter.current))
                .padding(20).frame(width: 720).background(theme.settings.surface)
            shoot(AnyView(view), NSSize(width: 720, height: 820), name)
        }
        card("check-agent-panel-wisp", .macspaces)
        defaults.set(WispCharacter.kemosabe.rawValue, forKey: WidgetOptions.Keys.wispCharacter)
        AgentColours.choose(TerminalThemeItem.own(.matchaLatte))
        AgentColours.setGlass(0.4)
        _ = await KemoSabeArt.make(.felt, look: AgentColours.currentKemoSabe(), small: false)
        _ = await KemoSabeArt.make(.glass, look: AgentColours.currentKemoSabe(), small: false)
        card("check-agent-panel-kemosabe", .everforest)
        if let solarized = ghostty("iTerm2 Solarized Light") {
            AgentColours.choose(solarized)
            AgentColours.setGlass(0)
            _ = await KemoSabeArt.make(.felt, look: AgentColours.currentKemoSabe(), small: false)
            card("check-agent-panel-kemosabe-solarized", .paper)
        }
        // Automatic, the agent's own colours (an existing install's unset palette): KemoSabe as drawn,
        // the header saying Original and no row picked, since the list has none for it; then Noir,
        // what a new install starts on; then Custom, with no row picked and the wells saying so.
        defaults.set(WispCharacter.kemosabe.rawValue, forKey: WidgetOptions.Keys.wispCharacter)
        AgentColours.choose(AgentPalette.automatic)
        AgentColours.setGlass(1)
        _ = await KemoSabeArt.make(.glass, look: AgentColours.currentKemoSabe(), small: false)
        TerminalThemeList.initialAgentPack = .editorial
        card("check-agent-panel-original", .macspaces)
        TerminalThemeList.initialAgentPack = .all
        AgentColours.choose(TerminalThemeItem.own(.macspaces))
        _ = await KemoSabeArt.make(.glass, look: AgentColours.currentKemoSabe(), small: false)
        card("check-agent-panel-noir", .macspaces)
        // Glass KemoSabe's card in the Midnight and Everforest scenes, its glow in each palette's colours.
        for (id, family) in [("midnight", ThemeFamily.midnight), ("everforest", .everforest)] {
            AgentColours.choose(TerminalThemeItem.own(family))
            _ = await KemoSabeArt.make(.glass, look: AgentColours.currentKemoSabe(), small: false)
            card("check-agent-panel-glass-\(id)", family)
        }
        defaults.set("8FB9E8", forKey: WidgetOptions.Keys.agentCustomBody)
        defaults.set("2B4A7A", forKey: WidgetOptions.Keys.agentCustomFace)
        AgentColours.choose(AgentPalette.custom)
        _ = await KemoSabeArt.make(.glass, look: AgentColours.currentKemoSabe(), small: false)
        card("check-agent-panel-custom", .macspaces)

        // The arrow keys in the Agent card's list: from Noir, right, left, left and down, each one
        // colouring the agent and leaving the Nook's theme as it is.
        TerminalThemeList.initialAgentPack = .editorial
        AgentColours.choose(TerminalThemeItem.own(.macspaces))
        theme.selectFamily(.macspaces)
        let keyWindow = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 720, height: 820), styleMask: [.borderless], backing: .buffered, defer: false)
        keyWindow.isReleasedWhenClosed = false
        keyWindow.contentView = NSHostingView(rootView: AgentSettingsCard(character: .constant(.kemosabe)).padding(20)
            .frame(width: 720, height: 820).background(theme.settings.surface))
        keyWindow.orderFrontRegardless()
        RunLoop.main.run(until: Date().addingTimeInterval(1.5))
        var keyLog: [String] = ["start: \(defaults.string(forKey: WidgetOptions.Keys.agentPalette) ?? "unset"), Nook \(theme.family.rawValue)"]
        for (code, name) in [(UInt16(124), "right"), (123, "left"), (123, "left"), (125, "down")] {
            if let event = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                            windowNumber: keyWindow.windowNumber, context: nil, characters: "", charactersIgnoringModifiers: "",
                                            isARepeat: false, keyCode: code) {
                NSApp.sendEvent(event)
            }
            RunLoop.main.run(until: Date().addingTimeInterval(0.4))
            keyLog.append("\(name): \(defaults.string(forKey: WidgetOptions.Keys.agentPalette) ?? "unset"), Nook \(theme.family.rawValue)")
        }
        keyWindow.orderOut(nil)
        keyWindow.contentView = nil
        TerminalThemeList.initialAgentPack = .all
        if let folder = ProcessInfo.processInfo.environment["MACSPACES_DEMO_OUTPUT"] {
            try? keyLog.joined(separator: "\n").write(toFile: folder + "/check-agent-keys.txt", atomically: true, encoding: .utf8)
        }
        for key in keys { defaults.removeObject(forKey: key) }

        // CPU with each face live in a small window off the visible screen, 6 s each (a rough local
        // look; Feature QA's wisp scope measures on screen).
        var report: [String] = []
        let apricotHalf = KemoSabeLook(.apricot, glass: 0.5)
        _ = await KemoSabeArt.make(.felt, look: .apricot, small: false)
        _ = await KemoSabeArt.make(.glass, look: apricotHalf, small: false)
        _ = await KemoSabeArt.make(.felt, look: apricotHalf, small: false)
        let cases: [(String, AnyView)] = [
            ("nothing", AnyView(Color.clear)),
            ("Wisp idle", AnyView(WispFace(mood: .idle, size: 80))),
            ("3.99's KemoSabe (one picture breathing at 30 fps)", AnyView(TimelineView(.periodic(from: .now, by: 1.0 / 30)) { context in
                Image(decorative: KemoSabeArt.original()!, scale: 1).resizable().interpolation(.high).frame(width: 92, height: 92)
                    .scaleEffect(x: 1 + 0.012 * sin(context.date.timeIntervalSinceReferenceDate * 1.9),
                                 y: 1 - 0.018 * sin(context.date.timeIntervalSinceReferenceDate * 1.9), anchor: .bottom)
            })),
            ("KemoSabe idle", AnyView(KemoSabeFace(mood: .idle, size: 92))),
            ("KemoSabe happy", AnyView(KemoSabeFace(mood: .happy, size: 92))),
            ("KemoSabe idle, half glass", AnyView(KemoSabeFace(mood: .idle, size: 92, look: apricotHalf))),
        ]
        theme.setPreviewSystemReduceMotion(false)
        for (name, view) in cases {
            let window = NSWindow(contentRect: NSRect(x: -20000, y: -20000, width: 200, height: 160), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: view.frame(width: 200, height: 160).background(theme.notch.surface))
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(1.5))
            let start = FeatureQAHarness.cpuSeconds()
            RunLoop.main.run(until: Date().addingTimeInterval(6))
            report.append(String(format: "%@: %.1f%% CPU", name, (FeatureQAHarness.cpuSeconds() - start) / 6 * 100))
            window.orderOut(nil)
            window.contentView = nil
        }
        theme.setPreviewSystemReduceMotion(NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
        if let folder = ProcessInfo.processInfo.environment["MACSPACES_DEMO_OUTPUT"] {
            try? report.joined(separator: "\n").write(toFile: folder + "/check-agent-cost.txt", atomically: true, encoding: .utf8)
        }

        // Appearance's list with the Editorial pack, in a dark theme and a light one.
        TerminalThemeList.initialPack = .editorial
        for (name, family) in [("dark", ThemeFamily.midnight), ("light", .pearl)] {
            theme.selectFamily(family)
            shoot(AnyView(NookThemePicker().padding(20).frame(width: 760).background(theme.settings.surface)),
                  NSSize(width: 760, height: 600), "check-appearance-editorial-\(name)")
        }
        TerminalThemeList.initialPack = .all
        theme.selectFamily(.midnight)
        func appearancePage() -> some View {
            SettingsPage(title: "Appearance", subtitle: "", fillsHeight: true) { NookThemePicker() }
        }
        for height in [640.0, 1000.0] {
            shoot(AnyView(appearancePage()), NSSize(width: 760, height: height), "check-appearance-page-\(Int(height))")
        }
        for tone in GhosttyLibrary.Tone.allCases {
            TerminalThemeList.initialTone = tone
            shoot(AnyView(appearancePage()), NSSize(width: 760, height: 1500), "check-appearance-order-\(tone.rawValue)")
        }
        TerminalThemeList.initialTone = .all
        theme.selectFamily(savedFamily)
    }
}
#endif
