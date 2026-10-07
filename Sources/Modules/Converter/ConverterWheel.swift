import AppKit
import SwiftUI

/// Shift-drag a file and a wheel of formats appears around the pointer; drop
/// on one to convert. Option-Shift shows tools for that kind of file instead.
/// Watching mouse drags and reading the drag pasteboard needs no permission.
@MainActor
final class ConverterWheel: ObservableObject {
    static let shared = ConverterWheel()

    @Published private(set) var actions: [FileConverter.Action] = []
    @Published private(set) var urls: [URL] = []
    @Published var hovered: Int?
    @Published private(set) var showingTools = false

    static let diameter: CGFloat = 320
    static let innerRadius: CGFloat = 58
    static let outerRadius: CGFloat = 150

    private var monitors: [Any] = []
    private var panel: NSPanel?
    private var dragCount = 0
    private var watch: Timer?

    func setEnabled(_ enabled: Bool) {
        monitors.forEach(NSEvent.removeMonitor)
        monitors = []
        hide()
        guard enabled else { return }
        if let down = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDown, handler: { [weak self] _ in
            Task { @MainActor in self?.dragCount = NSPasteboard(name: .drag).changeCount }
        }) { monitors.append(down) }
        if let dragged = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseDragged, handler: { [weak self] _ in
            Task { @MainActor in self?.dragged() }
        }) { monitors.append(dragged) }
    }

    /// While a file drag is under way, Shift shows the wheel; Option switches it to tools.
    private func dragged() {
        let flags = NSEvent.modifierFlags
        let board = NSPasteboard(name: .drag)
        guard flags.contains(.shift), board.changeCount != dragCount else { return }
        let tools = flags.contains(.option)
        if panel != nil {
            if tools != showingTools { showingTools = tools; actions = FileConverter.actions(for: urls, tools: tools) }
            return
        }
        guard let found = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL],
              !found.isEmpty else { return }
        show(found, tools: tools, at: NSEvent.mouseLocation)
    }

    private func show(_ files: [URL], tools: Bool, at point: NSPoint) {
        urls = files
        showingTools = tools
        actions = FileConverter.actions(for: files, tools: tools)
        hovered = nil
        guard !actions.isEmpty else { return }
        let size = Self.diameter
        let panel = WheelPanel(contentRect: NSRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size),
                               styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .popUpMenu
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        let host = WheelHostingView(rootView: ConverterWheelView(wheel: self).environment(\.colorScheme, .dark))
        host.wheel = self
        host.frame = NSRect(origin: .zero, size: NSSize(width: size, height: size))
        panel.contentView = host
        panel.orderFrontRegardless()
        self.panel = panel
        // The drag ends somewhere else: put the wheel away once the button is up.
        watch = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, NSEvent.pressedMouseButtons & 1 == 0 else { return }
                self.hide()
            }
        }
    }

#if DEBUG
    /// QA captures: the wheel's state for these files without a drag or a panel.
    func preview(_ files: [URL], tools: Bool, hovered: Int?) {
        urls = files; showingTools = tools
        actions = FileConverter.actions(for: files, tools: tools)
        self.hovered = hovered
    }
#endif

    func hide() {
        watch?.invalidate(); watch = nil
        panel?.orderOut(nil)
        panel = nil
        hovered = nil
    }

    /// The segment under a point in the wheel's own coordinates (origin bottom-left).
    func segment(at point: NSPoint) -> Int? {
        let dx = point.x - Self.diameter / 2, dy = Self.diameter / 2 - point.y
        let distance = hypot(dx, dy)
        guard distance > Self.innerRadius, distance < Self.outerRadius + 24, !actions.isEmpty else { return nil }
        let step = 360 / Double(actions.count)
        let degrees = atan2(Double(dy), Double(dx)) * 180 / .pi
        let fromTop = (degrees + 90 + step / 2 + 720).truncatingRemainder(dividingBy: 360)
        return Int(fromTop / step) % actions.count
    }

    func drop(on index: Int) {
        guard actions.indices.contains(index) else { return }
        let action = actions[index], files = urls
        hide()
        ConverterJobs.shared.start(action, on: files)
    }
}

private final class WheelPanel: NSPanel {
    override var canBecomeKey: Bool { false }
}

/// Receives the drag: tracks the segment under the pointer and runs it on drop.
private final class WheelHostingView<Content: View>: NSHostingView<Content> {
    weak var wheel: ConverterWheel?

    required init(rootView: Content) {
        super.init(rootView: rootView)
        registerForDraggedTypes([.fileURL])
    }

    @MainActor required dynamic init?(coder: NSCoder) { fatalError() }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation { update(sender) }
    override func draggingExited(_ sender: NSDraggingInfo?) { wheel?.hovered = nil }

    // `draggingLocation` is in the panel's window coordinates (origin bottom-left),
    // which is what `segment(at:)` expects. The hosting view is flipped, so
    // converting into it would mirror the wheel top to bottom.
    private func update(_ sender: NSDraggingInfo) -> NSDragOperation {
        let index = wheel?.segment(at: sender.draggingLocation)
        if wheel?.hovered != index { wheel?.hovered = index; if index != nil { Haptics.tap() } }
        return index == nil ? [] : .copy
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard let wheel, let index = wheel.segment(at: sender.draggingLocation) else { return false }
        wheel.drop(on: index)
        return true
    }
}

/// A frosted ring of segments around the file.
struct ConverterWheelView: View {
    @ObservedObject var wheel: ConverterWheel
    @ObservedObject private var theme = ThemeStore.shared
    @State private var appeared = false

    var body: some View {
        let size = ConverterWheel.diameter
        let count = max(wheel.actions.count, 1)
        ZStack {
            Circle()
                .fill(.ultraThinMaterial)
                .overlay(Circle().fill(theme.notch.surface.opacity(0.55)))
                .overlay(Circle().strokeBorder(Color.white.opacity(0.14), lineWidth: 1))
                .frame(width: ConverterWheel.outerRadius * 2 + 12, height: ConverterWheel.outerRadius * 2 + 12)
                .shadow(color: .black.opacity(0.35), radius: 22, y: 10)
            ForEach(Array(wheel.actions.enumerated()), id: \.element.id) { index, action in
                let hovered = wheel.hovered == index
                let fill = hovered ? theme.notch.accent : Color.white
                // Inset, then filled and stroked in the same colour with round
                // joins: the corners come out soft instead of sharp.
                let shape = Segment(index: index, count: count, inner: ConverterWheel.innerRadius + 10, outer: ConverterWheel.outerRadius - 4)
                shape.fill(fill, style: FillStyle(eoFill: true))
                    .overlay(shape.stroke(fill, style: StrokeStyle(lineWidth: 8, lineJoin: .round)))
                    // One layer, then faded, so the soft corners don't show as a second outline.
                    .compositingGroup()
                    .opacity(hovered ? 1 : 0.08)
                label(action, hovered: hovered)
                    .offset(offset(for: index, count: count, radius: (ConverterWheel.innerRadius + ConverterWheel.outerRadius) / 2 + 4))
            }
            center
        }
        .frame(width: size, height: size)
        .scaleEffect(appeared ? 1 : 0.86)
        .opacity(appeared ? 1 : 0)
        .animation(.spring(response: 0.28, dampingFraction: 0.78), value: appeared)
        .animation(.easeOut(duration: 0.12), value: wheel.hovered)
        .onAppear { appeared = true }
    }

    private func label(_ action: FileConverter.Action, hovered: Bool) -> some View {
        VStack(spacing: 3) {
            if let symbol = action.symbol {
                Image(systemName: symbol).font(.system(size: 15, weight: .semibold))
            }
            Text(action.symbol == nil ? action.title : action.title.uppercased())
                .font(.system(size: action.symbol == nil ? 15 : 9, weight: .bold))
                .tracking(action.symbol == nil ? 0.3 : 0.4)
                .lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(width: 64)
        .foregroundStyle(hovered ? Color.black.opacity(0.85) : theme.nookForeground)
    }

    private var center: some View {
        ZStack {
            Circle().fill(theme.notch.surface).frame(width: ConverterWheel.innerRadius * 2, height: ConverterWheel.innerRadius * 2)
            if !wheel.urls.isEmpty {
                // A file, not a picture of its contents: the page with its type, stacked for several.
                FileGlyph(kind: fileKind, stacked: wheel.urls.count > 1, ink: theme.nookForeground, accent: theme.notch.accent)
                    .offset(y: -6)
            } else {
                Image(systemName: wheel.showingTools ? "wrench.and.screwdriver" : "arrow.triangle.2.circlepath")
                    .font(.system(size: 26, weight: .medium)).foregroundStyle(theme.notch.accent)
            }
            Text(caption)
                .font(.system(size: 11, weight: .bold)).monospacedDigit()
                .foregroundStyle(theme.nookForeground)
                .padding(.horizontal, 9).padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().fill(theme.notch.surface.opacity(0.5)))
                .offset(y: ConverterWheel.innerRadius - 8)
        }
    }

    /// The type shown on the page: the extension for one file, or the shared one for several.
    private var fileKind: String {
        let kinds = Set(wheel.urls.map { $0.pathExtension.uppercased() })
        guard kinds.count == 1, let kind = kinds.first, !kind.isEmpty, kind.count <= 5 else { return "" }
        return kind
    }

    private var caption: String {
        if wheel.urls.count > 1 { return "\(wheel.urls.count) files" }
        guard let url = wheel.urls.first,
              let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return wheel.showingTools ? "Tools" : "Convert" }
        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }

    private func offset(for index: Int, count: Int, radius: CGFloat) -> CGSize {
        let angle = (Double(index) * 360 / Double(count) - 90) * .pi / 180
        return CGSize(width: cos(angle) * radius, height: sin(angle) * radius)
    }
}

/// One annular slice, starting at the top and going clockwise, with a small gap.
private struct Segment: Shape {
    let index: Int
    let count: Int
    let inner: CGFloat
    let outer: CGFloat

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        // A single choice is a whole, smooth ring.
        if count == 1 {
            var ring = Path()
            ring.addEllipse(in: CGRect(x: center.x - outer, y: center.y - outer, width: outer * 2, height: outer * 2))
            ring.addEllipse(in: CGRect(x: center.x - inner, y: center.y - inner, width: inner * 2, height: inner * 2))
            return ring
        }
        let step = 2 * Double.pi / Double(count)
        let gap = 0.05
        let start = Double(index) * step - .pi / 2 - step / 2 + gap
        let end = start + step - gap * 2
        func point(_ radius: CGFloat, _ angle: Double) -> CGPoint {
            CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius)
        }
        var path = Path()
        let samples = 24
        path.move(to: point(inner, start))
        for i in 0...samples { path.addLine(to: point(outer, start + (end - start) * Double(i) / Double(samples))) }
        for i in (0...samples).reversed() { path.addLine(to: point(inner, start + (end - start) * Double(i) / Double(samples))) }
        path.closeSubpath()
        return path
    }
}

// MARK: - Jobs

/// Conversions in progress, shown as small cards in the bottom-right corner.
@MainActor
final class ConverterJobs: ObservableObject {
    static let shared = ConverterJobs()

    struct Job: Identifiable {
        let id = UUID()
        let title: String
        let action: FileConverter.Action
        let inputs: [URL]
        var progress: Double = 0
        var outputs: [URL] = []
        var issues: [FileConverter.BatchResult.Issue] = []
        var remaining: [URL] = []
        var sizeSummary: String?
        var state: State = .running
        enum State: Equatable { case running, cancelling, done, failed, cancelled }
        var active: Bool { state == .running || state == .cancelling }
    }

    @Published private(set) var jobs: [Job] = []
    private var panel: NSPanel?
    private var completions: [UUID: @MainActor ([URL]) -> Void] = [:]
    private var workers: [UUID: Task<FileConverter.BatchResult, Never>] = [:]

    func start(_ action: FileConverter.Action, on urls: [URL], completion: @escaping @MainActor ([URL]) -> Void = { _ in }) {
        guard !urls.isEmpty else { return }
        let name = urls.count == 1 ? urls[0].lastPathComponent : "\(urls.count) files"
        let verb = action.symbol == nil ? "\(name) → \(action.title)" : "\(action.title): \(name)"
        let job = Job(title: verb, action: action, inputs: urls)
        jobs.append(job)
        completions[job.id] = completion
        showPanel()
        let worker = Task.detached(priority: .userInitiated) { [weak self] in
            await FileConverter.runBatch(action, on: urls) { [weak self] value in
                self?.update(job.id) { $0.progress = value }
            }
        }
        workers[job.id] = worker
        Task { [weak self] in
            let result = await worker.value
            guard let self else { return }
            self.workers[job.id] = nil
            let sizeSummary: String?
            if urls.count == 1, result.outputs.count == 1,
               let before = try? urls[0].resourceValues(forKeys: [.fileSizeKey]).fileSize,
               let after = try? result.outputs[0].resourceValues(forKeys: [.fileSizeKey]).fileSize {
                sizeSummary = ByteCountFormatter.string(fromByteCount: Int64(before), countStyle: .file) + " → " + ByteCountFormatter.string(fromByteCount: Int64(after), countStyle: .file)
            } else { sizeSummary = nil }
            self.update(job.id) {
                $0.sizeSummary = sizeSummary
                $0.outputs = result.outputs; $0.issues = result.issues; $0.remaining = result.remaining
                $0.state = result.cancelled ? .cancelled : result.issues.isEmpty ? .done : .failed
                if !result.cancelled { $0.progress = 1 }
            }
            completion(result.outputs)
            if action.id == "tool.ocr", !result.outputs.isEmpty {
                let text = result.outputs.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n\n")
                if !text.isEmpty {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(text, forType: .string)
                }
            }
            if UserDefaults.standard.bool(forKey: "converter.revealResults"), !result.outputs.isEmpty {
                NSWorkspace.shared.activateFileViewerSelecting(result.outputs)
            }
        }
    }

    func cancel(_ id: UUID) {
        guard workers[id] != nil else { return }
        update(id) { $0.state = .cancelling }
        workers[id]?.cancel()
    }

    func dismiss(_ id: UUID) {
        guard workers[id] == nil else { return }
        jobs.removeAll { $0.id == id }
        completions[id] = nil
        if jobs.isEmpty { panel?.orderOut(nil) }
    }

    func retry(_ job: Job) {
        let urls = job.issues.map(\.url) + job.remaining
        guard !urls.isEmpty else { return }
        let completion = completions[job.id] ?? { _ in }
        if job.outputs.isEmpty { dismiss(job.id) }
        else { update(job.id) { $0.issues = []; $0.remaining = []; $0.state = .done } }
        start(job.action, on: urls, completion: completion)
    }

    private func update(_ id: UUID, _ change: (inout Job) -> Void) {
        guard let index = jobs.firstIndex(where: { $0.id == id }) else { return }
        change(&jobs[index])
    }

    private func showPanel() {
        guard let screen = NSScreen.main?.visibleFrame else { return }
        let size = NSSize(width: 360, height: 380)
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: screen.maxX - size.width - 16, y: screen.minY + 16, width: size.width, height: size.height),
                                styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = false
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: ConverterJobsView(jobs: self).environment(\.colorScheme, .dark))
            self.panel = panel
        }
        panel?.orderFrontRegardless()
    }
}

private struct ConverterJobsView: View {
    @ObservedObject var jobs: ConverterJobs
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .trailing, spacing: 8) {
                ForEach(jobs.jobs) { job in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: job.active ? "arrow.triangle.2.circlepath" : job.state == .done ? "checkmark.circle" : "exclamationmark.circle")
                                .foregroundStyle(theme.notch.accent)
                            Text(job.title).font(.system(size: 12, weight: .semibold)).lineLimit(2).truncationMode(.middle)
                            Spacer(minLength: 0)
                            if !job.active {
                                Button { jobs.dismiss(job.id) } label: { Image(systemName: "xmark") }
                                    .buttonStyle(.plain).help("Dismiss result").accessibilityLabel("Dismiss result")
                            }
                        }
                        if job.active {
                            if job.progress > 0 {
                                ProgressView(value: job.progress).tint(theme.notch.accent)
                            } else { ProgressView().controlSize(.small) }
                            HStack {
                                Text(job.state == .cancelling ? "Cancelling…" : "Processing on this Mac…").font(.caption)
                                Spacer()
                                Button("Cancel") { jobs.cancel(job.id) }.disabled(job.state == .cancelling)
                            }
                        } else {
                            if job.state == .cancelled { Text("Cancelled · completed files kept").font(.caption) }
                            if let summary = job.sizeSummary { Text(summary).font(.caption).foregroundStyle(.secondary) }
                            ForEach(Array(job.issues.enumerated()), id: \.offset) { _, issue in
                                Text(issue.url.lastPathComponent + ": " + issue.message).font(.caption).foregroundStyle(.orange)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            ForEach(job.outputs, id: \.self) { url in
                                HStack {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(url.lastPathComponent).font(.caption).lineLimit(1).truncationMode(.middle)
                                        Text("Saved in " + url.deletingLastPathComponent().lastPathComponent).font(.system(size: 10)).foregroundStyle(.secondary)
                                    }
                                    Spacer(minLength: 0)
                                    Button("Reveal") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                                }
                                .onDrag { NSItemProvider(contentsOf: url) ?? NSItemProvider() }
                            }
                            if job.state == .failed || job.state == .cancelled {
                                Button("Retry") { jobs.retry(job) }
                            }
                        }
                    }
                    .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                    .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .background(theme.notch.surface.opacity(0.6), in: RoundedRectangle(cornerRadius: 16))
                    .foregroundStyle(theme.nookForeground)
                }
            }.padding(10)
        }
    }
}

/// A document page with a folded corner and its file type, drawn in the theme's ink.
private struct FileGlyph: View {
    let kind: String
    let stacked: Bool
    let ink: Color
    let accent: Color

    var body: some View {
        ZStack {
            if stacked {
                page.opacity(0.35).rotationEffect(.degrees(-9)).offset(x: -7, y: 2)
            }
            page
        }
        .frame(width: 52, height: 64)
        .accessibilityHidden(true)
    }

    private var page: some View {
        ZStack {
            PageShape().fill(ink.opacity(0.12))
            PageShape().stroke(ink.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            FoldShape().stroke(ink.opacity(0.85), style: StrokeStyle(lineWidth: 2.2, lineJoin: .round))
            if !kind.isEmpty {
                Text(kind)
                    .font(.system(size: kind.count > 3 ? 9.5 : 11, weight: .heavy, design: .rounded))
                    .foregroundStyle(Color.black.opacity(0.8))
                    .padding(.horizontal, 4).padding(.vertical, 2)
                    .background(accent, in: RoundedRectangle(cornerRadius: 3))
                    .offset(y: 9)
            }
        }
        .frame(width: 44, height: 56)
    }

    private struct PageShape: Shape {
        func path(in rect: CGRect) -> Path {
            let fold = rect.width * 0.32, r: CGFloat = 4
            var path = Path()
            path.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - r))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - r, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX + r, y: rect.maxY))
            path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - r), control: CGPoint(x: rect.minX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
            path.addQuadCurve(to: CGPoint(x: rect.minX + r, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
            path.closeSubpath()
            return path
        }
    }

    private struct FoldShape: Shape {
        func path(in rect: CGRect) -> Path {
            let fold = rect.width * 0.32
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX - fold, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - fold, y: rect.minY + fold - 2))
            path.addQuadCurve(to: CGPoint(x: rect.maxX - fold + 2, y: rect.minY + fold), control: CGPoint(x: rect.maxX - fold, y: rect.minY + fold))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + fold))
            return path
        }
    }
}
