import SwiftUI

struct KeepAwakeWidget: View {
    @ObservedObject var service: KeepAwakeService
    @State private var mode = KeepAwakeService.Mode.system
    @State private var minutes = 30

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Mode", selection: $mode) {
                ForEach(KeepAwakeService.Mode.allCases) { Text($0.rawValue).tag($0) }
            }.labelsHidden().disabled(service.isActive)
            Picker("Duration", selection: $minutes) {
                Text("15 minutes").tag(15)
                Text("30 minutes").tag(30)
                Text("1 hour").tag(60)
                Text("2 hours").tag(120)
                Text("Until stopped").tag(0)
            }.labelsHidden().disabled(service.isActive)
            if let end = service.expiresAt {
                Text(end, style: .timer).monospacedDigit().font(.caption)
            } else {
                Text(service.isActive ? "Until you stop it" : "Idle sleep is allowed")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Button(service.isActive ? "Allow Sleep" : "Keep Awake") {
                if service.isActive { service.stop() }
                else { service.start(mode: mode, minutes: minutes == 0 ? nil : minutes) }
            }
            if let error = service.error { Text(error).font(.caption2).foregroundStyle(.secondary) }
        }.padding(10)
    }
}

struct AudioControlsWidget: View {
    @ObservedObject var service: AudioMixerService

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                HStack {
                    Text(service.outputName).lineLimit(1).font(.caption)
                    Spacer(minLength: 4)
                    Button { service.toggleMasterMute() } label: {
                        Image(systemName: service.masterMuted ? "speaker.slash.fill" : "speaker.wave.2.fill")
                    }.buttonStyle(.plain).accessibilityLabel(service.masterMuted ? "Unmute output" : "Mute output")
                }
                Slider(value: Binding(get: { service.masterVolume }, set: service.setMasterVolume), in: 0...1)
                    .accessibilityLabel("Output volume")
                if !service.isSupported {
                    Text("Per-app levels require macOS 14.2 or later.").font(.caption2).foregroundStyle(.secondary)
                } else if service.sessions.isEmpty {
                    Text("Play audio in an app to adjust its volume here.").font(.caption).foregroundStyle(.secondary)
                }
                ForEach(service.sessions) { session in
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            if let icon = session.icon { Image(nsImage: icon).resizable().frame(width: 16, height: 16) }
                            Text(session.name).font(.caption).lineLimit(1)
                            Spacer()
                            Text("\(Int(session.volume * 100))%").font(.caption2).monospacedDigit()
                            Button { service.toggleMute(for: session.id) } label: {
                                Image(systemName: session.isMuted ? "speaker.slash" : "speaker.wave.1")
                            }.buttonStyle(.plain).accessibilityLabel("Toggle mute for \(session.name)")
                        }
                        Slider(value: Binding(get: { session.volume }, set: { service.setVolume($0, for: session.id) }), in: 0...1)
                            .accessibilityLabel("\(session.name) volume")
                    }
                }
                if let error = service.engineError {
                    Text(error).font(.caption2).foregroundStyle(.secondary)
                    Button("Retry audio mixer", action: service.retryMixer).font(.caption)
                }
            }.padding(10)
        }
    }
}

struct SystemStatsWidget: View {
    @ObservedObject var service: SystemStatsService
    var body: some View {
        VStack(spacing: 10) {
            metric("CPU", value: service.cpuUsage, values: service.history.map(\.cpu))
            metric("Memory", value: service.memoryUsage, values: service.history.map(\.memory))
            metric("Disk used", value: service.diskUsage, values: service.history.map(\.disk))
            Text("Last 3 minutes · 3-second samples")
                .font(.system(size: 9)).foregroundStyle(.secondary)
        }.padding(10)
    }
    private func metric(_ name: String, value: Double, values: [Double]) -> some View {
        VStack(spacing: 3) {
            HStack {
                Text(name)
                Spacer()
                Text("\(Int(value * 100))%").monospacedDigit()
            }.font(.caption)
            GeometryReader { proxy in
                Path { path in
                    for (index, sample) in values.enumerated() {
                        let point = CGPoint(x: CGFloat(index) / CGFloat(max(1, values.count - 1)) * proxy.size.width,
                            y: (1 - min(1, max(0, sample))) * proxy.size.height)
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }.stroke(ThemeStore.shared.notch.accent, lineWidth: 1.5)
            }.frame(height: 17).accessibilityHidden(true)
        }
    }
}
