#if DEBUG
import AppKit
import SwiftUI

/// The `themes-redesign` scope: Settings → Appearance's three drawers for review. The
/// page collapsed and with every drawer open; Terminal as it opens, searched and filtered
/// to Light; Live; Custom in each style; and the open Nook in Custom, a Ghostty theme,
/// Noir and Synthwave. Synthetic data only; the
/// picture is drawn here and imported as the open panel would.
@MainActor enum ThemesRedesignCaptures {
    static func capture(to directory: URL) {
        let theme = ThemeStore.shared
        GhosttyLibrary.shared.load()
        settle { !GhosttyLibrary.shared.themes.isEmpty }
        let width: CGFloat = 820

        func picker(_ open: Set<ThemeCollection>, _ name: String) {
            NookThemePicker.initiallyOpen = open
            let view = NookThemePicker().padding(24).frame(width: width)
                .background(theme.settings.surface).foregroundStyle(theme.settingsForeground)
                .environment(\.colorScheme, ThemeStore.shared.settingsScheme)
            // Let the cards' photos arrive first.
            render(view, name: name, width: width, warmUp: true, directory: directory)
        }

        // The page as it opens: every drawer closed.
        theme.selectFamily(.macspaces)
        NookThemePicker.initiallyOpen = []
        SettingsNavigationModel.shared.selection = .appearance
        renderFixed(SettingsView(), name: "appearance-collapsed", size: NSSize(width: 1100, height: 900), directory: directory)

        // Terminal: ours on top, then Ghostty's in its own order, the same colour pill for
        // each; then the same list with 3.37's swatch cards to compare.
        theme.selectFamily(.everforest)
        picker([.terminal], "terminal")
        TerminalThemeList.swatchPreview = true
        picker([.terminal], "terminal-3.37-swatches")
        TerminalThemeList.swatchPreview = false
        // 3.39's SwiftUI rows, to compare with today's AppKit table pixel for pixel.
        NookThemePicker.legacyViews = true
        picker([.terminal], "terminal-3.39-rows")
        NookThemePicker.legacyViews = false
        if let rose = GhosttyLibrary.shared.theme(named: "Rose Pine Moon") { theme.selectGhostty(rose) }
        TerminalThemeList.initialQuery = "rose"
        picker([.terminal], "terminal-search-rose")
        TerminalThemeList.initialQuery = ""
        TerminalThemeList.initialTone = .light
        if let latte = GhosttyLibrary.shared.theme(named: "Catppuccin Latte") { theme.selectGhostty(latte) }
        picker([.terminal], "terminal-light")
        TerminalThemeList.initialTone = .all

        // Live: every scene at once.
        theme.selectFamily(.synthwave)
        picker([.live], "live")
        NookThemePicker.legacyViews = true
        ThemeMotifView.legacyStillMask = true
        picker([.live], "live-3.39")
        NookThemePicker.legacyViews = false
        ThemeMotifView.legacyStillMask = false
        // Unlisted themes stay exactly as they were for anyone using one, first in their drawer.
        theme.selectFamily(.ruby)
        picker([.terminal], "unlisted-ruby-in-use")
        theme.selectFamily(.sunflower)
        picker([.live], "unlisted-sunflower-in-use")

        // Each style's default, as someone new to Custom first sees it (Reset returns to it),
        // and Picture before any picture.
        for (style, name) in [(CustomThemeStyle.solid, "solid"), (.twoTone, "two-tone"), (.glass, "glass")] {
            theme.selectCustomStyle(style)
            theme.resetCustomStyle()
            print("themes-redesign default \(name): background \(theme.customThemeBackground), accent \(theme.customThemeAccent), second \(theme.customThemeSecond), strength \(theme.customGlassStrength), blur \(theme.customGlassBlurs), reset disabled \(theme.customStyleIsDefault)")
            picker([.custom], "custom-default-\(name)")
        }
        theme.removeCustomPicture()
        theme.selectCustomStyle(.image)
        picker([.custom], "custom-picture-empty")

        // Custom in each style.
        custom(.solid, "060C24", "4D7CFF")
        picker([.custom], "custom-solid")
        custom(.twoTone, "141022", "FF9E7A", second: "4A2343")
        picker([.custom], "custom-two-tone")
        custom(.glass, "F6F8FB", "2F6BB3", strength: 0.55, blurs: true)
        picker([.custom], "custom-glass-frost")
        custom(.glass, "15171B", "E4E9F0", strength: 0, blurs: false)
        picker([.custom], "custom-glass-clear")
        let picture = directory.appendingPathComponent("Synthetic picture.png")
        writeSyntheticPicture(to: picture)
        if let result = CustomTheme.importImage(from: picture) {
            theme.setCustomPicture(result.name, background: result.background, accent: result.accent)
            print("themes-redesign picture palette: background \(result.background), accent \(result.accent)")
        }
        CustomBackgroundImage.shared.prepare()
        settle { CustomBackgroundImage.shared.image != nil }
        picker([.custom], "custom-picture")
        // Remove Picture: the copy goes and Picture is empty again.
        theme.removeCustomPicture()
        settle { ((try? FileManager.default.contentsOfDirectory(atPath: CustomTheme.imageFolder.path)) ?? []).isEmpty }
        print("themes-redesign picture removed: image key \(theme.customImageName ?? "nil"), files left \(((try? FileManager.default.contentsOfDirectory(atPath: CustomTheme.imageFolder.path)) ?? []).count)")
        picker([.custom], "custom-picture-removed")
        if let result = CustomTheme.importImage(from: picture) {
            theme.setCustomPicture(result.name, background: result.background, accent: result.accent)
        }
        CustomBackgroundImage.shared.prepare()
        settle { CustomBackgroundImage.shared.image != nil }

        // The open Nook in the picture, Two-tone and a Ghostty theme.
        renderNook("nook-custom-picture", directory: directory)
        custom(.twoTone, "141022", "FF9E7A", second: "4A2343")
        renderNook("nook-custom-two-tone", directory: directory)
        if let kanagawa = GhosttyLibrary.shared.theme(named: "Kanagawa Wave") { theme.selectGhostty(kanagawa) }
        renderNook("nook-ghostty-kanagawa", directory: directory)
        theme.selectFamily(.macspaces)
        renderNook("nook-noir", directory: directory)
        theme.selectFamily(.synthwave)
        renderNook("nook-synthwave", directory: directory)

        // The README's Themes row: a matching set. Settings in one theme (Blossom), each image
        // only its own drawer open, all the same size, the drawer running off a soft bottom edge.
        theme.selectFamily(.blossom)
        for (collection, name) in [(ThemeCollection.terminal, "readme-terminal"), (.live, "readme-macspaces"), (.custom, "readme-custom")] {
            if collection == .custom {
                // Custom shows the Picture style (the owner's favourite), while Settings stays in Blossom.
                let picture = directory.appendingPathComponent("Synthetic picture.png")
                writeSyntheticPicture(to: picture)
                if let result = CustomTheme.importImage(from: picture) {
                    theme.setCustomPicture(result.name, background: result.background, accent: result.accent)
                }
                CustomBackgroundImage.shared.prepare()
                settle { CustomBackgroundImage.shared.image != nil }
                theme.selectFamily(.blossom)
            }
            NookThemePicker.initiallyOpen = [collection]
            let view = NookThemePicker().padding(24).frame(width: width).fixedSize(horizontal: false, vertical: true)
                .frame(width: width, height: 420, alignment: .top).clipped()
                .mask(LinearGradient(stops: [.init(color: .black, location: 0.84), .init(color: .clear, location: 1)], startPoint: .top, endPoint: .bottom))
                .background(theme.settings.surface).foregroundStyle(theme.settingsForeground)
                .environment(\.colorScheme, ThemeStore.shared.settingsScheme)
            renderFixed(view, name: name, size: NSSize(width: width, height: 420), directory: directory)
        }

        // The whole page with every drawer open.
        theme.selectFamily(.blossom)
        NookThemePicker.startsFullyOpen = true
        SettingsNavigationModel.shared.selection = .appearance
        renderFixed(SettingsView(), name: "appearance-all-open", size: NSSize(width: 1100, height: 2700), directory: directory)
        NookThemePicker.initiallyOpen = []
        try? FileManager.default.removeItem(at: CustomTheme.imageFolder)
        print("Themes redesign captures written")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    /// The open Nook on Home, with synthetic content, as the motif captures draw it.
    private static func renderNook(_ name: String, directory: URL) {
        let suite = "MacSpaces.ThemesQA." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = NookSettings(defaults: defaults)
        settings.widgets = [.media, .timer, .clock]
        let player = NowPlayingController()
        var track = NowPlayingInfo()
        track.title = "Evening light"; track.artist = "Sample Artist"; track.album = "Sample Album"
        track.duration = 240; track.elapsed = 75; track.isPlaying = true
        track.capabilities = [.playPause, .previous, .next, .seek]
        player.setPreviewInfo(track)
        let model = NotchViewModel(geometry: NotchGeometry(width: 185, height: 32, isHardwareNotch: true), availableWidth: 1440,
            settings: settings, shelf: ShelfStore(basketID: UUID()), nowPlaying: player, powerMonitor: AppServices.shared.powerMonitor,
            timerService: AppServices.shared.timerService, bluetoothMonitor: AppServices.shared.bluetooth,
            systemActivityMonitor: AppServices.shared.systemActivity, teleprompter: TeleprompterService(nowPlaying: player))
        model.state = .expanded
        renderFixed(NotchContainerView(viewModel: model), name: name,
                    size: NSSize(width: model.expandedSize.width + 52, height: model.expandedSize.height + 28), directory: directory)
    }

    /// A made-up landscape: a dusk gradient, a sun and hills; never a real photo.
    private static func writeSyntheticPicture(to url: URL) {
        let image = NSImage(size: NSSize(width: 1600, height: 1000), flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.62, blue: 0.42, alpha: 1),
                                NSColor(srgbRed: 0.55, green: 0.30, blue: 0.55, alpha: 1),
                                NSColor(srgbRed: 0.12, green: 0.10, blue: 0.28, alpha: 1)])?.draw(in: rect, angle: -90)
            NSColor(srgbRed: 1, green: 0.85, blue: 0.55, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 1080, y: 520, width: 220, height: 220)).fill()
            for (i, shade) in [0.16, 0.10, 0.06].enumerated() {
                NSColor(srgbRed: shade, green: shade * 0.8, blue: shade * 1.6, alpha: 1).setFill()
                let hill = NSBezierPath()
                hill.move(to: .zero)
                for x in stride(from: 0, through: 1600, by: 40) {
                    let y = 260 - CGFloat(i) * 70 + 60 * sin(CGFloat(x) / 210 + CGFloat(i) * 1.7)
                    hill.line(to: NSPoint(x: CGFloat(x), y: y))
                }
                hill.line(to: NSPoint(x: 1600, y: 0)); hill.close(); hill.fill()
            }
            return true
        }
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }

    private static func custom(_ style: CustomThemeStyle, _ background: String, _ accent: String, second: String? = nil,
                               strength: Double? = nil, blurs: Bool? = nil) {
        let theme = ThemeStore.shared
        theme.customStyle = style
        theme.customThemeBackground = background; theme.customThemeAccent = accent
        if let second { theme.customThemeSecond = second }
        if let strength { theme.customGlassStrength = strength }
        if let blurs { theme.customGlassBlurs = blurs }
        theme.selectFamily(.custom)
    }

    private static func settle(timeout: TimeInterval = 5, _ done: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    /// Renders at the view's own height.
    private static func render<V: View>(_ view: V, name: String, width: CGFloat, warmUp: Bool, directory: URL) {
        let host = NSHostingView(rootView: view)
        let height = max(200, host.fittingSize.height)
        renderFixed(view, name: name, size: NSSize(width: width, height: height), directory: directory, settleFor: warmUp ? 1.5 : 0.9)
    }

    private static func renderFixed<V: View>(_ view: V, name: String, size: NSSize, directory: URL, settleFor: TimeInterval = 1.5) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host; window.appearance = NSAppearance(named: .darkAqua)
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(settleFor))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = FeatureQAHarness.qaBitmap(for: host)
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        window.contentView = nil
    }
}
#endif
