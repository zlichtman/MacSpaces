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

struct BluetoothActivityValueView: View {
    @ObservedObject var monitor: BluetoothMonitor
    @ObservedObject private var theme = ThemeStore.shared

    private var stateColor: Color {
        switch monitor.activityState {
        case .connected: return .green
        case .disconnected: return .red
        case .battery: return theme.notch.accent
        }
    }

    private var stateLabel: String {
        switch monitor.activityState {
        case .connected: return "Connected"
        case .disconnected: return "Disconnected"
        case .battery: return "Battery"
        }
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 0) {
            Text(monitor.lastChangedDeviceName ?? "Bluetooth device")
                .font(.system(size: 8.5, weight: .semibold))
                .foregroundStyle(.primary.opacity(0.92))
                .lineLimit(1)
                .truncationMode(.middle)

            HStack(spacing: 3) {
                Circle()
                    .fill(stateColor)
                    .frame(width: 4, height: 4)
                Text(stateLabel)
                if let battery = monitor.activityBatteryPercent,
                   monitor.activityState != .disconnected {
                    Text("·")
                    Image(systemName: batterySymbol(for: battery))
                    Text("\(battery)%")
                        .monospacedDigit()
                }
            }
            .font(.system(size: 7.5, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .lineLimit(1)
        }
        .padding(.trailing, 10)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func batterySymbol(for level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
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

/// Charging bolt / battery icon (left side of the notch after power changes).
struct PowerActivityIconView: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        NotchActivityGlyphView(
            systemImage: monitor.activitySystemImage,
            tint: monitor.isLowBatteryActivity ? .red : theme.notch.accent
        )
    }
}

/// Battery percentage label (right side of the notch after power changes).
struct PowerActivityLabelView: View {
    @ObservedObject var monitor: PowerSourceMonitor
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Text(monitor.activityLabel)
            .font(.system(size: 9, weight: .semibold, design: .rounded))
            .foregroundStyle(monitor.isLowBatteryActivity ? Color.red : theme.notch.accent)
            .lineLimit(1)
            .minimumScaleFactor(0.84)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
