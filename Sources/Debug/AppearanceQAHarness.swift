#if DEBUG
import AppKit
import SwiftUI

@MainActor enum AppearanceQAHarness {
    static func captureIfRequested() -> Bool {
        guard let output = ProcessInfo.processInfo.environment["MACSPACES_APPEARANCE_QA"] else { return false }
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.AppearanceQA")
        InteractionRegressionChecks.run()
        DeviceRegressionChecks.run()
        let directory = URL(fileURLWithPath: output, isDirectory: true)
        try! FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for family in Array(ThemeFamily.ownTerminal.prefix(5)) + [.catppuccin, .everforest] {
            // The Settings window follows the system, so capture it under both.
            for (mode, name) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                let theme = ThemeStore.shared
                theme.selectFamily(family); NSApp.appearance = NSAppearance(named: name)
                RunLoop.current.run(until: Date().addingTimeInterval(0.05))
                for destination in [SettingsDestination.appearance, .general] {
                    SettingsNavigationModel.shared.selection = destination
                    let view = SettingsView()
                        .frame(width: 980, height: 1000, alignment: .top)
                        .environment(\.colorScheme, theme.settingsScheme)
                    let host = NSHostingView(rootView: view)
                    host.frame = NSRect(x: 0, y: 0, width: 980, height: 1000)
                    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = host
                    window.appearance = NSAppearance(named: name)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(family.rawValue)-\(mode)-\(destination.rawValue).png"))
                }
            }
        }
        print("Appearance captures complete")
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }
}
#endif
