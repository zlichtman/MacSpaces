import AppKit
import ApplicationServices

/// Whether an app appears in the Dock says nothing about its normal windows.
enum WindowDiscovery {
    static func includesApp(policy: NSApplication.ActivationPolicy, isOwnApp: Bool) -> Bool {
        !isOwnApp && policy != .prohibited
    }
    /// A standard window, or one with no subrole that still has a title bar's close or minimize
    /// button: apps' popups, menus and panels often report no subrole but have neither.
    static func isNormalWindow(role: String?, subrole: String?, hasTitleBarButton: Bool = true) -> Bool {
        guard role == (kAXWindowRole as String) else { return false }
        if subrole == (kAXStandardWindowSubrole as String) { return true }
        return (subrole == nil || subrole == (kAXUnknownSubrole as String)) && hasTitleBarButton
    }
    /// Smaller than this, a window is a palette, a mini player or a popup, not one to give a column.
    static let smallestTile = CGSize(width: 260, height: 160)
    static func isTooSmall(_ size: CGSize) -> Bool { size.width < smallestTile.width || size.height < smallestTile.height }
    static func visibleMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        // Independent CG and AX reads may differ slightly during resizing or rounding.
        // Stay conservative: do not admit arbitrary overlapping windows on other Spaces.
        abs(lhs.minX - rhs.minX) <= 8 && abs(lhs.minY - rhs.minY) <= 8
            && abs(lhs.width - rhs.width) <= 8 && abs(lhs.height - rhs.height) <= 8
    }
}
