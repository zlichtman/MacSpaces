import SwiftUI

// Small views rendered in the strip either side of the hardware notch while collapsed.

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

/// A quiet level track for volume and brightness. It communicates magnitude
/// faster than a percentage alone and avoids animated waveform noise.
struct NotchActivityLevelView: View {
    let level: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.14))
                Capsule()
                    .fill(tint.opacity(0.92))
                    .frame(
                        width: max(
                            2,
                            proxy.size.width * min(max(level, 0), 1)
                        )
                    )
            }
        }
        .frame(width: 25, height: 3)
    }
}

struct SystemActivityValueView: View {
    let activity: SystemLiveActivity
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            if let level = activity.level {
                NotchActivityLevelView(level: level, tint: tint)
            }
            Text(activity.label)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.84)
        }
        .foregroundStyle(tint)
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .trailing)
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

/// Rounded album artwork thumbnail (left side of the notch while music plays).
struct MusicActivityArtworkView: View {
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Group {
            if let artwork = nowPlaying.info.artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 5).fill(theme.notch.control)
                    Image(systemName: "music.note")
                        .font(.system(size: 9))
                        .foregroundStyle(theme.notch.accent)
                }
            }
        }
        .frame(width: 18, height: 18)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay {
            RoundedRectangle(cornerRadius: 5)
                .strokeBorder(theme.notch.accent.opacity(0.28), lineWidth: 0.75)
        }
    }
}

/// The battery beside the notch: just the gauge on one side and the level on the
/// other, in the same colour (green while charging, orange when low), so the
/// notch grows no wider than any other activity.
struct PowerActivityIconView: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject private var theme = ThemeStore.shared
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            BatteryGaugeView(level: monitor.hasReading ? monitor.batteryLevel : nil,
                             charging: monitor.isCharging, tint: PowerActivityLabelView.tint(monitor, accent: theme.notch.accent),
                             width: 24)
            if compact {
                Text("\(monitor.batteryLevel)%")
                    .font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(PowerActivityLabelView.tint(monitor, accent: theme.notch.accent))
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(monitor.activityLabel)
    }
}

struct PowerActivityLabelView: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject private var theme = ThemeStore.shared

    static func tint(_ monitor: PowerSourceMonitor, accent: Color) -> Color {
        monitor.isLowBatteryActivity ? .orange : monitor.isCharging ? .green : accent
    }

    var body: some View {
        Text("\(monitor.batteryLevel)%")
            .font(.system(size: 12, weight: .semibold, design: .rounded)).monospacedDigit()
            .foregroundStyle(Self.tint(monitor, accent: theme.notch.accent))
            .lineLimit(1).fixedSize()
            .accessibilityLabel(monitor.activityLabel)
    }
}
