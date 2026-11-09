#if DEBUG
import SwiftUI
import AppKit

/// Check renders for the Music page's Shelf (`MACSPACES_DEMO_KIND=tools`, stopping here with
/// `MACSPACES_DEMO_ONLY=shelf`): one source at a time, the fallback to the first playlist with
/// songs when Liked Songs has none, and the source menu open over the shelf in a real Nook
/// window. Songs are the owner's, from `MACSPACES_DEMO_SEQUENCE`. Never published.
extension WebsiteDemoClips {
    private struct ShelfSequence: Decodable {
        struct Entry: Decodable { let key: String; let title: String; let artist: String; let album: String }
        let songs: [Entry]
    }

    static func shelfChecks(output: URL, pictures: [URL], shoot: (AnyView, NSSize, String) -> Void) async {
        let env = ProcessInfo.processInfo.environment
        guard let path = env["MACSPACES_DEMO_SEQUENCE"],
              let data = try? Data(contentsOf: URL(fileURLWithPath: path)),
              let sequence = try? JSONDecoder().decode(ShelfSequence.self, from: data), !sequence.songs.isEmpty else {
            print("Shelf checks: set MACSPACES_DEMO_SEQUENCE to Demos/music-sequence.json; skipped")
            return
        }
        let theme = ThemeStore.shared
        theme.selectFamily(.fern)
        // Covers: the fetched ones when the capture has them, otherwise the basket's pictures.
        let songs = sequence.songs.enumerated().map { index, entry -> SpotifyLibrary.Song in
            let fetched = WebsiteDemoProfile.track(entry.key).map { URL(fileURLWithPath: $0.cover) }
            let image = fetched ?? (pictures.isEmpty ? nil : pictures[index % pictures.count])
            return SpotifyLibrary.Song(title: entry.title, artists: entry.artist, album: entry.album, image: image, link: nil)
        }
        func playlist(_ id: String, _ name: String, total: Int?) -> SpotifyLibrary.ShelfSource {
            var source = SpotifyLibrary.ShelfSource(id: id, name: name)
            source.total = total
            source.image = pictures.first
            return source
        }
        // Liked Songs is empty, and so is the first playlist (its count was out of date), so the
        // shelf falls back to Euphoric, the first with songs. More playlists fill the menu.
        let shelf: [(source: SpotifyLibrary.ShelfSource, songs: [SpotifyLibrary.Song])] = [
            (.liked, []),
            (playlist("autumn", "Autumn drives", total: 3), []),
            (playlist("euphoric", "Euphoric", total: songs.count), songs),
            (playlist("late", "Late night", total: 2), Array(songs.suffix(2))),
            (playlist("road", "Road trip", total: 3), Array(songs.prefix(3))),
            (playlist("sunday", "Sunday morning", total: 2), Array(songs.dropFirst(2).prefix(2))),
        ]
        let size = NSSize(width: 600, height: 300)
        func shelfView() -> AnyView {
            AnyView(SpotifyShelfView(nowPlaying: AppServices.shared.nowPlaying).frame(width: 572, height: 272).padding(14)
                .background(theme.notch.surface).foregroundStyle(theme.nookForeground))
        }
        let library = SpotifyLibrary.shared
        library.setPreview(account: "sample", top: nil, backups: [], shelf: shelf)
        for _ in 0..<40 where library.shelfSource == .liked { try? await Task.sleep(nanoseconds: 50_000_000) }
        print("Shelf checks: chose \(library.shelfChoice.name), showing \(library.shelfSource.name) with \(library.shelfRows.count) songs")
        shoot(shelfView(), size, "check-shelf-fallback")
        WebsiteDemoProfile.play(WebsiteDemoProfile.homeTrack)
        shoot(shelfView(), size, "check-shelf-playing")
        await shelfLooks(songs: songs, shoot: shoot)
        theme.selectFamily(.fern)
        await shelfMenuCheck(output: output, name: "check-shelf-menu")
    }

    /// The Shelf as the Nook draws it (its surface, gradient and scene) in a dark terminal theme
    /// (Duckbones), a photo scene (Blossom) and Midnight, playing and paused, and with Reduce
    /// Motion: `check-shelf-<theme>-<state>.png`. Plays Mouthful of Diamonds,
    /// its lyric beside the source.
    private static func shelfLooks(songs: [SpotifyLibrary.Song], shoot: (AnyView, NSSize, String) -> Void) async {
        let theme = ThemeStore.shared
        let services = AppServices.shared
        GhosttyLibrary.shared.load()
        for _ in 0..<100 where GhosttyLibrary.shared.themes.isEmpty { try? await Task.sleep(nanoseconds: 50_000_000) }
        ThemeMotifView.breezeUsesShader = false
        defer { ThemeMotifView.breezeUsesShader = true }
        let size = NSSize(width: 600, height: 300)
        func nook(pose: (position: CGFloat, out: CGFloat)? = nil) -> AnyView {
            AnyView(ZStack {
                theme.notch.surface
                LinearGradient(colors: [theme.notch.surfaceSecondary, .clear], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let motif = theme.activeMotif {
                    ThemeMotifView(motif: motif, accent: theme.notch.accent, ink: theme.nookForeground, animated: false)
                }
                SpotifyShelfView(nowPlaying: services.nowPlaying, lyrics: services.teleprompter, previewPose: pose)
                    .frame(width: 572, height: 272).padding(14)
            }
            .frame(width: 600, height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .foregroundStyle(theme.nookForeground))
        }
        func playing(_ on: Bool) {
            WebsiteDemoProfile.play(WebsiteDemoProfile.track("phantogram"))
            var info = services.nowPlaying.info
            info.isPlaying = on
            services.nowPlaying.setPreviewInfo(info)
            if let line = WebsiteDemoProfile.track("phantogram")?.lyrics?.first {
                services.teleprompter.setPreview(current: line, source: .lyrics)
            }
        }
        let looks: [(name: String, select: () -> Void)] = [
            ("duckbones", { if let found = GhosttyLibrary.shared.theme(named: "Duckbones") { theme.selectGhostty(found) } }),
            ("blossom", { theme.selectFamily(.blossom) }),
            ("midnight", { theme.selectFamily(.midnight) }),
        ]
        let wasTint = WidgetOptions.shared.albumTint, wasAscii = WidgetOptions.shared.asciiCover
        let wasScene = WidgetOptions.shared.asciiScene
        WidgetOptions.shared.albumTint = false
        for look in looks {
            look.select()
            // The scene's photo, decoded before the picture is taken.
            if let motif = theme.activeMotif, let asset = motif.floralAsset ?? motif.natureAsset {
                MotifImages.shared.prepare(motif)
                for _ in 0..<100 where MotifImages.shared.image(for: asset) == nil { try? await Task.sleep(nanoseconds: 50_000_000) }
                print("Shelf looks: \(look.name) scene \(asset) ready \(MotifImages.shared.image(for: asset) != nil)")
            }
            theme.setPreviewSystemReduceMotion(false)
            playing(true)
            shoot(nook(), size, "check-shelf-\(look.name)-playing")
            playing(false)
            shoot(nook(), size, "check-shelf-\(look.name)-paused")
            // ASCII art with the Vinyl scene: the record turns as the Vinyl look's.
            WidgetOptions.shared.asciiCover = true
            WidgetOptions.shared.asciiScene = .vinyl
            playing(true)
            AsciiCoverCache.shared.prepareNow(services.nowPlaying.info.artwork)
            shoot(nook(), size, "check-shelf-\(look.name)-ascii")
            WidgetOptions.shared.asciiCover = false
        }
        looks[0].select()
        theme.setPreviewSystemReduceMotion(true)
        playing(true)
        shoot(nook(), size, "check-shelf-duckbones-reduce-motion")
        theme.setPreviewSystemReduceMotion(false)
        if ProcessInfo.processInfo.environment["MACSPACES_SHELF_CPU"] == "1" { await shelfCPU(nook: { nook() }, playing: playing) }
        // Flipping on to the next sleeve as the record goes back into its sleeve and comes out
        // again: `check-shelf-strip-<n>.png`, joined into one strip by the caller.
        let strip: [(CGFloat, CGFloat)] = [(1, 1), (1.25, 0.6), (1.55, 0.25), (1.85, 0), (2, 0.3), (2, 0.65), (2, 1)]
        for (index, pose) in strip.enumerated() {
            shoot(nook(pose: pose), size, "check-shelf-strip-\(index + 1)")
        }
        WidgetOptions.shared.albumTint = wasTint
        WidgetOptions.shared.asciiCover = wasAscii
        WidgetOptions.shared.asciiScene = wasScene
        services.teleprompter.setPreview(current: "", source: .lyrics)
    }

    /// The process's CPU while the Shelf shows in a window, paused and then playing eight seconds each, from `getrusage`: `MACSPACES_SHELF_CPU=1`. The window is off
    /// screen, so what the window server composites isn't counted.
    private static func shelfCPU(nook: () -> AnyView, playing: (Bool) -> Void) async {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 300), styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        window.orderFrontRegardless()
        func used() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            return Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec) + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
        }
        for (name, on) in [("paused", false), ("playing", true)] {
            playing(on)
            window.contentView = NSHostingView(rootView: nook())
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            let start = used(), began = Date()
            try? await Task.sleep(nanoseconds: 8_000_000_000)
            print(String(format: "Shelf CPU: %@ %.1f%%", name, (used() - start) / Date().timeIntervalSince(began) * 100))
        }
        window.contentView = nil
        window.orderOut(nil)
    }

    /// The Shelf in a real Nook window (`NotchWindow`, the status-bar panel) with its source menu
    /// clicked open, then every window drawn in the order the window server stacks them, so the
    /// picture shows what's really on top. Logs each window's level and place in the stack.
    private static func shelfMenuCheck(output: URL, name: String) async {
        let theme = ThemeStore.shared
        let size = NSSize(width: 600, height: 300)
        let host = NSHostingView(rootView: SpotifyShelfView(nowPlaying: AppServices.shared.nowPlaying)
            .frame(width: 572, height: 272).padding(14)
            .background(theme.notch.surface).foregroundStyle(theme.nookForeground)
            .environment(\.colorScheme, .dark))
        let window = NotchWindow(contentRect: NSRect(origin: .zero, size: size))
        window.appearance = NSAppearance(named: .darkAqua)
        window.installNookContent(host)
        // Off screen, as the other checks are drawn, unless asked to show it.
        let onScreen = ProcessInfo.processInfo.environment["MACSPACES_SHELF_ONSCREEN"] == "1"
        if onScreen, let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: screen.frame.midX - size.width / 2, y: screen.visibleFrame.maxY - size.height - 40))
        } else {
            window.setFrameOrigin(NSPoint(x: -20000, y: -20000))
        }
        window.orderFrontRegardless()
        try? await Task.sleep(nanoseconds: 1_200_000_000)
        host.layoutSubtreeIfNeeded()

        // Click the source pill: at the foot, 14 pt in plus the page's 20 (AppKit counts up from the bottom).
        let point = NSPoint(x: 14 + 20 + 20, y: 14 + 4 + 16)
        // As in the app: an accessory app that isn't active, its Nook a panel that isn't key.
        // (Active, AppKit stacks the menu in front anyway; inactive, it stacked it behind.)
        NSApp.setActivationPolicy(.accessory)
        NSApp.deactivate()
        try? await Task.sleep(nanoseconds: 500_000_000)
        print("Shelf menu check: app active \(NSApp.isActive), Nook key \(window.isKeyWindow)")
        // A click lands once the view has settled; try again if no menu shows.
        func menuShows() -> Bool { window.childWindows?.contains { $0.isVisible } == true }
        for _ in 0..<5 where !menuShows() {
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                if let event = NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                                  windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                    window.sendEvent(event)
                }
            }
            try? await Task.sleep(nanoseconds: 1_200_000_000)
        }

        // What the window server stacks, front to back, for this app.
        func stacked(_ moment: String) -> (stack: [NSWindow], menus: [NSWindow]) {
            let pid = ProcessInfo.processInfo.processIdentifier
            let list = (CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] ?? [])
                .filter { ($0[kCGWindowOwnerPID as String] as? Int32) == pid }
            let numbers = list.compactMap { $0[kCGWindowNumber as String] as? Int }
            let ours = NSApp.windows.filter { $0.isVisible }
            let stack = numbers.compactMap { number in ours.first { $0.windowNumber == number } }
            for (place, shown) in stack.enumerated() {
                let kind = String(describing: type(of: shown))
                let parent = shown.parent.map { String(describing: type(of: $0)) } ?? "none"
                print("Shelf menu check [\(moment)]: \(place) \(kind) level \(shown.level.rawValue) parent \(parent)"
                      + " frame \(shown.frame)" + (shown === window ? " (the Nook)" : ""))
            }
            let menus = stack.filter { $0 !== window && String(describing: type(of: $0)).localizedCaseInsensitiveContains("popover") }
            let nook = stack.firstIndex { $0 === window } ?? .max
            let inFront = menus.allSatisfy { menu in (stack.firstIndex { $0 === menu } ?? .max) < nook }
            print("Shelf menu check [\(moment)]: menu \(menus.isEmpty ? "missing" : inFront ? "in front of the Nook" : "BEHIND the Nook")")
            return (stack, menus)
        }
        _ = stacked("opened")
        // What the Nook does to its window while it's open: brought forward again
        // (`NotchManager` on a hidden app's return and a page shown from the menu bar or keyboard).
        if ProcessInfo.processInfo.environment["MACSPACES_SHELF_PROBE"] == "1" {
            window.orderFrontRegardless()
            _ = stacked("after orderFrontRegardless")
            window.makeKeyAndOrderFront(nil)
            _ = stacked("after makeKeyAndOrderFront")
            window.orderOut(nil)
            window.orderFrontRegardless()
            _ = stacked("after orderOut then orderFrontRegardless")
        }

        // Drawn back to front as stacked now, on the site's page colour.
        let (stack, popovers) = stacked("drawn")
        let drawn = stack.reversed().filter { $0 === window || popovers.contains($0) }
        // Off screen, AppKit puts the menu on a screen far from the Nook: draw it where it opens,
        // under the pill, keeping the window server's order.
        func placed(_ shown: NSWindow) -> NSRect {
            guard shown !== window, !onScreen else { return shown.frame }
            let origin = NSPoint(x: window.frame.minX + point.x - 40, y: window.frame.minY + point.y - 16 - shown.frame.height)
            return NSRect(origin: origin, size: shown.frame.size)
        }
        let bounds = drawn.map(placed).reduce(window.frame) { $0.union($1) }.insetBy(dx: -16, dy: -16)
        let scale: CGFloat = 2
        if let canvas = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(bounds.width * scale), pixelsHigh: Int(bounds.height * scale),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
           let context = NSGraphicsContext(bitmapImageRep: canvas) {
            canvas.size = bounds.size
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = context
            context.cgContext.scaleBy(x: scale, y: scale)
            NSColor(red: 250 / 255, green: 247 / 255, blue: 241 / 255, alpha: 1).setFill()
            NSRect(origin: .zero, size: bounds.size).fill()
            for shown in drawn {
                guard let view = shown.contentView?.superview ?? shown.contentView,
                      let picture = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { continue }
                view.cacheDisplay(in: view.bounds, to: picture)
                let frame = placed(shown)
                let origin = NSPoint(x: frame.minX - bounds.minX, y: frame.minY - bounds.minY)
                picture.draw(in: NSRect(origin: origin, size: shown.frame.size), from: .zero, operation: .sourceOver,
                             fraction: 1, respectFlipped: true, hints: nil)
            }
            NSGraphicsContext.restoreGraphicsState()
            try? canvas.representation(using: .png, properties: [:])?.write(to: output.appendingPathComponent(name + ".png"))
        }
        popovers.forEach { $0.orderOut(nil) }
        window.contentView = nil
        window.orderOut(nil)
    }
}
#endif
