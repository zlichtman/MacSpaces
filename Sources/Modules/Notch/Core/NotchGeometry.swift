import AppKit

/// Describes the physical (or synthetic) notch area of a screen.
struct NotchGeometry: Equatable {
    /// Width of the hardware notch, or a synthetic width on notchless screens.
    var width: CGFloat
    /// Height of the hardware notch (== menu bar area height), or a synthetic height.
    var height: CGFloat
    /// Whether the screen actually has a hardware notch.
    var isHardwareNotch: Bool

    /// Fallback pill shown on external / notchless displays.
    static let synthetic = NotchGeometry(width: 156, height: 30, isHardwareNotch: false)

    static func detect(on screen: NSScreen) -> NotchGeometry {
        guard screen.safeAreaInsets.top > 0 else {
            // A synthetic resting pill scales gently by display class without
            // becoming a wide empty bar on large external displays.
            let width: CGFloat
            switch screen.frame.width {
            case ..<1500: width = 144
            case ..<1900: width = 156
            default: width = 168
            }
            return NotchGeometry(width: width, height: 30, isHardwareNotch: false)
        }

        // The notch spans the gap between the two auxiliary top areas.
        if let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            let width = max(120, screen.frame.width - left.width - right.width)
            return NotchGeometry(width: width,
                                 height: screen.safeAreaInsets.top,
                                 isHardwareNotch: true)
        }

        return NotchGeometry(width: 185,
                             height: screen.safeAreaInsets.top,
                             isHardwareNotch: true)
    }
}
