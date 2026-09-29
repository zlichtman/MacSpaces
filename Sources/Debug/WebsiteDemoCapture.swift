#if DEBUG
import SwiftUI
import AppKit

/// Captures native Nook views using isolated preferences and synthetic content.
@MainActor
enum WebsiteDemoCapture {
    static func captureIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["MACSPACES_WEBSITE_DEMO"] == "1" else { return false }
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.WebsiteDemo")
        let env = ProcessInfo.processInfo.environment
        let output = URL(fileURLWithPath: env["MACSPACES_DEMO_OUTPUT"] ?? "/private/tmp/macspaces-nook-demo")
        try! FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        InteractionRegressionChecks.run()
        DeviceRegressionChecks.run()
        let settings = NookSettings.shared
        let services = AppServices.shared
        let theme = ThemeStore.shared
        if env["MACSPACES_DEVICE_AUDIT"] == "1" {
            services.powerMonitor.start()
            services.bluetooth.start()
            DispatchQueue.main.asyncAfter(deadline: .now() + 9) {
                let devices = services.bluetooth.connectedDevices
                print("Device audit: connected=\(devices.count), withBattery=\(devices.filter { $0.batteryPercent != nil }.count), withComponents=\(devices.filter { $0.batteryLevels.left != nil || $0.batteryLevels.right != nil }.count), powerRead=\(services.powerMonitor.hasReading), charging=\(services.powerMonitor.isCharging), externalPower=\(services.powerMonitor.isOnExternalPower)")
                services.bluetooth.stop(); services.powerMonitor.stop()
                NSApp.terminate(nil)
            }
            return true
        }
        settings.showTeleprompterBar = false
        settings.showMusicLiveActivity = true
        settings.showTimerLiveActivity = false
        settings.showPowerLiveActivity = false
        settings.expandedWidth = 860
        settings.expandedHeight = 270
        settings.fitWidthToProfile = true
        services.weather.setPreviewSnapshot(WeatherSnapshot(temperature: 22, weatherCode: 2, high: 25, low: 17))
        services.clipboard.setPreviewEntries(["Meet at the lake at 5:30", "A small space for a clear head."])
        UserDefaults.standard.set("Today\nFinish the first draft\nTake a walk by the lake", forKey: "quickNote")
        let timer = TimerService(previewRemaining: 18 * 60 + 19, total: 25 * 60)
        let shelf = ShelfStore()
        let files = output.appendingPathComponent("Demo files")
        try! FileManager.default.createDirectory(at: files, withIntermediateDirectories: true)
        let notes = files.appendingPathComponent("Weekend plans.md")
        try! "# Weekend plans\nCoffee, a walk, and a new playlist.\n".write(to: notes, atomically: true, encoding: .utf8)
        let brief = files.appendingPathComponent("Project brief.txt")
        try! "Make room for a little focus.\n".write(to: brief, atomically: true, encoding: .utf8)
        shelf.setPreviewItems([notes, brief], selectedIndex: 0)
        func profile(_ kinds: [NookWidgetKind]) {
            let p = NookProfile(id: UUID(), name: "Everyday", widgets: kinds)
            settings.profiles = [p]; settings.activeProfileID = p.id
        }
        func model(hardware: Bool = true, availableWidth: CGFloat = 1440) -> NotchViewModel {
            NotchViewModel(geometry: hardware ? NotchGeometry(width: 185, height: 32, isHardwareNotch: true) : .synthetic,
                availableWidth: availableWidth, settings: settings, shelf: shelf, nowPlaying: services.nowPlaying,
                powerMonitor: services.powerMonitor, timerService: timer, bluetoothMonitor: services.bluetooth,
                systemActivityMonitor: services.systemActivity, teleprompter: services.teleprompter)
        }
        func camera<V: View>(_ view: V) -> some View {
            view.overlay(alignment: .top) {
                UnevenRoundedRectangle(bottomLeadingRadius: 8, bottomTrailingRadius: 8).fill(.black).frame(width: 185, height: 32)
            }
        }
        for (index, name) in ["gold", "midnight", "everforest"].enumerated() {
            theme.reset()
            if name == "gold" {
                theme.customNotchHex = "#211A11"; theme.customAccentHex = "#D6AF63"
                theme.accentChoice = .custom; theme.setPreset(.custom, for: .notch)
                theme.notchThemeIntensity = 0.55
            } else { theme.setPreset(index == 1 ? .midnight : .forest, for: .notch) }
            var info = NowPlayingInfo()
            info.title = index == 0 ? "Mouthful of Diamonds" : index == 1 ? "I Melt With You" : "Catacombs"
            info.artist = index == 0 ? "Phantogram" : index == 1 ? "Modern English" : "Fog Lake"
            info.album = index == 0 ? "Eyelid Movies" : index == 1 ? "Pillow Lips" : "Tragedy Reel"
            info.isPlaying = true; info.elapsed = 74; info.duration = index == 2 ? 201 : 253
            info.artwork = NSImage(contentsOfFile: index == 0 ? "/private/tmp/macspaces-phantogram.jpg" : index == 1 ? "/private/tmp/macspaces-pillow-lips.jpg" : "/private/tmp/macspaces-fog-lake.jpg")!
            services.nowPlaying.setPreviewInfo(info)
            let overviewProfiles: [[NookWidgetKind]] = [
                [.media, .weather, .clock, .notes],
                [.pomodoro, .clipboard, .media],
                [.quickActions, .media, .timer, .weather],
            ]
            profile(overviewProfiles[index])
            let overview = model(); overview.state = .expanded
            render(camera(NotchContainerView(viewModel: overview)).frame(width: 1000, height: 620, alignment: .top),
                   size: CGSize(width: 1000, height: 620), to: output.appendingPathComponent("laptop-\(name).png"))
            overview.state = .collapsed
            render(camera(NotchContainerView(viewModel: overview)).frame(width: 1000, height: 620, alignment: .top),
                   size: CGSize(width: 1000, height: 620), to: output.appendingPathComponent("closed-\(name).png"))
            let detailProfiles: [[NookWidgetKind]] = [
                [.weather, .clock, .media, .clipboard],
                [.pomodoro, .media, .quickActions],
                [.notes, .media, .timer, .clock],
            ]
            profile(detailProfiles[index])
            let detail = model(); detail.state = .expanded
            render(camera(NotchContainerView(viewModel: detail)).frame(width: 800, height: 330, alignment: .top),
                   size: CGSize(width: 800, height: 330), to: output.appendingPathComponent("nook-\(name).png"))
            profile([.media, .weather, .clock])
            let tray = model(); tray.state = .expanded; tray.selectedTab = .tray
            render(camera(NotchContainerView(viewModel: tray)).frame(width: 800, height: 330, alignment: .top),
                   size: CGSize(width: 800, height: 330), to: output.appendingPathComponent("tray-\(name).png"))
        }
        for destination in SettingsDestination.allCases {
            SettingsNavigationModel.shared.selection = destination
            render(SettingsView().frame(width: 980, height: 760), size: CGSize(width: 980, height: 760),
                   to: output.appendingPathComponent("settings-\(destination.rawValue).png"))
        }
        for (name, kinds) in [("empty", [NookWidgetKind]()), ("one", [.weather]), ("pair", [.timer, .clock])] {
            profile(kinds)
            let nook = model(); nook.state = .expanded
            precondition(nook.expandedSize.width >= 625)
            precondition(nook.expandedHeaderTopInset == 9)
            let constrained = model(availableWidth: 520)
            precondition(constrained.expandedHeaderTopInset >= 40)
            render(camera(NotchContainerView(viewModel: nook)).frame(width: 740, height: 340),
                   size: CGSize(width: 740, height: 340), to: output.appendingPathComponent("regression-\(name).png"))
        }
        settings.showPowerLiveActivity = true
        settings.showTimerLiveActivity = false
        for preset in [ThemePreset.midnight, .forest, .frosted] {
            theme.setPreset(preset, for: .notch)
            settings.showMusicLiveActivity = false
            precondition(model(availableWidth: 520).collapsedSize.width <= 488)
            precondition(model(hardware: false, availableWidth: 520).collapsedSize.width <= 488)
            services.powerMonitor.setPreview(level: 74, externalPower: true, charging: false)
            let power = model(); power.state = .collapsed
            render(camera(NotchContainerView(viewModel: power)).frame(width: 800, height: 75, alignment: .top),
                size: CGSize(width: 800, height: 75), to: output.appendingPathComponent("power-\(preset.rawValue).png"))
            settings.showMusicLiveActivity = true
        }
        // Synthetic accessory fixtures keep personal names/addresses out of captures.
        theme.setPreset(.forest, for: .notch)
        services.powerMonitor.setPreview(level: 14, activity: false)
        let levels = BluetoothBatteryLevels(left: 80, right: 60, caseLevel: 1)
        services.bluetooth.setPreviewDevices([
            BluetoothDeviceSnapshot(id: "buds", name: "Studio AirPods Pro", batteryPercent: levels.primary, batteryLevels: levels),
            BluetoothDeviceSnapshot(id: "keyboard", name: "Desk keyboard", batteryPercent: nil),
        ])
        render(BatteryDetailsView(monitor: services.powerMonitor, bluetooth: services.bluetooth)
            .background(Color(nsColor: .windowBackgroundColor)), size: CGSize(width: 380, height: 400),
            to: output.appendingPathComponent("battery-device-details.png"))
        profile([.media, .battery, .clock])
        let batteryNook = model(); batteryNook.state = .expanded
        render(camera(NotchContainerView(viewModel: batteryNook)).frame(width: 800, height: 330, alignment: .top),
            size: CGSize(width: 800, height: 330), to: output.appendingPathComponent("battery-nook.png"))
        print("Nook-only native captures and layout checks passed: \(output.path)")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { NSApp.terminate(nil) }
        return true
    }
    private static func render<V: View>(_ view: V, size: CGSize, to url: URL) {
        let host = NSHostingView(rootView: view.environment(\.colorScheme, .dark))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .darkAqua)
        window.isOpaque = false; window.backgroundColor = .clear; window.contentView = host
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try! bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
#endif
