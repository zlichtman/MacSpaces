import SwiftUI
import UniformTypeIdentifiers

extension UTType {
    static let nookWidget = UTType(exportedAs: "dev.opensource.MacSpaces.widget", conformingTo: .data)
}

/// Dedicated payloads cannot be confused with a file drag or arbitrary pasted text.
enum NookWidgetTransfer {
    static func provider(_ kind: NookWidgetKind) -> NSItemProvider {
        let provider = NSItemProvider()
        provider.suggestedName = kind.title
        provider.registerDataRepresentation(forTypeIdentifier: UTType.nookWidget.identifier, visibility: .all) { complete in
            complete(Data(kind.rawValue.utf8), nil)
            return nil
        }
        return provider
    }

    static func decode(_ data: Data) -> NookWidgetKind? {
        guard data.count <= 64, let raw = String(data: data, encoding: .utf8) else { return nil }
        return NookWidgetKind(rawValue: raw)
    }

    @MainActor @discardableResult
    static func receive(_ providers: [NSItemProvider], into settings: NookSettings,
                        before target: NookWidgetKind? = nil,
                        selected: @escaping (NookWidgetKind) -> Void = { _ in }) -> Bool {
        guard let provider = providers.first(where: { $0.hasItemConformingToTypeIdentifier(UTType.nookWidget.identifier) }) else { return false }
        let profileID = settings.activeProfileID
        provider.loadDataRepresentation(forTypeIdentifier: UTType.nookWidget.identifier) { data, _ in
            guard let data, let kind = decode(data) else { return }
            Task { @MainActor in
                defer { WidgetDragSession.shared.finish() }
                guard settings.activeProfileID == profileID else { return }
                withAnimation(Design.spring()) {
                    settings.setEnabled(true, for: kind)
                    if let target { settings.moveWidget(kind, to: target) }
                }
                selected(kind)
            }
        }
        return true
    }
}

/// Always-visible sample cards: browsing never starts a service or requests a permission.
struct WidgetGallery: View {
    @ObservedObject var settings: NookSettings
    let select: (NookWidgetKind) -> Void
    @ObservedObject private var theme = ThemeStore.shared
    @State private var search = ""

    private var kinds: [NookWidgetKind] {
        NookWidgetKind.alphabetical.filter {
            search.isEmpty || $0.title.localizedCaseInsensitiveContains(search)
                || $0.descriptor.summary.localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Widgets").font(.headline)
                Spacer()
                Text("Drag to Home").font(.caption).foregroundStyle(.secondary)
            }
            SettingsListSearchField("Search widgets", text: $search)
            BalancedWidgetGalleryLayout {
                ForEach(kinds) { kind in card(kind) }
            }
            if kinds.isEmpty {
                Text("No widgets match your search.").font(.caption).foregroundStyle(.secondary).padding(.vertical, 16)
            }
        }
    }

    private func card(_ kind: NookWidgetKind) -> some View {
        let included = settings.widgets.contains(kind)
        return VStack(alignment: .leading, spacing: 9) {
            WidgetVisualPreview(kind: kind)
                .frame(maxWidth: .infinity).frame(height: 112)
                .padding(8)
                .background(theme.notch.surface, in: RoundedRectangle(cornerRadius: 12))
                .environment(\.colorScheme, theme.notch.colorScheme)
                .foregroundStyle(theme.nookForeground)
            HStack(spacing: 6) {
                Text(kind.title).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
                Button(included ? "Added" : "Add") {
                    withAnimation(Design.spring()) { settings.setEnabled(true, for: kind) }
                    select(kind)
                }
                .buttonStyle(.settings()).disabled(included)
                .accessibilityLabel(included ? "\(kind.title) is on Home" : "Add \(kind.title) to Home")
            }
        }
        .padding(10)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onDrag {
            NotchManager.active?.beginWidgetLibraryDrag()
            return NookWidgetTransfer.provider(kind)
        } preview: {
            WidgetVisualPreview(kind: kind).frame(width: 185, height: 112).padding(12)
                .background(theme.notch.surface, in: RoundedRectangle(cornerRadius: 16))
                .environment(\.colorScheme, theme.notch.colorScheme).foregroundStyle(theme.nookForeground)
        }
        .help("Drag \(kind.title) to Home")
    }
}

/// Small, static illustrations of the widgets themselves, shared by the gallery and layout editor.
/// These deliberately use no live services, timers, private content, camera or microphone.
struct WidgetVisualPreview: View {
    let kind: NookWidgetKind
    var compact: Bool? = nil
    @ObservedObject private var theme = ThemeStore.shared
    private var accent: Color { theme.notch.accent }

    private var isCompact: Bool { compact ?? (kind.defaultSize == .small) }

    var body: some View {
        GeometryReader { proxy in
            let usesHomeComponent = [.media, .clock, .timer].contains(kind)
            let natural = usesHomeComponent
                ? CGSize(width: kind.width(for: kind.defaultSize), height: isCompact ? 104 : 218)
                : CGSize(width: 180, height: 104)
            let scale = min(proxy.size.width / natural.width, proxy.size.height / natural.height)
            Group {
                switch kind {
                case .media: MediaPlayerView(nowPlaying: WidgetPreviewSamples.music).padding(.horizontal, 5)
                case .clock: NookClockWidget(compact: isCompact)
                case .timer: NookTimerWidget(service: WidgetPreviewSamples.timer, compact: isCompact)
                default: illustration.frame(width: 180, height: 104)
                    .frame(width: natural.width, height: natural.height)
                }
            }
            .frame(width: natural.width, height: natural.height)
            .scaleEffect(scale)
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    @ViewBuilder private var illustration: some View {
        switch kind {
        case .media:
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 10).fill(LinearGradient(colors: [accent, .indigo], startPoint: .topLeading, endPoint: .bottomTrailing))
                    .overlay(Image(systemName: "music.note").font(.system(size: 26)).foregroundStyle(.white)).frame(width: 58, height: 66)
                VStack(alignment: .leading, spacing: 8) {
                    Text("Your music").font(.system(size: 12, weight: .semibold))
                    Text("Artist · Album").font(.system(size: 9)).foregroundStyle(.secondary)
                    HStack(spacing: 14) { Image(systemName: "backward.fill"); Image(systemName: "play.fill"); Image(systemName: "forward.fill") }.font(.system(size: 12))
                    Capsule().fill(accent.opacity(0.4)).frame(height: 3)
                }
            }.padding(6)
        case .clock:
            VStack(spacing: 5) {
                Text("10:08").font(.system(size: 34, weight: .light, design: .rounded)).monospacedDigit()
                Text("THURSDAY, OCTOBER 15").font(.system(size: 8, weight: .medium)).foregroundStyle(.secondary)
                HStack(spacing: 14) { Text("LONDON  16:08"); Text("TOKYO  00:08") }.font(.system(size: 7))
            }
        case .timer, .pomodoro:
            ZStack {
                Circle().stroke(accent.opacity(0.16), lineWidth: 6)
                Circle().trim(from: 0, to: 0.72).stroke(accent, style: StrokeStyle(lineWidth: 6, lineCap: .round)).rotationEffect(.degrees(-90))
                VStack(spacing: 5) { Text(kind == .pomodoro ? "Focus" : "Timer").font(.system(size: 9)).foregroundStyle(.secondary); Text("25:00").font(.system(size: 23, weight: .medium, design: .rounded)).monospacedDigit(); Image(systemName: "play.fill").font(.system(size: 10)) }
            }.frame(width: 93, height: 93)
        case .weather:
            VStack(spacing: 10) {
                HStack(spacing: 10) { Image(systemName: "cloud.sun.fill").symbolRenderingMode(.multicolor).font(.system(size: 30)); VStack(alignment: .leading) { Text("22°").font(.system(size: 30, weight: .light)); Text("Partly cloudy").font(.system(size: 9)) } }
                HStack(spacing: 15) { ForEach(["Fri", "Sat", "Sun", "Mon"], id: \.self) { day in VStack(spacing: 4) { Text(day); Image(systemName: "sun.max.fill").foregroundStyle(accent); Text("24°") } } }.font(.system(size: 8))
            }
        case .battery:
            VStack(spacing: 9) {
                Image(systemName: "battery.100percent").font(.system(size: 43)).foregroundStyle(accent)
                Text("100% · Fully charged").font(.system(size: 11, weight: .medium))
                Text("Battery health & devices").font(.system(size: 8)).foregroundStyle(.secondary)
            }
        case .calendar:
            VStack(alignment: .leading, spacing: 9) {
                HStack { Text("THU").foregroundStyle(accent); Spacer(); Text("15").font(.system(size: 26, weight: .light)) }
                Label("Design review", systemImage: "calendar").font(.system(size: 12, weight: .medium))
                Text("10:30 – 11:00").font(.system(size: 10)).foregroundStyle(.secondary)
                Capsule().fill(accent.opacity(0.5)).frame(height: 4)
            }.padding(10)
        case .systemStats:
            VStack(spacing: 11) {
                HStack { Label("CPU", systemImage: "cpu"); Spacer(); Text("24%") }.font(.system(size: 11))
                HStack(alignment: .bottom, spacing: 4) { ForEach(0..<20) { i in RoundedRectangle(cornerRadius: 2).fill(accent.opacity(0.5 + Double(i % 3) * 0.2)).frame(height: CGFloat(10 + (i * 13) % 32)) } }.frame(height: 42)
                HStack { Text("Memory"); Spacer(); Text("8.4 GB") }.font(.system(size: 9)).foregroundStyle(.secondary)
            }.padding(8)
        case .calculator:
            VStack(alignment: .trailing, spacing: 8) { Text("15% of 80").font(.system(size: 14)).foregroundStyle(.secondary); Text("12").font(.system(size: 34, weight: .light)); Text("Calculate · Convert · Copy").font(.system(size: 8)).foregroundStyle(accent) }.padding(12)
        case .terminal:
            VStack(alignment: .leading, spacing: 8) { Text("~  ❯ swift build").foregroundStyle(accent); Text("Building for debugging…"); Text("Build complete."); Text("~  ❯ ▏").foregroundStyle(accent) }.font(.system(size: 10, design: .monospaced)).frame(maxWidth: .infinity, alignment: .leading).padding(10)
        case .notes, .clipboard, .todos, .devServers:
            VStack(alignment: .leading, spacing: 10) {
                Label(kind.title, systemImage: kind.systemImage).font(.system(size: 12, weight: .semibold)).foregroundStyle(accent)
                ForEach(0..<3) { i in HStack(spacing: 7) { Image(systemName: kind == .todos ? "circle" : kind == .devServers ? "circle.fill" : "text.alignleft").font(.system(size: 8)).foregroundStyle(accent); RoundedRectangle(cornerRadius: 2).fill(Color.primary.opacity(0.18)).frame(width: CGFloat(110 - i * 16), height: 5) } }
            }.padding(10)
        case .keepAwake:
            VStack(spacing: 8) { Image(systemName: "cup.and.saucer.fill").font(.system(size: 30)).foregroundStyle(accent); Text("Stay awake").font(.system(size: 13, weight: .medium)); Text("15m    30m    1h    ∞").font(.system(size: 10)).foregroundStyle(.secondary) }
        case .mirror:
            RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [accent.opacity(0.25), .clear], startPoint: .top, endPoint: .bottom))
                .overlay(VStack(spacing: 8) { Image(systemName: "person.crop.rectangle").font(.system(size: 35)).foregroundStyle(accent); Text("Camera preview").font(.system(size: 10)).foregroundStyle(.secondary) }).padding(8)
        case .quickActions, .shortcuts:
            HStack(spacing: 12) { ForEach(["lock.fill", "moon.fill", "display"], id: \.self) { symbol in Image(systemName: symbol).font(.system(size: 18)).frame(width: 43, height: 43).background(accent.opacity(0.14), in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(accent) } }
        }
    }
}


/// Uses the real Home components for the starter widgets, without media polling
/// or a running timer. Their controls never receive input inside a preview.
@MainActor private enum WidgetPreviewSamples {
    static let music: NowPlayingController = {
        var info = NowPlayingInfo()
        info.title = "Your music"; info.artist = "Artist"; info.album = "Album"
        info.sourceName = "Music"; info.sourceBundleID = "com.apple.Music"
        info.duration = 240; info.elapsed = 72
        info.capabilities = [.playPause, .previous, .next, .seek]
        return NowPlayingController(preview: info)
    }()
    static let timer = TimerService(previewRemaining: 1500, total: 1800)
}

/// Each row fills its width, including the final row. Filtering never leaves
/// empty grid cells at the bottom of the gallery.
private struct BalancedWidgetGalleryLayout: Layout {
    private let spacing: CGFloat = 14
    private func rows(width: CGFloat, count: Int) -> [Int] {
        guard count > 0 else { return [] }
        let safeWidth = width.isFinite && width > 0 ? width : 600
        let columns = min(count, max(1, Int(min(12, (safeWidth + spacing) / (185 + spacing)))))
        let rowCount = (count + columns - 1) / columns
        return (0..<rowCount).map { count / rowCount + ($0 < count % rowCount ? 1 : 0) }
    }
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let proposed = proposal.width ?? 600
        let width = proposed.isFinite && proposed > 0 ? min(proposed, 10000) : 600
        var height: CGFloat = 0
        var index = 0
        for count in rows(width: width, count: subviews.count) {
            let itemWidth = max(1, (width - CGFloat(count - 1) * spacing) / CGFloat(count))
            let rowHeight = (index..<(index + count)).map { subviews[$0].sizeThatFits(.init(width: itemWidth, height: nil)).height }.max() ?? 0
            height += rowHeight + (index == 0 ? 0 : spacing)
            index += count
        }
        return CGSize(width: width, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var index = 0
        var y = bounds.minY
        for count in rows(width: bounds.width, count: subviews.count) {
            let itemWidth = max(1, (bounds.width - CGFloat(count - 1) * spacing) / CGFloat(count))
            let rowHeight = (index..<(index + count)).map { subviews[$0].sizeThatFits(.init(width: itemWidth, height: nil)).height }.max() ?? 0
            for column in 0..<count {
                subviews[index + column].place(at: CGPoint(x: bounds.minX + CGFloat(column) * (itemWidth + spacing), y: y),
                    anchor: .topLeading, proposal: .init(width: itemWidth, height: rowHeight))
            }
            index += count; y += rowHeight + spacing
        }
    }
}
