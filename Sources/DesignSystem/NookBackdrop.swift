import SwiftUI
import AppKit

/// The fill behind the open Nook and its dock. Solid themes paint their background;
/// Glass themes (`ThemeFamily.glassTint`) are a see-through pane: the desktop behind
/// is blurred (`glassBlurs`), then tinted (`glassTint`) so text stays readable. Clear
/// has neither, leaving only the content over the desktop. Callers draw the rim.
struct NookBackdrop<S: Shape>: View {
    let shape: S
    /// The closed notch stays solid so it blends with the camera housing.
    var allowsGlass = true
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        if allowsGlass, theme.family.glassTint == 0, !theme.family.glassBlurs {
            // Invisible, but not alpha 0: macOS sends clicks on fully transparent
            // pixels to the window behind, and the Nook must keep its hover and clicks.
            shape.fill(Color.black.opacity(0.01))
        } else if allowsGlass, let tint = theme.family.glassTint {
            let dark = theme.notch.colorScheme == .dark
            let blurs = theme.family.glassBlurs
            shape.fill(theme.notch.surface.opacity(tint))
                .background { if blurs { GlassPane(shape: shape, dark: dark) } }
                .overlay {
                    if blurs {
                    // A soft sheen from the top edge, as light catches a pane of glass.
                    GlassSheen(dark: dark).clipShape(shape)
                    }
                }
        } else {
            shape.fill(theme.notch.surface)
        }
    }
}

/// The same quiet top-edge highlight on live panes and Settings previews.
struct GlassSheen: View {
    let dark: Bool
    var body: some View {
        LinearGradient(colors: [.white.opacity(dark ? 0.08 : 0.22), .clear],
                       startPoint: .top, endPoint: .center)
    }
}

/// Liquid Glass from macOS 26; a behind-window blur before that.
private struct GlassPane<S: Shape>: View {
    let shape: S
    let dark: Bool

    var body: some View {
        if #available(macOS 26.0, *) {
            Color.clear.glassEffect(.clear, in: shape)
        } else {
            BlurBehindWindow(dark: dark).clipShape(shape)
        }
    }
}

private struct BlurBehindWindow: NSViewRepresentable {
    let dark: Bool

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        // The material follows the theme's light or dark look, not the system's.
        view.appearance = NSAppearance(named: dark ? .vibrantDark : .vibrantLight)
    }
}
