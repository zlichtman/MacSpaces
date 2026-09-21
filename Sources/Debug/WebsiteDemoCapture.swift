#if DEBUG
import SwiftUI
import AppKit

/// Fresh website captures of native views. Run only in the isolated demo bundle.
@MainActor
enum WebsiteDemoCapture {
    static func captureIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["MACSPACES_WEBSITE_DEMO"] == "1" else { return false }
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.WebsiteDemo")
        let environment = ProcessInfo.processInfo.environment
        let output = URL(fileURLWithPath: environment["MACSPACES_DEMO_OUTPUT"] ?? "/private/tmp/macspaces-gallery-native")
        let artworkPath = environment["MACSPACES_DEMO_ARTWORK"] ?? "/private/tmp/macspaces-phantogram.jpg"
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        InteractionRegressionChecks.run()
        AppleDockPlacement.shared.setPreviewEdge(.left)
        let theme = ThemeStore.shared
        theme.reset()
        let services = AppServices.shared
        var track = NowPlayingInfo()
        track.title = "Mouthful of Diamonds"
        track.artist = "Phantogram"
        track.album = "Eyelid Movies"
        track.isPlaying = true
        track.duration = 253.427
        track.elapsed = 74
        track.artwork = NSImage(contentsOfFile: artworkPath)!
        services.nowPlaying.setPreviewInfo(track)
        let settings = NookSettings.shared
        settings.showTeleprompterBar = false
        settings.showMusicLiveActivity = true
        settings.showTimerLiveActivity = false
        settings.showBluetoothLiveActivity = false
        settings.showPowerLiveActivity = false
        settings.expandedWidth = 720
        settings.expandedHeight = 246
        settings.fitWidthToProfile = true
        let timer = TimerService(previewRemaining: 18 * 60 + 19, total: 25 * 60)
        let shelf = ShelfStore()
        let sampleDirectory = output.appendingPathComponent("Demo files")
        try! FileManager.default.createDirectory(at: sampleDirectory, withIntermediateDirectories: true)
        let notes = sampleDirectory.appendingPathComponent("Project notes.md")
        try! "# Project notes\nA focused desktop, your way.\n".write(to: notes, atomically: true, encoding: .utf8)
        let artwork = sampleDirectory.appendingPathComponent("Cover.jpg")
        try? FileManager.default.removeItem(at: artwork)
        try! FileManager.default.copyItem(atPath: artworkPath, toPath: artwork.path)
        shelf.setPreviewItems([notes, artwork], selectedIndex: 0)
        func model(hardware: Bool = false, availableWidth: CGFloat = 1440) -> NotchViewModel {
            NotchViewModel(geometry: hardware ? NotchGeometry(width: 185, height: 32, isHardwareNotch: true) : .synthetic,
                availableWidth: availableWidth, settings: settings, shelf: shelf,
                nowPlaying: services.nowPlaying, powerMonitor: services.powerMonitor, timerService: timer,
                bluetoothMonitor: services.bluetooth, systemActivityMonitor: services.systemActivity, teleprompter: services.teleprompter)
        }
        func profile(_ widgets: [NookWidgetKind], style: WidgetVisualStyle = .studio) {
            let p = NookProfile(id: UUID(), name: "Demo", widgets: widgets,
                widgetWidths: [NookWidgetKind.media.rawValue: 280, NookWidgetKind.timer.rawValue: 126, NookWidgetKind.clock.rawValue: 126],
                widgetStyles: Dictionary(uniqueKeysWithValues: widgets.map { ($0.rawValue, style) }))
            settings.profiles = [p]
            settings.activeProfileID = p.id
        }
        let dock = DockStore.shared
        dock.beginInteractiveReorder()
        dock.tileSize = 110
        dock.position = .bottom
        func dockProfile(_ kinds: [WidgetKind], style: WidgetVisualStyle = .studio) {
            dock.widgets = kinds.map { WidgetInstance(kind: $0, visualStyle: style, sizeMode: .full) }
        }
        func dockSize() -> CGSize {
            let items = dock.widgets.dockLayoutItems(vertical: false)
            let width = items.reduce(CGFloat(14)) { $0 + $1.axisLength(tile: CGFloat(dock.tileSize), spacing: 6) } + CGFloat(max(0, items.count - 1)) * 6
            return CGSize(width: width, height: CGFloat(dock.tileSize) + 14)
        }
        func palette(_ name: String) {
            theme.reset()
            if name == "gold" {
                theme.customNotchHex = "#211A11"
                theme.customDockHex = "#211A11"
                theme.customAccentHex = "#D6AF63"
                theme.accentChoice = .custom
                theme.applyCoordinatedPreset(.custom)
                theme.notchThemeIntensity = 0.55
                theme.dockThemeIntensity = 0.55
            } else if name == "everforest" {
                theme.customNotchHex = "#2D353B"
                theme.customDockHex = "#2D353B"
                theme.customAccentHex = "#A7C080"
                theme.accentChoice = .custom
                theme.applyCoordinatedPreset(.custom)
            } else {
                theme.applyCoordinatedPreset(name == "sunset" ? .sunset : .midnight)
            }
        }
        func song(_ index: Int) {
            var info = NowPlayingInfo()
            let songs = [("Mouthful of Diamonds", "Phantogram", "Eyelid Movies", artworkPath),
                         ("I Melt With You", "Modern English", "Pillow Lips", "/private/tmp/macspaces-pillow-lips.jpg"),
                         ("White Dress", "Lana Del Rey", "Chemtrails Over the Country Club", "/private/tmp/macspaces-lana.jpg")]
            let selected = songs[index]
            info.title = selected.0; info.artist = selected.1; info.album = selected.2
            info.isPlaying = true; info.duration = index == 2 ? 333 : 253; info.elapsed = 74
            info.artwork = NSImage(contentsOfFile: selected.3)!
            services.nowPlaying.setPreviewInfo(info)
        }
        func sideDockSize() -> CGSize {
            let height = dock.widgets.reduce(CGFloat(14)) { $0 + $1.kind.axisLength(tile: CGFloat(dock.tileSize), spacing: 6) }
                + CGFloat(max(0, dock.widgets.count - 1)) * 6
            return CGSize(width: dock.sideDockWidth + 14, height: height)
        }
        UserDefaults.standard.set(["#D6AF63", "#A7C080", "#73A4D5", "#D3B9D7"], forKey: "colorPickerHistory")
        dock.position = .right
        for (index, name) in ["gold", "midnight", "everforest"].enumerated() {
            song(index); palette(name)
            profile(index == 1 ? [.clock, .media, .timer] : [.media, .timer, .clock])
            dock.sideDockWidth = 154
            dockProfile(index == 0 ? [.clock, .quickActions, .drinkWater] : index == 1 ? [.pomodoro, .colorPicker, .quickActions] : [.progress, .clock, .drinkWater])
            let overview = model(hardware: true); overview.state = .expanded
            let size = sideDockSize()
            render(ZStack(alignment: .top) {
                NotchContainerView(viewModel: overview).overlay(alignment: .top) {
                    UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 185, height: 32)
                }.frame(width: 700, height: 254)
                HStack { Spacer(); DockContainerView(store: dock).frame(width: size.width, height: size.height).padding(.trailing, 12) }
                    .frame(height: 650, alignment: .bottom).padding(.top, 20)
            }.frame(width: 1080, height: 680), size: CGSize(width: 1080, height: 680), to: output.appendingPathComponent("desktop-\(name).png"))
            // Each detail composition is independent of the overview.
            profile(index == 0 ? [.media, .clock, .timer] : index == 1 ? [.timer, .media, .clock] : [.clock, .timer, .media])
            let nook = model(); nook.state = .expanded
            render(NotchContainerView(viewModel: nook).frame(width: 620, height: 260).frame(width: 680, height: 340),
                   size: CGSize(width: 680, height: 340), to: output.appendingPathComponent("nook-\(name).png"))
            dock.sideDockWidth = 220
            dockProfile(index == 0 ? [.nowPlaying, .clock, .quickActions, .drinkWater] : index == 1 ? [.clock, .nowPlaying, .colorPicker, .pomodoro] : [.nowPlaying, .pomodoro, .drinkWater, .quickActions])
            let detailSize = sideDockSize()
            render(DockContainerView(store: dock).frame(width: detailSize.width, height: detailSize.height)
                .frame(width: 280, height: 640), size: CGSize(width: 280, height: 640),
                to: output.appendingPathComponent("column-\(name).png"))
        }
        for destination in [SettingsDestination.notch, .dock, .theme] {
            SettingsNavigationModel.shared.selection = destination
            render(SettingsView().frame(width: 980, height: 760), size: CGSize(width: 980, height: 760), to: output.appendingPathComponent("settings-\(destination.rawValue).png"))
        }
        // Regression captures: a physical camera overlay exposes controls hidden behind it.
        settings.fitWidthToProfile = true
        settings.expandedWidth = 480
        for (name, widgets) in [("empty", [NookWidgetKind]()), ("one", [.timer]), ("pair", [.timer, .clock])] {
            profile(widgets)
            let nook = model(hardware: true); nook.state = .expanded
            precondition(nook.expandedSize.width >= 185 + 440)
            precondition(nook.expandedHeaderTopInset == 9)
            render(NotchContainerView(viewModel: nook).overlay(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 185, height: 32)
            }.frame(width: 700, height: 280), size: CGSize(width: 700, height: 280), to: output.appendingPathComponent("regression-\(name).png"))
            let constrained = model(hardware: true, availableWidth: 520)
            precondition(constrained.expandedHeaderTopInset >= 32 + 8)
        }
        print("Website captures and notch layout checks complete: \(output.path)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
        return true
    }
    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.contentView = host
        host.layoutSubtreeIfNeeded()
        host.displayIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
#endif
