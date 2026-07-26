import SwiftUI

// Small views rendered in the strip either side of the hardware notch while collapsed.

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
        Image(systemName: monitor.activitySystemImage)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(monitor.isLowBatteryActivity ? Color.red : theme.notch.accent)
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
    }
}
