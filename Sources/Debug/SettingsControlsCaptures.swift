#if DEBUG
import AppKit
import SwiftUI

/// The `settings-controls` scope: every Settings page in light and dark, plus the Custom
/// drawer with and without a picture and the Terminal drawer searched, so the shared
/// controls (`SettingsControls.swift`) can be reviewed together. Synthetic data only, in
/// the harness's own defaults. Each capture reports how much of it is text-coloured, so a
/// render that lost its text shows up in the log.
@MainActor enum SettingsControlsCaptures {
    static func capture(to directory: URL) {
        let theme = ThemeStore.shared
        let settings = NookSettings.shared
        theme.selectFamily(.macspaces)
        settings.widgets = [.media, .clock, .timer]
        if settings.profiles.count < 2 {
            let first = settings.activeProfileID
            settings.addProfile(named: "Work")
            settings.activeProfileID = first
        }
        settings.hiddenInApps = ["com.apple.TextEdit"]
        ClipboardPreferences.shared.filter.ignoredPatterns = ["^\\d{6}$"]
        GhosttyLibrary.shared.load()
        settle { !GhosttyLibrary.shared.themes.isEmpty }

        let pages: [(SettingsDestination, CGFloat)] = [
            (.general, 1350), (.appearance, 1050), (.permissions, 1000), (.widgets, 1500),
            (.apps, 1250), (.activities, 1350), (.files, 900), (.clipboard, 1900)
        ]
        for dark in [false, true] {
            setSystemDark(dark)
            let suffix = dark ? "dark" : "light"
            NookThemePicker.initiallyOpen = []
            for (page, height) in pages {
                SettingsNavigationModel.shared.selection = page
                render(SettingsView(), name: "\(page.rawValue)-\(suffix)", height: height, dark: dark, directory: directory)
            }
            // The Terminal drawer with a search typed, then Custom's Picture with and without a picture.
            SettingsNavigationModel.shared.selection = .appearance
            NookThemePicker.initiallyOpen = [.terminal]
            TerminalThemeList.initialQuery = "rose"
            render(SettingsView(), name: "appearance-terminal-\(suffix)", height: 1100, dark: dark, directory: directory)
            TerminalThemeList.initialQuery = ""
            NookThemePicker.initiallyOpen = [.custom]
            theme.selectCustomStyle(.image)
            theme.selectFamily(.custom)
            render(SettingsView(), name: "appearance-custom-empty-\(suffix)", height: 1100, dark: dark, directory: directory)
            let picture = directory.appendingPathComponent("qa-picture.png")
            writePicture(to: picture)
            if let result = CustomTheme.importImage(from: picture) {
                theme.setCustomPicture(result.name, background: result.background, accent: result.accent)
            }
            CustomBackgroundImage.shared.prepare()
            settle { CustomBackgroundImage.shared.image != nil }
            render(SettingsView(), name: "appearance-custom-picture-\(suffix)", height: 1100, dark: dark, directory: directory)
            theme.removeCustomPicture()
            try? FileManager.default.removeItem(at: picture)
            theme.selectFamily(.macspaces)
            NookThemePicker.initiallyOpen = []
        }
        // One theme with a coloured accent, light and dark, for the primary button's text.
        theme.selectFamily(.everforest)
        for dark in [false, true] {
            setSystemDark(dark)
            SettingsNavigationModel.shared.selection = .widgets
            render(SettingsView(), name: "widgets-everforest-\(dark ? "dark" : "light")", height: 1500, dark: dark, directory: directory)
        }
        theme.selectFamily(.macspaces)
        try? FileManager.default.removeItem(at: CustomTheme.imageFolder)
        print("Settings controls captures written")
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    /// Settings follows the system's light or dark appearance (`ThemeStore.systemIsDark`).
    private static func setSystemDark(_ dark: Bool) {
        NSApp.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        settle { ThemeStore.shared.settingsScheme == (dark ? .dark : .light) }
    }

    private static func settle(timeout: TimeInterval = 5, _ done: () -> Bool) {
        let end = Date().addingTimeInterval(timeout)
        while !done(), Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    }

    private static func render<V: View>(_ view: V, name: String, height: CGFloat, dark: Bool, directory: URL) {
        let size = NSSize(width: 980, height: height)
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(1.2))
        host.layoutSubtreeIfNeeded(); host.displayIfNeeded()
        guard let bitmap = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return }
        host.cacheDisplay(in: host.bounds, to: bitmap)
        try? bitmap.representation(using: .png, properties: [:])?.write(to: directory.appendingPathComponent(name + ".png"))
        window.contentView = nil
        print("settings-controls \(name): text-coloured pixels \(String(format: "%.2f", inkShare(bitmap, dark: dark) * 100))%")
    }

    /// The share of sampled pixels close to the text colour (near black in light, near
    /// white in dark): a page that rendered without text comes out near zero.
    private static func inkShare(_ bitmap: NSBitmapImageRep, dark: Bool) -> Double {
        var ink = 0, total = 0
        for y in stride(from: 0, to: bitmap.pixelsHigh, by: 3) {
            for x in stride(from: 0, to: bitmap.pixelsWide, by: 3) {
                guard let colour = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                let level = (colour.redComponent + colour.greenComponent + colour.blueComponent) / 3
                total += 1
                if dark ? level > 0.85 : level < 0.15 { ink += 1 }
            }
        }
        return total == 0 ? 0 : Double(ink) / Double(total)
    }

    /// A made-up gradient with a sun; never a real photo.
    private static func writePicture(to url: URL) {
        let image = NSImage(size: NSSize(width: 1200, height: 800), flipped: false) { rect in
            NSGradient(colors: [NSColor(srgbRed: 0.98, green: 0.62, blue: 0.42, alpha: 1),
                                NSColor(srgbRed: 0.20, green: 0.14, blue: 0.36, alpha: 1)])?.draw(in: rect, angle: -90)
            NSColor(srgbRed: 1, green: 0.85, blue: 0.55, alpha: 1).setFill()
            NSBezierPath(ovalIn: NSRect(x: 800, y: 420, width: 180, height: 180)).fill()
            return true
        }
        if let tiff = image.tiffRepresentation, let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
}
#endif
