import AppKit
import ApplicationServices
import Combine
import ScreenCaptureKit
import SwiftUI

struct WindowPreviewItem: Identifiable {
    let id: CGWindowID
    let title: String
    let appName: String
    let appIcon: NSImage?
    let image: NSImage?
    let isOnScreen: Bool
    let processIdentifier: pid_t
}

private struct DockHitIdentity: Sendable {
    let bundleIdentifier: String?
    let title: String?
}

/// ScreenCaptureKit-backed window discovery and thumbnails shared by the
/// Apple Dock hover surface and MacSpaces' App Switcher widget.
@MainActor
final class WindowPreviewService: ObservableObject {
    static let shared = WindowPreviewService()

    @Published private(set) var windows: [WindowPreviewItem] = []
    @Published private(set) var applicationName = ""
    @Published private(set) var applicationIcon: NSImage?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private var generation = 0

    static var hasScreenRecordingAccess: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func requestScreenRecordingAccess() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    func clear() {
        generation += 1
        windows = []
        applicationName = ""
        applicationIcon = nil
        isLoading = false
        errorMessage = nil
    }

    func loadWindows(
        for application: NSRunningApplication,
        limit: Int,
        force: Bool = false
    ) async {
        generation += 1
        let requestGeneration = generation
        applicationName = application.localizedName ?? "Application"
        applicationIcon = application.icon
        errorMessage = nil

        guard Self.hasScreenRecordingAccess else {
            windows = []
            isLoading = false
            errorMessage = "Allow Screen Recording to see live window previews."
            return
        }

        if !force,
           windows.first?.processIdentifier == application.processIdentifier,
           !windows.isEmpty {
            return
        }

        isLoading = true
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: false
            )
            let candidates = content.windows
                .filter {
                    $0.owningApplication?.processID == application.processIdentifier
                        && $0.frame.width >= 80
                        && $0.frame.height >= 60
                }
                .sorted {
                    if $0.isOnScreen != $1.isOnScreen {
                        return $0.isOnScreen && !$1.isOnScreen
                    }
                    return ($0.title ?? "") < ($1.title ?? "")
                }
                .prefix(max(1, limit))

            let appName = application.localizedName ?? "Application"
            let icon = application.icon
            let pid = application.processIdentifier

            let previews = await withTaskGroup(
                of: (Int, WindowPreviewItem).self,
                returning: [WindowPreviewItem].self
            ) { group in
                for (index, window) in candidates.enumerated() {
                    group.addTask {
                        let image = await Self.capture(window)
                        let title = Self.displayTitle(
                            window.title,
                            appName: appName,
                            index: index
                        )
                        return (
                            index,
                            WindowPreviewItem(
                                id: window.windowID,
                                title: title,
                                appName: appName,
                                appIcon: icon,
                                image: image,
                                isOnScreen: window.isOnScreen,
                                processIdentifier: pid
                            )
                        )
                    }
                }

                var indexed: [(Int, WindowPreviewItem)] = []
                for await item in group {
                    indexed.append(item)
                }
                return indexed.sorted { $0.0 < $1.0 }.map(\.1)
            }

            guard requestGeneration == generation else { return }
            windows = previews
            isLoading = false
            if previews.isEmpty {
                errorMessage = "No open windows"
            }
        } catch {
            guard requestGeneration == generation else { return }
            windows = []
            isLoading = false
            errorMessage = "Window previews are temporarily unavailable."
        }
    }

    func activate(_ preview: WindowPreviewItem) {
        guard let application = NSRunningApplication(
            processIdentifier: preview.processIdentifier
        ) else { return }

        _ = application.activate(options: [.activateAllWindows])
        raiseAccessibilityWindow(
            processIdentifier: preview.processIdentifier,
            title: preview.title
        )
    }

    nonisolated private static func displayTitle(
        _ title: String?,
        appName: String,
        index: Int
    ) -> String {
        let trimmed = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        return index == 0 ? appName : "\(appName) Window \(index + 1)"
    }

    nonisolated private static func capture(_ window: SCWindow) async -> NSImage? {
        let sourceSize = window.frame.size
        guard sourceSize.width > 0, sourceSize.height > 0 else { return nil }

        let maximumWidth: CGFloat = 560
        let scale = min(1, maximumWidth / sourceSize.width)
        let configuration = SCStreamConfiguration()
        configuration.width = max(1, Int(sourceSize.width * scale))
        configuration.height = max(1, Int(sourceSize.height * scale))
        configuration.scalesToFit = true
        configuration.showsCursor = false
        configuration.captureResolution = .best

        do {
            let filter = SCContentFilter(desktopIndependentWindow: window)
            let cgImage = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return NSImage(cgImage: cgImage, size: .zero)
        } catch {
            return nil
        }
    }

    private func raiseAccessibilityWindow(
        processIdentifier: pid_t,
        title: String
    ) {
        guard AXIsProcessTrusted() else { return }
        let appElement = AXUIElementCreateApplication(processIdentifier)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            appElement,
            kAXWindowsAttribute as CFString,
            &value
        ) == .success,
        let elements = value as? [AXUIElement] else { return }

        let target = elements.first { element in
            var titleValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXTitleAttribute as CFString,
                &titleValue
            ) == .success else { return false }
            return (titleValue as? String) == title
        } ?? elements.first

        guard let target else { return }
        AXUIElementPerformAction(target, kAXRaiseAction as CFString)
        AXUIElementSetAttributeValue(
            target,
            kAXMainAttribute as CFString,
            kCFBooleanTrue
        )
    }
}

/// Observes the real macOS Dock, identifies the application under the pointer
/// through Accessibility, and presents a native live-preview strip.
@MainActor
final class DockWindowPreviewController {
    static let shared = DockWindowPreviewController()

    private let store = DockStore.shared
    private let service = WindowPreviewService.shared
    private var panel: DockWindowPreviewPanel?
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var isMonitoring = false
    private var cancellable: AnyCancellable?
    private var hoverWorkItem: DispatchWorkItem?
    private var hideWorkItem: DispatchWorkItem?
    private var refreshTimer: Timer?
    private var hoveredProcessIdentifier: pid_t?
    private var macSpacesHoveredProcessIdentifier: pid_t?
    private var lastEvaluation: CFTimeInterval = 0
    private let accessibilityQueue = DispatchQueue(
        label: "dev.opensource.MacSpaces.dock-accessibility",
        qos: .userInitiated
    )
    private var accessibilityLookupInFlight = false
    private var isStarted = false

    private init() {}

    func start() {
        guard !isStarted else { return }
        isStarted = true
        cancellable = store.objectWillChange
            .debounce(for: .milliseconds(80), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.reconcile() }
            }
        reconcile()
    }

    func stop() {
        isStarted = false
        cancellable?.cancel()
        cancellable = nil
        stopMonitoring()
        closePanel()
    }

    func showWindows(
        for application: NSRunningApplication,
        anchor: NSPoint = NSEvent.mouseLocation
    ) {
        guard store.windowPreviewsEnabled,
              WindowPreviewService.hasScreenRecordingAccess else {
            _ = application.activate(options: [])
            return
        }
        hoveredProcessIdentifier = application.processIdentifier
        present(application: application, anchor: anchor)
    }

    func hoverWindows(
        for application: NSRunningApplication,
        anchor: NSPoint = NSEvent.mouseLocation
    ) {
        guard store.windowPreviewsEnabled,
              WindowPreviewService.hasScreenRecordingAccess else { return }
        macSpacesHoveredProcessIdentifier = application.processIdentifier
        hoveredProcessIdentifier = application.processIdentifier
        hideWorkItem?.cancel()
        hideWorkItem = nil
        hoverWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self, weak application] in
            guard let self, let application,
                  self.macSpacesHoveredProcessIdentifier
                    == application.processIdentifier else { return }
            self.present(application: application, anchor: anchor)
        }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + store.windowPreviewDelay,
            execute: work
        )
    }

    func endMacSpacesAppHover(processIdentifier: pid_t) {
        guard macSpacesHoveredProcessIdentifier == processIdentifier else {
            return
        }
        macSpacesHoveredProcessIdentifier = nil
        scheduleHide()
    }

    private func reconcile() {
        if store.windowPreviewsEnabled {
            startMonitoring()
        } else {
            stopMonitoring()
            closePanel()
        }
    }

    private func startMonitoring() {
        // Tracked with an explicit flag rather than by testing globalMonitor:
        // that call returns nil without input-monitoring permission, so the old
        // guard never tripped and every reconcile stacked another local monitor.
        guard !isMonitoring else { return }
        isMonitoring = true
        globalMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.pointerMoved()
            }
        }
        localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.mouseMoved, .leftMouseDragged]
        ) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.pointerMoved()
            }
            return event
        }
    }

    private func stopMonitoring() {
        isMonitoring = false
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        hoveredProcessIdentifier = nil
        macSpacesHoveredProcessIdentifier = nil
    }

    private func pointerMoved() {
        let now = CACurrentMediaTime()
        guard now - lastEvaluation >= 1.0 / 20.0 else { return }
        lastEvaluation = now

        let cocoaPoint = NSEvent.mouseLocation
        if let panel, panel.frame.insetBy(dx: -10, dy: -10).contains(cocoaPoint) {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            return
        }

        if macSpacesHoveredProcessIdentifier != nil {
            hideWorkItem?.cancel()
            hideWorkItem = nil
            return
        }

        guard isNearAppleDock(cocoaPoint) else {
            scheduleHide()
            return
        }

        guard AXIsProcessTrusted(),
              !accessibilityLookupInFlight,
              let dock = NSRunningApplication.runningApplications(
                withBundleIdentifier: "com.apple.dock"
              ).first,
              let quartzPoint = CGEvent(source: nil)?.location else {
            if !AXIsProcessTrusted() { scheduleHide() }
            return
        }
        accessibilityLookupInFlight = true
        let dockPID = dock.processIdentifier
        accessibilityQueue.async { [weak self] in
            let identity = Self.dockIdentity(
                at: quartzPoint,
                dockProcessIdentifier: dockPID
            )
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.accessibilityLookupInFlight = false
                guard self.isMonitoring,
                      self.isNearAppleDock(NSEvent.mouseLocation),
                      hypot(
                        NSEvent.mouseLocation.x - cocoaPoint.x,
                        NSEvent.mouseLocation.y - cocoaPoint.y
                      ) < 48,
                      let identity,
                      let application = self.runningApplication(
                        matching: identity
                      ) else {
                    self.scheduleHide()
                    return
                }
                self.handleDockHover(application, anchor: NSEvent.mouseLocation)
            }
        }
    }

    private func handleDockHover(
        _ application: NSRunningApplication,
        anchor: NSPoint
    ) {
        hideWorkItem?.cancel()
        hideWorkItem = nil
        guard hoveredProcessIdentifier != application.processIdentifier else {
            return
        }

        hoveredProcessIdentifier = application.processIdentifier
        hoverWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self, weak application] in
            guard let self, let application,
                  self.hoveredProcessIdentifier == application.processIdentifier
            else { return }
            self.present(application: application, anchor: anchor)
        }
        hoverWorkItem = work
        DispatchQueue.main.asyncAfter(
            deadline: .now() + store.windowPreviewDelay,
            execute: work
        )
    }

    private func present(
        application: NSRunningApplication,
        anchor: NSPoint
    ) {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil

        if panel == nil {
            panel = DockWindowPreviewPanel(
                service: service,
                onClose: { [weak self] in self?.closePanel() }
            )
        }

        panel?.present(
            near: anchor,
            screen: NSScreen.screens.first(where: { $0.frame.contains(anchor) })
                ?? NSScreen.main,
            maximumItems: store.windowPreviewLimit
        )

        Task {
            await service.loadWindows(
                for: application,
                limit: store.windowPreviewLimit
            )
            panel?.updateLayout(
                near: anchor,
                screen: NSScreen.screens.first(where: { $0.frame.contains(anchor) })
                    ?? NSScreen.main,
                itemCount: service.windows.count
            )
        }

        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(
            withTimeInterval: 1.5,
            repeats: true
        ) { [weak self, weak application] _ in
            Task { @MainActor [weak self, weak application] in
                guard let self, let application,
                      self.hoveredProcessIdentifier == application.processIdentifier
                else { return }
                await self.service.loadWindows(
                    for: application,
                    limit: self.store.windowPreviewLimit,
                    force: true
                )
            }
        }
    }

    private func scheduleHide() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        guard panel != nil, hideWorkItem == nil else {
            if panel == nil { hoveredProcessIdentifier = nil }
            return
        }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.hideWorkItem = nil
            let pointer = NSEvent.mouseLocation
            if let panel = self.panel,
               panel.frame.insetBy(dx: -12, dy: -12).contains(pointer) {
                return
            }
            self.closePanel()
        }
        hideWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.24, execute: work)
    }

    private func closePanel() {
        hoverWorkItem?.cancel()
        hoverWorkItem = nil
        hideWorkItem?.cancel()
        hideWorkItem = nil
        refreshTimer?.invalidate()
        refreshTimer = nil
        panel?.orderOut(nil)
        panel = nil
        hoveredProcessIdentifier = nil
        macSpacesHoveredProcessIdentifier = nil
        service.clear()
    }

    private func isNearAppleDock(_ point: NSPoint) -> Bool {
        guard let screen = NSScreen.screens.first(
            where: { $0.frame.contains(point) }
        ) else { return false }
        let hiddenDockRevealDepth: CGFloat = 64
        let orientation = UserDefaults(suiteName: "com.apple.dock")?
            .string(forKey: "orientation") ?? "bottom"
        switch orientation {
        case "left":
            let reserved = screen.visibleFrame.minX - screen.frame.minX
            return point.x <= screen.frame.minX
                + max(hiddenDockRevealDepth, reserved + 24)
        case "right":
            let reserved = screen.frame.maxX - screen.visibleFrame.maxX
            return point.x >= screen.frame.maxX
                - max(hiddenDockRevealDepth, reserved + 24)
        default:
            let reserved = screen.visibleFrame.minY - screen.frame.minY
            return point.y <= screen.frame.minY
                + max(hiddenDockRevealDepth, reserved + 24)
        }
    }

    nonisolated private static func dockIdentity(
        at location: CGPoint,
        dockProcessIdentifier: pid_t
    ) -> DockHitIdentity? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.12)
        var hitElement: AXUIElement?
        guard AXUIElementCopyElementAtPosition(
            system,
            Float(location.x),
            Float(location.y),
            &hitElement
        ) == .success,
        let hitElement else { return nil }

        var hitPID: pid_t = 0
        AXUIElementGetPid(hitElement, &hitPID)
        guard hitPID == dockProcessIdentifier else { return nil }

        var element: AXUIElement? = hitElement
        for _ in 0..<6 {
            guard let current = element else { break }
            if let identity = dockIdentity(forDockElement: current) {
                return identity
            }

            var parentValue: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                current,
                kAXParentAttribute as CFString,
                &parentValue
            ) == .success,
            let parentValue,
            CFGetTypeID(parentValue) == AXUIElementGetTypeID() else {
                break
            }
            element = unsafeBitCast(parentValue, to: AXUIElement.self)
        }
        return nil
    }

    nonisolated private static func dockIdentity(
        forDockElement element: AXUIElement
    ) -> DockHitIdentity? {
        var subroleValue: CFTypeRef?
        AXUIElementCopyAttributeValue(
            element,
            kAXSubroleAttribute as CFString,
            &subroleValue
        )
        if let subrole = subroleValue as? String,
           !subrole.localizedCaseInsensitiveContains("application") {
            return nil
        }

        var urlValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element,
            kAXURLAttribute as CFString,
            &urlValue
        ) == .success,
        let url = urlValue as? URL,
        let bundleIdentifier = Bundle(url: url)?.bundleIdentifier {
            return DockHitIdentity(
                bundleIdentifier: bundleIdentifier,
                title: nil
            )
        }

        var titleValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXTitleAttribute as CFString,
            &titleValue
        ) == .success,
        let title = titleValue as? String else { return nil }

        return DockHitIdentity(bundleIdentifier: nil, title: title)
    }

    private func runningApplication(
        matching identity: DockHitIdentity
    ) -> NSRunningApplication? {
        if let bundleIdentifier = identity.bundleIdentifier,
           let application = NSRunningApplication.runningApplications(
            withBundleIdentifier: bundleIdentifier
           ).first {
            return application
        }
        guard let title = identity.title else { return nil }
        return NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular
                && $0.localizedName?.localizedCaseInsensitiveCompare(title) == .orderedSame
        }
    }
}

private final class DockWindowPreviewPanel: NSPanel {
    private let service: WindowPreviewService
    private let onClose: () -> Void
    private var anchor = NSPoint.zero

    init(service: WindowPreviewService, onClose: @escaping () -> Void) {
        self.service = service
        self.onClose = onClose
        super.init(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        collectionBehavior = [
            .canJoinAllSpaces,
            .transient,
            .fullScreenAuxiliary,
            .ignoresCycle
        ]
        contentView = NSHostingView(
            rootView: WindowPreviewStripView(
                service: service,
                onClose: onClose
            )
        )
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func present(
        near anchor: NSPoint,
        screen: NSScreen?,
        maximumItems: Int
    ) {
        self.anchor = anchor
        updateLayout(
            near: anchor,
            screen: screen,
            itemCount: min(maximumItems, max(1, service.windows.count))
        )
        orderFrontRegardless()
    }

    func updateLayout(
        near anchor: NSPoint,
        screen: NSScreen?,
        itemCount: Int
    ) {
        guard let screen else { return }
        let visible = screen.visibleFrame
        let columns = min(max(1, itemCount), 4)
        let rows = itemCount > 4 ? 2 : 1
        let width = min(
            visible.width - 24,
            CGFloat(columns) * 220 + CGFloat(columns - 1) * 10 + 24
        )
        let height = CGFloat(rows) * 144 + CGFloat(rows - 1) * 10 + 58
        let orientation = UserDefaults(suiteName: "com.apple.dock")?
            .string(forKey: "orientation") ?? "bottom"
        let x: CGFloat
        let y: CGFloat
        switch orientation {
        case "left":
            x = min(visible.maxX - width - 12, anchor.x + 32)
            y = min(
                max(anchor.y - height / 2, visible.minY + 12),
                visible.maxY - height - 12
            )
        case "right":
            x = max(visible.minX + 12, anchor.x - width - 32)
            y = min(
                max(anchor.y - height / 2, visible.minY + 12),
                visible.maxY - height - 12
            )
        default:
            x = min(
                max(anchor.x - width / 2, visible.minX + 12),
                visible.maxX - width - 12
            )
            y = min(
                max(visible.minY + 12, anchor.y + 32),
                visible.maxY - height - 12
            )
        }
        setFrame(NSRect(x: x, y: y, width: width, height: height), display: true)
    }
}

private struct WindowPreviewStripView: View {
    @ObservedObject var service: WindowPreviewService
    @ObservedObject private var theme = ThemeStore.shared
    let onClose: () -> Void

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: 10),
            count: min(max(service.windows.count, 1), 4)
        )
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                if let icon = service.applicationIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text(service.applicationName.isEmpty ? "Windows" : service.applicationName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text("\(service.windows.count) window\(service.windows.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 22, height: 22)
                }
                .buttonStyle(.plain)
                .background(.primary.opacity(0.06), in: Circle())
            }

            if service.isLoading && service.windows.isEmpty {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Loading live windows…")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let message = service.errorMessage,
                      service.windows.isEmpty {
                VStack(spacing: 7) {
                    Image(systemName: "rectangle.on.rectangle.slash")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(theme.dock.accent)
                    Text(message)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(service.windows) { preview in
                        Button {
                            service.activate(preview)
                            onClose()
                        } label: {
                            WindowPreviewCard(preview: preview)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .padding(12)
        .background {
            ZStack {
                VisualEffectView(material: .hudWindow)
                theme.dock.surface.opacity(0.78)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(theme.dock.border.opacity(0.72), lineWidth: 1)
        }
    }
}

private struct WindowPreviewCard: View {
    let preview: WindowPreviewItem
    @ObservedObject private var theme = ThemeStore.shared
    @State private var isHovering = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(.black.opacity(0.22))

                if let image = preview.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                } else if let icon = preview.appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .frame(width: 48, height: 48)
                }

                if !preview.isOnScreen {
                    Text("HIDDEN")
                        .font(.system(size: 8, weight: .bold, design: .monospaced))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.68), in: Capsule())
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                        .padding(7)
                }
            }
            .frame(height: 104)

            Text(preview.title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(7)
        .background(
            isHovering
                ? theme.dock.accent.opacity(0.16)
                : Color.primary.opacity(0.045),
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(
                    isHovering
                        ? theme.dock.accent.opacity(0.72)
                        : Color.primary.opacity(0.08),
                    lineWidth: 1
                )
        }
        .contentShape(Rectangle())
        .onHover { isHovering = $0 }
    }
}
