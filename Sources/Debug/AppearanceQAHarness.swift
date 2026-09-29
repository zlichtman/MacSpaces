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
        for family in ThemeFamily.signature + [.catppuccin, .everforest] {
            for mode in [AppearanceMode.light, .dark] {
                let theme = ThemeStore.shared
                theme.selectFamily(family); theme.appearanceMode = mode
                for destination in [SettingsDestination.appearance, .general] {
                    SettingsNavigationModel.shared.selection = destination
                    let view = SettingsView()
                        .frame(width: 980, height: 1000, alignment: .top)
                        .environment(\.colorScheme, theme.resolvedScheme)
                    let host = NSHostingView(rootView: view)
                    host.frame = NSRect(x: 0, y: 0, width: 980, height: 1000)
                    let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                    window.contentView = host
                    window.appearance = NSAppearance(named: mode == .dark ? .darkAqua : .aqua)
                    host.layoutSubtreeIfNeeded()
                    RunLoop.current.run(until: Date().addingTimeInterval(0.2))
                    host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
                    let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds)!
                    host.cacheDisplay(in: host.bounds, to: bitmap)
                    try! bitmap.representation(using: .png, properties: [:])!.write(to: directory.appendingPathComponent("\(family.rawValue)-\(mode.rawValue)-\(destination.rawValue).png"))
                }
            }
        }
        print("Appearance captures complete")
        DispatchQueue.main.async { NSApp.terminate(nil) }
        return true
    }
}
#endif
