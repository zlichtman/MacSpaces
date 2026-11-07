import AppKit
import ApplicationServices

/// Whether an app appears in the Dock says nothing about its normal windows.
enum WindowDiscovery {
    static func includesApp(policy: NSApplication.ActivationPolicy, isOwnApp: Bool) -> Bool {
        !isOwnApp && policy != .prohibited
    }
    static func isNormalWindow(role: String?, subrole: String?) -> Bool {
        guard role == (kAXWindowRole as String) else { return false }
        return subrole == nil || subrole == (kAXUnknownSubrole as String)
            || subrole == (kAXStandardWindowSubrole as String)
    }
    static func visibleMatch(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        // Independent CG and AX reads may differ slightly during resizing or rounding.
        // Stay conservative: do not admit arbitrary overlapping windows on other Spaces.
        abs(lhs.minX - rhs.minX) <= 8 && abs(lhs.minY - rhs.minY) <= 8
            && abs(lhs.width - rhs.width) <= 8 && abs(lhs.height - rhs.height) <= 8
    }
}
