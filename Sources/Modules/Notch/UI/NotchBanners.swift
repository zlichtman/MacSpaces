import AppKit
import SwiftUI

/// Notifications that come through the notch: a card slides down under the
/// camera for a few seconds (longer while the pointer rests on it). Messages get
/// a Reply button; other apps' notifications open their app. Cards are hidden
/// from screen sharing and recordings, and while the screen is locked.
@MainActor
final class NotchBanners: ObservableObject {
    static let shared = NotchBanners()

    struct Banner: Identifiable, Equatable {
        enum Source: Equatable { case message(handle: String), app(bundleID: String) }
        let id = UUID()
        let source: Source
        let title: String
        let detail: String
    }

    @Published private(set) var current: Banner?
    @Published var showsText: Bool = UserDefaults.standard.object(forKey: "banners.showText") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsText, forKey: "banners.showText") }
    }
    private var queue: [Banner] = []
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    var hovering = false { didSet { if !hovering { scheduleHide() } } }
    static let size = NSSize(width: 380, height: 92)
    static let showsFor: TimeInterval = 6

    func post(_ banner: Banner) {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" || ProcessInfo.processInfo.environment["MACSPACES_FEATURE_QA"] != nil else { return }
        queue.append(banner)
        if current == nil { next() }
    }

    func dismiss() {
        hideWork?.cancel()
        current = nil
        next()
    }

    func activate(_ banner: Banner) {
        switch banner.source {
        case .message(let handle):
            let address = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
            if let url = URL(string: "imessage:\(address)") { NSWorkspace.shared.open(url) }
        case .app(let bundleID):
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) {
                NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            }
        }
        dismiss()
    }

    private func next() {
        guard !queue.isEmpty else { panel?.orderOut(nil); return }
        current = queue.removeFirst()
        show()
        scheduleHide()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.hovering else { return }
            self.dismiss()
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.showsFor, execute: work)
    }

    private func show() {
        let panel = self.panel ?? make()
        self.panel = panel
        let screen = NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main
        if let screen {
            let top = screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
            panel.setFrameOrigin(NSPoint(x: screen.frame.midX - Self.size.width / 2, y: top - Self.size.height - 4))
        }
        panel.orderFrontRegardless()
    }

    private func make() -> NSPanel {
        let panel = NSPanel(contentRect: NSRect(origin: .zero, size: Self.size),
                            styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.sharingType = .none
        panel.contentView = NSHostingView(rootView: NotchBannerView(banners: self))
        return panel
    }
}

struct NotchBannerView: View {
    @ObservedObject var banners: NotchBanners
    @ObservedObject private var theme = ThemeStore.shared

    var body: some View {
        Group {
            if let banner = banners.current {
                HStack(spacing: 12) {
                    icon(banner)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(banner.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                        Text(banners.showsText ? banner.detail : "New notification")
                            .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if case .message = banner.source {
                        Button("Reply") { banners.activate(banner) }
                            .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
                    }
                    Button { banners.dismiss() } label: { Image(systemName: "xmark") }
                        .buttonStyle(WidgetChipStyle(height: 24)).accessibilityLabel("Dismiss")
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture { banners.activate(banner) }
                .id(banner.id)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(width: NotchBanners.size.width, height: NotchBanners.size.height)
        .background(theme.notch.surface)
        .foregroundStyle(theme.nookForeground)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 10))
        .onHover { banners.hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: banners.current?.id)
        .preferredColorScheme(theme.notch.colorScheme)
    }

    @ViewBuilder
    private func icon(_ banner: NotchBanners.Banner) -> some View {
        switch banner.source {
        case .message:
            Image(systemName: "message.fill").font(.system(size: 18)).foregroundStyle(.white)
                .frame(width: 38, height: 38).background(Color.green, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        case .app(let bundleID):
            AppIcon(bundleID: bundleID).frame(width: 38, height: 38)
        }
    }
}

/// Watches Notification Center's store for other apps' notifications and shows
/// them through the notch. Off until turned on; needs Full Disk Access.
@MainActor
final class SystemNotificationsFeed: ObservableObject {
    static let shared = SystemNotificationsFeed()
    @Published private(set) var isEnabled = UserDefaults.standard.bool(forKey: "banners.fromApps")
    @Published private(set) var status = ""
    @Published private(set) var needsAccess = false
    private var task: Task<Void, Never>?

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        UserDefaults.standard.set(enabled, forKey: "banners.fromApps")
        task?.cancel(); task = nil
        if enabled { start() } else { status = ""; needsAccess = false }
    }

    func start() {
        guard isEnabled, task == nil, Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        let reader = SystemNotificationsReader(url: SystemNotificationsReader.defaultURL)
        status = "Checking access…"
        task = Task { [weak self] in
            var cursor: Int64?
            while !Task.isCancelled {
                do {
                    let snapshot = try await Task.detached(priority: .utility) { try reader.read(after: cursor) }.value
                    guard let self, !Task.isCancelled else { return }
                    cursor = snapshot.cursor
                    self.status = "Showing notifications in the notch."
                    self.needsAccess = false
                    let locked = (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true
                    // Messages has its own banner with Reply when incoming Messages is on.
                    let skip: Set<String> = UserDefaults.standard.bool(forKey: "messages.incomingEnabled")
                        ? ["com.apple.MobileSMS", "dev.opensource.MacSpaces"] : ["dev.opensource.MacSpaces"]
                    for item in snapshot.notifications.reversed() where !locked && !skip.contains(item.bundleID) {
                        let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.bundleID)
                            .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") }
                        let title = item.title.isEmpty ? (app ?? "Notification") : item.title
                        let detail = [item.subtitle, item.body].filter { !$0.isEmpty }.joined(separator: " — ")
                        NotchBanners.shared.post(.init(source: .app(bundleID: item.bundleID), title: title, detail: detail))
                    }
                } catch IncomingMessagesReader.Failure.busy {
                    // Notification Center is writing; try again shortly.
                } catch {
                    guard let self else { return }
                    self.needsAccess = (error as? IncomingMessagesReader.Failure) == .access
                    self.status = self.needsAccess
                        ? "Needs Full Disk Access: allow MacSpaces in System Settings → Privacy & Security, then turn this on again."
                        : "This version of macOS stores notifications differently, so they can't be shown yet."
                    self.task = nil
                    return
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
}
