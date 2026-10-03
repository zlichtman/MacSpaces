import SwiftUI
import AppKit

/// Soft pill used for presets and secondary widget actions. `prominent`
/// marks the primary action with the theme accent.
struct WidgetChipStyle: ButtonStyle {
    var prominent = false
    var height: CGFloat = 24
    @ObservedObject private var theme = ThemeStore.shared

    init(prominent: Bool = false, height: CGFloat = 24) {
        self.prominent = prominent
        self.height = height
    }

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .semibold, design: .rounded))
            .lineLimit(1)
            .minimumScaleFactor(0.75)
            .foregroundStyle(prominent ? Color.black.opacity(0.82) : Color.primary)
            .padding(.horizontal, height < 23 ? 5 : 8)
            .frame(minHeight: height)
            .background(
                prominent ? AnyShapeStyle(theme.notch.accent) : AnyShapeStyle(Color.primary.opacity(0.09)),
                in: RoundedRectangle(cornerRadius: height * 0.36, style: .continuous)
            )
            .contentShape(RoundedRectangle(cornerRadius: height * 0.36, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

/// A thin progress ring shared by the timer and focus widgets.
struct WidgetRing: View {
    let progress: Double
    let tint: Color
    var lineWidth: CGFloat = 5

    var body: some View {
        ZStack {
            Circle().stroke(Color.primary.opacity(0.10), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: min(max(progress, 0), 1))
                .stroke(tint, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 1), value: progress)
        }
    }
}

// MARK: - Timer

struct NookTimerWidget: View {
    @ObservedObject var service: TimerService
    let compact: Bool
    @ObservedObject private var options = WidgetOptions.shared
    @State private var customMinutes = 10

    private let tint = Color.orange

    var body: some View {
        if compact { compactBody } else { regularBody }
    }

    /// Stacked tiles are ~96 pt wide: the time gets its own row and the
    /// controls sit beneath it, so neither is ever cut off.
    private var compactBody: some View {
        HStack(spacing: 6) {
            if service.isRunning {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        WidgetRing(progress: service.progress, tint: tint, lineWidth: 3).frame(width: 16, height: 16)
                        Text(service.remainingText)
                            .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                            .opacity(service.isPaused ? 0.55 : 1)
                    }
                    HStack(spacing: 5) {
                        iconButton(service.isPaused ? "play.fill" : "pause.fill", service.isPaused ? "Resume" : "Pause") { service.togglePause() }
                        Button("+1") { service.extend(by: 60) }
                            .buttonStyle(WidgetChipStyle(height: 22)).help("Add a minute")
                        iconButton("xmark", "Cancel timer") { service.cancel() }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                ForEach(options.timerPresets, id: \.self) { minutes in
                    Button { service.start(minutes: minutes) } label: {
                        Text("\(minutes)").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WidgetChipStyle(height: 22))
                    .help("Start a \(minutes)-minute timer")
                }
            }
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }

    private var regularBody: some View {
        VStack(spacing: 8) {
            if service.isRunning {
                ZStack {
                    WidgetRing(progress: service.progress, tint: tint, lineWidth: 5)
                    VStack(spacing: 1) {
                        Text(service.remainingText)
                            .font(.system(size: 19, weight: .semibold, design: .rounded)).monospacedDigit()
                            .lineLimit(1).minimumScaleFactor(0.6)
                        Text(service.isPaused ? "Paused" : "Remaining")
                            .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                    }
                    .padding(8)
                }
                .frame(maxWidth: 104, maxHeight: 104)
                HStack(spacing: 6) {
                    Button { service.togglePause() } label: {
                        Image(systemName: service.isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
                    .help(service.isPaused ? "Resume" : "Pause")
                    Button("+1m") { service.extend(by: 60) }
                        .buttonStyle(WidgetChipStyle(height: 26)).help("Add a minute")
                    Button { service.cancel() } label: { Image(systemName: "xmark") }
                        .buttonStyle(WidgetChipStyle(height: 26)).help("Cancel timer")
                }
            } else {
                Text(durationText(customMinutes))
                    .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                    .contentTransition(.numericText())
                HStack(spacing: 6) {
                    Button { adjust(-1) } label: { Image(systemName: "minus") }
                        .buttonStyle(WidgetChipStyle(height: 24)).help("Shorter")
                    Button("Start") { service.start(minutes: customMinutes) }
                        .buttonStyle(WidgetChipStyle(prominent: true, height: 24))
                    Button { adjust(1) } label: { Image(systemName: "plus") }
                        .buttonStyle(WidgetChipStyle(height: 24)).help("Longer")
                }
                HStack(spacing: 5) {
                    ForEach(options.timerPresets, id: \.self) { minutes in
                        Button("\(minutes)m") { service.start(minutes: minutes) }
                            .buttonStyle(WidgetChipStyle(height: 22))
                            .help("Start a \(minutes)-minute timer")
                    }
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// One-minute steps up to ten minutes, then five-minute steps.
    private func adjust(_ direction: Int) {
        let step = (direction > 0 ? customMinutes >= 10 : customMinutes > 10) ? 5 : 1
        withAnimation(.snappy(duration: 0.18)) {
            customMinutes = min(max(customMinutes + direction * step, 1), 180)
        }
    }

    private func durationText(_ minutes: Int) -> String {
        minutes >= 60 ? String(format: "%d:%02d:00", minutes / 60, minutes % 60) : "\(minutes):00"
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 9, weight: .bold)).frame(width: 22, height: 22)
                .background(Color.primary.opacity(0.09), in: Circle()).contentShape(Circle())
        }
        .buttonStyle(PremiumPressButtonStyle()).help(help).accessibilityLabel(help)
    }
}

// MARK: - Clock

struct NookClockWidget: View {
    let compact: Bool
    @ObservedObject private var options = WidgetOptions.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            if compact {
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(timeText(context.date, zone: nil))
                        .font(.system(size: 17, weight: .bold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.7)
                    Spacer(minLength: 2)
                    Text(context.date, format: .dateTime.weekday(.abbreviated))
                        .font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 11)
                .frame(maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    Text(timeText(context.date, zone: nil))
                        .font(.system(size: 26, weight: .semibold, design: .rounded)).monospacedDigit()
                        .lineLimit(1).minimumScaleFactor(0.6)
                    Text(context.date, format: .dateTime.weekday(.wide).month(.abbreviated).day())
                        .font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        .lineLimit(1).minimumScaleFactor(0.8)
                    if let zone = options.secondTimeZone {
                        Divider().padding(.horizontal, 18).padding(.vertical, 2)
                        VStack(spacing: 1) {
                            Text(timeText(context.date, zone: zone))
                                .font(.system(size: 14, weight: .semibold, design: .rounded)).monospacedDigit()
                            Text(Self.cityName(for: zone) + " · " + offsetText(context.date, zone: zone))
                                .font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary)
                                .lineLimit(1).minimumScaleFactor(0.8)
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.bottom, 8)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func timeText(_ date: Date, zone: TimeZone?) -> String {
        let formatter = DateFormatter()
        formatter.locale = .current
        formatter.timeZone = zone ?? .current
        let seconds = options.clockShowsSeconds && zone == nil ? ":ss" : ""
        formatter.dateFormat = options.clockUses24Hour ? "HH:mm" + seconds : "h:mm" + seconds + " a"
        return formatter.string(from: date)
    }

    private func offsetText(_ date: Date, zone: TimeZone) -> String {
        let hours = Double(zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 3600
        if hours == 0 { return "Same time" }
        let value = hours == hours.rounded() ? String(Int(hours)) : String(format: "%.1f", hours)
        return (hours > 0 ? "+" : "") + value + "h"
    }

    static func cityName(for zone: TimeZone) -> String {
        WidgetOptions.worldClockZones.first { $0.identifier == zone.identifier }?.title
            ?? zone.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") }
            ?? zone.identifier
    }
}

// MARK: - Media (small)

/// Artwork, title and play/pause for a stacked media tile.
struct CompactMediaView: View {
    @ObservedObject var nowPlaying: NowPlayingController
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        HStack(spacing: 8) {
            Button { nowPlaying.openSource() } label: {
                RecordArtwork(artwork: nowPlaying.info.artwork, accent: theme.notch.accent,
                              control: theme.notch.control, size: 38)
            }
            .buttonStyle(PremiumPressButtonStyle())
            .disabled(!nowPlaying.canOpenSource)
            VStack(alignment: .leading, spacing: 1) {
                Text(nowPlaying.info.hasTrack ? nowPlaying.info.title : "Nothing playing")
                    .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Text(nowPlaying.info.hasTrack ? nowPlaying.info.artist : "Music or Spotify")
                    .font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button { nowPlaying.togglePlayPause() } label: {
                Image(systemName: nowPlaying.displayIsPlaying ? "pause.fill" : "play.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Color.black.opacity(0.82))
                    .frame(width: 26, height: 26)
                    .background(theme.notch.accent, in: Circle())
            }
            .buttonStyle(PremiumPressButtonStyle())
            .disabled(!nowPlaying.supports(.playPause))
            .accessibilityLabel(nowPlaying.displayIsPlaying ? "Pause" : "Play")
        }
        .padding(.horizontal, 10)
        .frame(maxHeight: .infinity)
    }
}
