import SwiftUI

// Small views rendered in the strip either side of the hardware notch while collapsed.

extension ThemeInks {
    /// A bubble's colour beside the closed notch: the theme's, or with Theme off its own.
    /// Music, timers and agents take theirs from what they show, so this is their fallback.
    @MainActor static func bubbleColour(_ popOut: NotchPopOut, _ theme: ThemeStore) -> Color {
        if NookSettings.shared.followsTheme(popOut) { return bubbleAccent(theme) }
        switch popOut {
        case .music, .agents: return theme.notch.accent
        case .timer: return TimerService.palette[0]
        case .keepAwake: return .orange
        case .meeting: return .blue
        case .screenshot: return .cyan
        case .pasteQueue: return .yellow
        case .power: return .green
        case .system: return .purple
        case .spaces: return .mint
        }
    }
}

/// Shared visual language for short-lived device and system feedback. The
/// subtle circular plate remains legible on every palette without turning the
/// closed Nook into a row of bright Control Center buttons.
struct NotchActivityGlyphView: View {
    let systemImage: String
    let tint: Color

    var body: some View {
        Image(systemName: systemImage)
            .font(.system(size: 9.5, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: 21, height: 21)
            .background {
                Circle()
                    .fill(tint.opacity(0.13))
                    .overlay {
                        Circle()
                            .strokeBorder(.white.opacity(0.09), lineWidth: 0.6)
                    }
            }
    }
}

/// A consistently sized battery silhouette with a real level, shared by the
/// compact activity, widget and accessory details. Unknown stays unfilled.
struct BatteryGaugeView: View {
    let level: Int?
    var charging = false
    let tint: Color
    var width: CGFloat = 28

    var body: some View {
        HStack(spacing: 1.5) {
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).strokeBorder(.primary.opacity(0.55), lineWidth: 1.2)
                if let level {
                    RoundedRectangle(cornerRadius: 1.6)
                        .fill(tint)
                        .frame(width: level > 0 ? max(1.6, (width - 9) * CGFloat(min(100, level)) / 100) : 0)
                        .padding(2.5)
                }
                if charging {
                    Image(systemName: "bolt.fill")
                        .font(.system(size: width * 0.3, weight: .bold))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity)
                }
            }
            RoundedRectangle(cornerRadius: 1).fill(.primary.opacity(0.55))
                .frame(width: 2, height: width * 0.19)
        }
        .frame(width: width, height: width * 0.47)
        .accessibilityHidden(true)
    }
}

/// The battery beside the notch: the gauge on one side and the level on the other,
/// in one colour (`ThemeInks.bubbleColour`, orange for a low or draining notice), so the
/// notch grows no wider than any other activity. The paired layout shows both side by
/// side. While a notice shows, the gauge follows the committed state in place.
struct PowerActivityGaugeView: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject private var theme = ThemeStore.shared
    @ObservedObject private var settings = NookSettings.shared

    var body: some View {
        BatteryGaugeView(level: monitor.batteryLevel, charging: monitor.state == .charging,
                         tint: PowerPalette.noticeTint(monitor, accent: ThemeInks.bubbleColour(.power, theme)), width: 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(BatteryStatusText.word(monitor.state)), \(monitor.batteryLevel)%")
    }
}
