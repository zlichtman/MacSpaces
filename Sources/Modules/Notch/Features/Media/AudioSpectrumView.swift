import SwiftUI

/// Playback status only. A real audio visualizer belongs to a measured audio
/// adapter; synthetic moving bars must not imply measured output.
struct AudioSpectrumView: View {
    var isPlaying: Bool
    @ObservedObject private var theme = ThemeStore.shared
    var body: some View {
        Image(systemName: isPlaying ? "waveform" : "pause.fill")
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(theme.notch.accent.opacity(isPlaying ? 1 : 0.45))
            .frame(width: 26, height: 18)
            .accessibilityLabel(isPlaying ? "Audio playing" : "Audio paused")
    }
}
