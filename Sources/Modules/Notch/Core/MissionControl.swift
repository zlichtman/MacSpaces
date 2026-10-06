import AppKit
import CoreGraphics

/// Whether Mission Control (or App Exposé) is showing, so reaching for the
/// Spaces bar at the top of the screen doesn't open the Nook. macOS has no
/// public signal, so this looks for the full-screen overlay windows it adds:
/// WindowManager draws them on current macOS, the Dock on earlier releases.
/// Reading window owners, layers and bounds needs no permission.
enum MissionControl {
    static var isActive: Bool {
        guard let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                       kCGNullWindowID) as? [[String: Any]] else { return false }
        let screens = NSScreen.screens.map(\.frame.size)
        return windows.contains { window in
            guard let owner = window[kCGWindowOwnerName as String] as? String,
                  let layer = window[kCGWindowLayer as String] as? Int,
                  let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = bounds["Width"], let height = bounds["Height"] else { return false }
            let fullScreen = screens.contains { $0.width == width && $0.height == height }
            switch owner {
            // Stage Manager also belongs to WindowManager, but never covers the whole screen.
            case "WindowManager": return fullScreen && layer >= 14
            // The Dock keeps a full-screen window at its own level (20); the overlay sits just below it.
            case "Dock": return fullScreen && (14...19).contains(layer)
            default: return false
            }
        }
    }
}
