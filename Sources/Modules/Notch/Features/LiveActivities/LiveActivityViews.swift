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

struct BluetoothActivityIdentityView: View {
    @ObservedObject var monitor: BluetoothMonitor
    @ObservedObject private var theme = ThemeStore.shared
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: monitor.activitySystemImage)
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(theme.notch.accent)
                .frame(width: 27)
            VStack(alignment: .leading, spacing: 1) {
                Text(monitor.lastChangedDeviceName ?? "Bluetooth device")
                    .font(.system(size: 11, weight: .semibold))
                    .lineLimit(1).truncationMode(.middle)
                if compact {
                    HStack(spacing: 6) {
                        Text(monitor.activityState.title)
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                        if let level = monitor.activityBatteryPercent {
                            Text("\(level)%").font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(level <= 20 ? Color.orange : .primary)
                                .monospacedDigit().fixedSize()
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help("\(monitor.activityLabel) · \(monitor.activityState.title)")
        .accessibilityElement(children: .combine)
    }
}

struct BluetoothActivityValueView: View {
    @ObservedObject var monitor: BluetoothMonitor
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(spacing: 1) {
            if let level = monitor.activityBatteryPercent {
                HStack(spacing: 7) {
                    BatteryGaugeView(level: level, tint: level <= 20 ? .orange : theme.notch.accent)
                    Text("\(level)%").font(.system(size: 12, weight: .semibold)).monospacedDigit()
                }
            }
            Text(monitor.activityState.title)
                .font(.system(size: monitor.activityBatteryPercent == nil ? 11 : 9, weight: .medium))
                .foregroundStyle(monitor.activityState == .disconnected ? .primary : .secondary)
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .accessibilityLabel("\(monitor.activityLabel), \(monitor.activityState.title)")
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

struct PowerActivityIconView: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject private var theme = ThemeStore.shared
    var compact = false

    var body: some View {
        HStack(spacing: 8) {
            BatteryGaugeView(level: monitor.hasReading ? monitor.batteryLevel : nil,
                charging: monitor.isCharging,
                tint: monitor.isLowBatteryActivity ? .orange : theme.notch.accent, width: 30)
            VStack(alignment: .leading, spacing: 1) {
                Text(compact ? "\(monitor.batteryLevel)%" : "Mac battery")
                    .font(.system(size: 11, weight: .semibold)).monospacedDigit()
                if compact {
                    Text(monitor.isLowBatteryActivity ? "Low battery" : monitor.statusLabel)
                        .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(monitor.activityLabel)
    }
}

struct PowerActivityLabelView: View {
    @ObservedObject var monitor: PowerSourceMonitor
    var body: some View {
        VStack(spacing: 1) {
            Text("\(monitor.batteryLevel)%")
                .font(.system(size: 13, weight: .semibold)).monospacedDigit()
                .foregroundStyle(monitor.isLowBatteryActivity ? Color.orange : .primary)
            Text(monitor.isLowBatteryActivity ? "Low battery" : monitor.statusLabel)
                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
        }
        .lineLimit(1).frame(maxWidth: .infinity)
        .accessibilityLabel(monitor.activityLabel)
    }
}
