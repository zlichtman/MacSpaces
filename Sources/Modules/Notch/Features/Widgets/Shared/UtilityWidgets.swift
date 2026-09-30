import SwiftUI

/// One tap keeps the Mac awake; the chips choose how long before starting.
struct KeepAwakeWidget: View {
    @ObservedObject var service: KeepAwakeService
    var compact = false
    @ObservedObject private var theme = ThemeStore.shared
    @State private var minutes = 60
    @State private var displayToo = false

    private static let durations: [(label: String, minutes: Int)] = [("15m", 15), ("1h", 60), ("2h", 120), ("∞", 0)]

    var body: some View {
        if compact {
            HStack(spacing: 8) {
                toggleButton(size: 30)
                VStack(alignment: .leading, spacing: 1) {
                    Text(service.isActive ? "Awake" : "Sleep allowed")
                        .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                    statusText.font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 9) {
                toggleButton(size: 48)
                VStack(spacing: 2) {
                    Text(service.isActive ? (displayToo ? "Mac and display awake" : "Mac awake") : "Sleep allowed")
                        .font(.system(size: 12, weight: .semibold))
                    statusText.font(.system(size: 10)).foregroundStyle(.secondary).monospacedDigit()
                }
                if !service.isActive {
                    HStack(spacing: 5) {
                        ForEach(Self.durations, id: \.minutes) { option in
                            Button(option.label) { minutes = option.minutes }
                                .buttonStyle(WidgetChipStyle(prominent: minutes == option.minutes, height: 22))
                                .help(option.minutes == 0 ? "Until you stop it" : "For \(option.label)")
                        }
                    }
                    Toggle("Keep display on", isOn: $displayToo)
                        .toggleStyle(.checkbox).controlSize(.small).font(.system(size: 10))
                }
                if let error = service.error {
                    Text(error).font(.caption2).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 8)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func toggleButton(size: CGFloat) -> some View {
        Button {
            if service.isActive { service.stop() }
            else { service.start(mode: displayToo ? .display : .system, minutes: minutes == 0 ? nil : minutes) }
        } label: {
            Image(systemName: service.isActive ? "cup.and.saucer.fill" : "cup.and.saucer")
                .font(.system(size: size * 0.4, weight: .semibold))
                .foregroundStyle(service.isActive ? Color.black.opacity(0.82) : Color.primary)
                .frame(width: size, height: size)
                .background(service.isActive ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(Color.primary.opacity(0.09)),
                            in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .help(service.isActive ? "Allow sleep" : "Keep awake")
        .accessibilityLabel(service.isActive ? "Allow sleep" : "Keep Mac awake")
    }

    @ViewBuilder
    private var statusText: some View {
        if let end = service.expiresAt {
            Text(end, style: .timer)
        } else if service.isActive {
            Text("Until you stop it")
        } else {
            Text(minutes == 0 ? "Tap to stay awake" : "Tap for \(Self.durations.first { $0.minutes == minutes }?.label ?? "")")
        }
    }
}

struct AudioControlsWidget: View {
    @ObservedObject var service: AudioMixerService
    var compact = false

    var body: some View {
        if compact {
            HStack(spacing: 8) {
                muteButton
                Slider(value: Binding(get: { service.masterVolume }, set: service.setMasterVolume), in: 0...1)
                    .controlSize(.small)
                    .accessibilityLabel("Output volume")
            }
            .padding(.horizontal, 10)
            .frame(maxHeight: .infinity)
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 8) {
                        muteButton
                        VStack(alignment: .leading, spacing: 3) {
                            Text(service.outputName).lineLimit(1).font(.system(size: 11, weight: .semibold))
                            Slider(value: Binding(get: { service.masterVolume }, set: service.setMasterVolume), in: 0...1)
                                .controlSize(.small)
                                .accessibilityLabel("Output volume")
                        }
                    }
                    if !service.isSupported {
                        Text("Per-app levels need macOS 14.2 or later.").font(.caption2).foregroundStyle(.secondary)
                    } else if service.sessions.isEmpty {
                        Text("Apps playing sound appear here with their own volume.")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    ForEach(service.sessions) { session in
                        HStack(spacing: 8) {
                            Button { service.toggleMute(for: session.id) } label: {
                                Group {
                                    if let icon = session.icon {
                                        Image(nsImage: icon).resizable()
                                    } else {
                                        Image(systemName: "app.fill").resizable().foregroundStyle(.secondary)
                                    }
                                }
                                .frame(width: 20, height: 20)
                                .opacity(session.isMuted ? 0.35 : 1)
                                .overlay(alignment: .bottomTrailing) {
                                    if session.isMuted {
                                        Image(systemName: "speaker.slash.fill").font(.system(size: 7, weight: .bold))
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .help(session.isMuted ? "Unmute \(session.name)" : "Mute \(session.name)")
                            .accessibilityLabel("Toggle mute for \(session.name)")
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(session.name).font(.system(size: 10, weight: .medium)).lineLimit(1)
                                    Spacer()
                                    Text("\(Int(session.volume * 100))%").font(.system(size: 9)).monospacedDigit()
                                        .foregroundStyle(.secondary)
                                }
                                Slider(value: Binding(get: { session.volume }, set: { service.setVolume($0, for: session.id) }), in: 0...1)
                                    .controlSize(.mini)
                                    .accessibilityLabel("\(session.name) volume")
                            }
                        }
                    }
                    if let error = service.engineError {
                        Text(error).font(.caption2).foregroundStyle(.secondary)
                        Button("Retry audio mixer", action: service.retryMixer).font(.caption)
                    }
                }
                .padding(.horizontal, 11)
                .padding(.bottom, 8)
            }
        }
    }

    private var muteButton: some View {
        Button { service.toggleMasterMute() } label: {
            Image(systemName: service.masterMuted ? "speaker.slash.fill" : volumeSymbol)
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(Color.primary.opacity(0.09), in: Circle())
        }
        .buttonStyle(PremiumPressButtonStyle())
        .accessibilityLabel(service.masterMuted ? "Unmute output" : "Mute output")
    }

    private var volumeSymbol: String {
        switch service.masterVolume {
        case ..<0.01: return "speaker.fill"
        case ..<0.34: return "speaker.wave.1.fill"
        case ..<0.67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }
}

struct SystemStatsWidget: View {
    @ObservedObject var service: SystemStatsService
    var compact = false
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        if compact {
            HStack(spacing: 0) {
                gauge("CPU", service.cpuUsage)
                gauge("MEM", service.memoryUsage)
                gauge("DISK", service.diskUsage)
            }
            .padding(.horizontal, 6)
            .frame(maxHeight: .infinity)
        } else {
            VStack(spacing: 8) {
                metric("CPU", value: service.cpuUsage, values: service.history.map(\.cpu))
                metric("Memory", value: service.memoryUsage, values: service.history.map(\.memory))
                metric("Disk", value: service.diskUsage, values: service.history.map(\.disk))
            }
            .padding(.horizontal, 11)
            .padding(.bottom, 9)
            .frame(maxHeight: .infinity)
            .help("Last 3 minutes, sampled every 3 seconds")
        }
    }

    private func tint(for value: Double) -> Color {
        value >= 0.9 ? .red : value >= 0.75 ? .orange : theme.notch.accent
    }

    private func gauge(_ name: String, _ value: Double) -> some View {
        VStack(spacing: 3) {
            ZStack {
                WidgetRing(progress: value, tint: tint(for: value), lineWidth: 3)
                Text("\(Int(value * 100))").font(.system(size: 9, weight: .bold, design: .rounded)).monospacedDigit()
            }
            .frame(width: 30, height: 30)
            Text(name).font(.system(size: 7, weight: .bold)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(name) \(Int(value * 100)) percent")
    }

    private func metric(_ name: String, value: Double, values: [Double]) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(name).font(.system(size: 10, weight: .medium))
                Spacer()
                Text("\(Int(value * 100))%").font(.system(size: 11, weight: .semibold, design: .rounded)).monospacedDigit()
                    .foregroundStyle(tint(for: value))
            }
            Sparkline(values: values.isEmpty ? [value, value] : values, tint: tint(for: value))
                .frame(height: 18)
                .accessibilityHidden(true)
        }
    }
}

/// Filled line chart with a baseline, so a short history still reads as data.
private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            let points = values.enumerated().map { index, sample in
                CGPoint(x: CGFloat(index) / CGFloat(max(1, values.count - 1)) * proxy.size.width,
                        y: (1 - min(1, max(0, sample))) * proxy.size.height)
            }
            ZStack {
                Rectangle().fill(Color.primary.opacity(0.06)).frame(height: 1)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: CGPoint(x: first.x, y: proxy.size.height))
                    points.forEach { path.addLine(to: $0) }
                    path.addLine(to: CGPoint(x: points.last!.x, y: proxy.size.height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [tint.opacity(0.28), tint.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                Path { path in
                    guard let first = points.first else { return }
                    path.move(to: first)
                    points.dropFirst().forEach { path.addLine(to: $0) }
                }
                .stroke(tint, style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            }
        }
    }
}
