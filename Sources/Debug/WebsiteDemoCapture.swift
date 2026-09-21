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
        let artworkPath = environment["MACSPACES_DEMO_ARTWORK"] ?? "/private/tmp/macspaces-pillow-lips.jpg"
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let theme = ThemeStore.shared
        theme.reset()
        let services = AppServices.shared
        var track = NowPlayingInfo()
        track.title = "I Melt With You"
        track.artist = "Modern English"
        track.album = "Pillow Lips"
        track.isPlaying = true
        track.duration = 235.933
        track.elapsed = 96
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
            if name == "everforest" {
                theme.customNotchHex = "#2D353B"
                theme.customDockHex = "#2D353B"
                theme.customAccentHex = "#A7C080"
                theme.accentChoice = .custom
                theme.applyCoordinatedPreset(.custom)
            } else {
                theme.applyCoordinatedPreset(name == "sunset" ? .sunset : .midnight)
            }
        }
        // The overview owns its combined compositions; none appear on the detail slides.
        for name in ["midnight", "everforest", "sunset"] {
            palette(name)
            profile([.media, .timer, .clock])
            dockProfile([.nowPlaying, .pomodoro, .progress])
            let nook = model(); nook.state = .expanded
            let size = dockSize()
            render(VStack(spacing: 30) {
                NotchContainerView(viewModel: nook).frame(width: 700, height: 254)
                DockContainerView(store: dock).frame(width: size.width, height: size.height)
            }.padding(.vertical, 26).frame(width: 740, height: 460), size: CGSize(width: 740, height: 460), to: output.appendingPathComponent("overview-\(name).png"))
        }
        palette("midnight")
        for (name, widgets) in [("music", [NookWidgetKind.media, .timer, .clock]), ("focus", [.timer, .clock])] {
            profile(widgets)
            let nook = model(); nook.state = .expanded
            render(NotchContainerView(viewModel: nook).frame(width: 580, height: 260).padding(.top, 28).frame(width: 620, height: 324), size: CGSize(width: 620, height: 324), to: output.appendingPathComponent("notch-\(name).png"))
        }
        profile([.media, .timer, .clock])
        settings.expandedWidth = 560
        settings.fitWidthToProfile = false
        let tray = model(); tray.state = .expanded; tray.selectedTab = .tray
        render(NotchContainerView(viewModel: tray).frame(width: 580, height: 260).padding(.top, 28).frame(width: 620, height: 324), size: CGSize(width: 620, height: 324), to: output.appendingPathComponent("notch-tray.png"))
        for (name, widgets) in [("listen", [WidgetKind.nowPlaying, .pomodoro]), ("plan", [.clock, .progress, .quickActions]), ("focus", [.nowPlaying, .clock, .pomodoro])] {
            dockProfile(widgets)
            let size = dockSize()
            render(DockContainerView(store: dock).frame(width: size.width, height: size.height).frame(width: size.width + 48, height: 184), size: CGSize(width: size.width + 48, height: 184), to: output.appendingPathComponent("dock-\(name).png"))
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
