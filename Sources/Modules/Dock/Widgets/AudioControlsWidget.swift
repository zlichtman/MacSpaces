import AppKit
import SwiftUI

/// Compact master control backed by a full per-app mixer popover.
struct AudioControlsWidget: View {
    let isVertical: Bool
    @ObservedObject private var mixer = AppServices.shared.audioMixer
    @ObservedObject private var theme = ThemeStore.shared
    @State private var showingMixer = false

    var body: some View {
        Button {
            showingMixer.toggle()
        } label: {
            if isVertical {
                verticalSummary
            } else {
                horizontalSummary
            }
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showingMixer, arrowEdge: .top) {
            AudioMixerPanel(mixer: mixer)
        }
        .onAppear { mixer.start() }
        .help("Open the app volume mixer")
    }

    private var horizontalSummary: some View {
        HStack(spacing: 10) {
            activeIcons

            VStack(alignment: .leading, spacing: 2) {
                Text(mixer.outputName)
                    .font(.system(size: 10, weight: .semibold))
                    .lineLimit(1)
                Text(activityLabel)
                    .font(.system(size: 8.5, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 4)
            MixerLevelBars(
                level: mixer.sessions.map(\.level).max() ?? 0,
                tint: theme.dock.accent
            )
            Image(systemName: masterSymbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(mixer.masterMuted ? .secondary : theme.dock.accent)
            Text("\(Int((mixer.masterVolume * 100).rounded()))")
                .font(.system(size: 9, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(width: 22, alignment: .trailing)
        }
        .padding(.horizontal, 11)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var verticalSummary: some View {
        VStack(spacing: 7) {
            activeIcons
            MixerLevelBars(
                level: mixer.sessions.map(\.level).max() ?? 0,
                tint: theme.dock.accent
            )
            HStack(spacing: 5) {
                Image(systemName: masterSymbol)
                Text("\(Int((mixer.masterVolume * 100).rounded()))")
                    .monospacedDigit()
            }
            .font(.system(size: 9, weight: .bold, design: .rounded))
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var activeIcons: some View {
        HStack(spacing: -7) {
            ForEach(Array(mixer.sessions.filter(\.isProducingAudio).prefix(3))) { session in
                Group {
                    if let icon = session.icon {
                        Image(nsImage: icon)
                            .resizable()
                    } else {
                        Image(systemName: "waveform")
                            .resizable()
                            .scaledToFit()
                            .padding(6)
                    }
                }
                .frame(width: 27, height: 27)
                .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .strokeBorder(theme.dock.border.opacity(0.75), lineWidth: 1)
                }
            }

            if mixer.activeAppCount == 0 {
                Image(systemName: "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(theme.dock.accent)
                    .frame(width: 27, height: 27)
                    .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 7))
            }
        }
    }

    private var activityLabel: String {
        switch mixer.activeAppCount {
        case 0: return "No apps playing"
        case 1: return "1 app playing"
        default: return "\(mixer.activeAppCount) apps playing"
        }
    }

    private var masterSymbol: String {
        if mixer.masterMuted { return "speaker.slash.fill" }
        switch mixer.masterVolume {
        case ...0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

struct AudioMixerPanel: View {
    @ObservedObject var mixer: AudioMixerService
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)

            Divider()

            masterControl
                .padding(14)

            Divider()

            HStack {
                Text("APPS")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("Settings are remembered per app")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            if mixer.sessions.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 7) {
                        ForEach(mixer.sessions) { session in
                            AppVolumeRow(session: session, mixer: mixer)
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
                .frame(maxHeight: 340)
            }

            if let error = mixer.engineError {
                mixerError(error)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
            }
        }
        .frame(width: 430)
        .background {
            ZStack {
                VisualEffectView(material: .popover)
                theme.dock.surface.opacity(0.72)
            }
        }
        .environment(\.colorScheme, theme.dock.colorScheme)
        .tint(theme.dock.accent)
    }

    private var header: some View {
        HStack(spacing: 10) {
            Image(systemName: "slider.horizontal.3")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(theme.dock.accent)
                .frame(width: 28, height: 28)
                .background(theme.dock.accent.opacity(0.13), in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("App Mixer")
                    .font(.system(size: 14, weight: .semibold))
                Text("Independent volume without changing the app")
                    .font(.system(size: 9.5, weight: .medium))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if mixer.isMixerRunning {
                Label("LIVE", systemImage: "waveform")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(theme.dock.accent)
            }
        }
    }

    private var masterControl: some View {
        HStack(spacing: 11) {
            Button { mixer.toggleMasterMute() } label: {
                Image(systemName: mixer.masterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(mixer.masterMuted ? .secondary : theme.dock.accent)

            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(mixer.outputName)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    Spacer()
                    Text("\(Int((mixer.masterVolume * 100).rounded()))%")
                        .font(.system(size: 10, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: Binding(
                        get: { mixer.masterVolume },
                        set: mixer.setMasterVolume
                    ),
                    in: 0...1
                )
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "speaker.badge.exclamationmark")
                .font(.system(size: 21, weight: .medium))
                .foregroundStyle(theme.dock.accent)
            Text("Play audio in an app")
                .font(.system(size: 12, weight: .semibold))
            Text("It will appear here automatically.")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func mixerError(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "waveform.badge.exclamationmark")
                .foregroundStyle(.orange)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 5) {
                Text(message)
                    .font(.system(size: 10, weight: .medium))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 10) {
                    Button("Try Again") { mixer.retryMixer() }
                    Button("Audio Recording Settings") {
                        guard let url = URL(
                            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AudioCapture"
                        ) else { return }
                        NSWorkspace.shared.open(url)
                    }
                }
                .font(.system(size: 9.5, weight: .semibold))
                .buttonStyle(.link)
            }
        }
        .padding(10)
        .background(.orange.opacity(0.09), in: RoundedRectangle(cornerRadius: 10))
    }
}

private struct AppVolumeRow: View {
    let session: AppAudioSession
    @ObservedObject var mixer: AudioMixerService
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        HStack(spacing: 10) {
            ZStack(alignment: .bottomLeading) {
                Group {
                    if let icon = session.icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: "app.dashed")
                            .resizable()
                            .scaledToFit()
                            .padding(7)
                    }
                }
                .frame(width: 32, height: 32)

                Circle()
                    .fill(session.isProducingAudio ? theme.dock.accent : Color.secondary)
                    .frame(width: 7, height: 7)
                    .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 1))
            }

            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(session.name)
                        .font(.system(size: 11, weight: .semibold))
                        .lineLimit(1)
                    MixerLevelBars(
                        level: session.level,
                        tint: session.isManaged ? theme.dock.accent : .secondary,
                        compact: true
                    )
                    Spacer()
                    if session.isManaged {
                        Text("CUSTOM")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .foregroundStyle(theme.dock.accent)
                    }
                }

                HStack(spacing: 8) {
                    Button { mixer.toggleMute(for: session.id) } label: {
                        Image(systemName: session.isMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                            .font(.system(size: 10, weight: .semibold))
                            .frame(width: 20, height: 18)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(session.isMuted ? .secondary : theme.dock.accent)

                    Slider(
                        value: Binding(
                            get: {
                                mixer.sessions.first(where: { $0.id == session.id })?.volume
                                    ?? session.volume
                            },
                            set: { mixer.setVolume($0, for: session.id) }
                        ),
                        in: 0...1
                    )

                    Text("\(Int((session.volume * 100).rounded()))%")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: 34, alignment: .trailing)

                    Button { mixer.reset(session.id) } label: {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .opacity(session.isManaged ? 1 : 0.28)
                    .disabled(!session.isManaged)
                    .help("Reset to system volume")
                }
            }
        }
        .padding(9)
        .background(theme.dock.control.opacity(0.62), in: RoundedRectangle(cornerRadius: 11))
        .overlay {
            RoundedRectangle(cornerRadius: 11)
                .strokeBorder(
                    session.isManaged
                        ? theme.dock.accent.opacity(0.34)
                        : theme.dock.border.opacity(0.45),
                    lineWidth: 0.8
                )
        }
    }
}

private struct MixerLevelBars: View {
    let level: Double
    let tint: Color
    var compact = false

    private let multipliers: [Double] = [0.44, 0.78, 1, 0.64]

    var body: some View {
        HStack(alignment: .center, spacing: compact ? 1.5 : 2) {
            ForEach(Array(multipliers.enumerated()), id: \.offset) { _, multiplier in
                Capsule()
                    .fill(tint.opacity(level > 0.03 ? 1 : 0.34))
                    .frame(
                        width: compact ? 2 : 2.5,
                        height: max(
                            compact ? 3 : 4,
                            (compact ? 11 : 16) * max(0.12, level) * multiplier
                        )
                    )
            }
        }
        .frame(width: compact ? 14 : 18, height: compact ? 12 : 18)
        .animation(.linear(duration: 0.1), value: level)
    }
}
