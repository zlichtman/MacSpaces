import AppKit
import SwiftUI

/// Notifications that come through the notch: a card slides down under the
/// camera for a few seconds (longer while the pointer rests on it). Messages get
/// a reply field right in the card; a coding agent that needs you gets a card
/// that stays until it's working again, with a button back to its app; other
/// apps' notifications open their app.
/// Cards are hidden from screen sharing and recordings, and while the screen is locked.
@MainActor
final class NotchBanners: ObservableObject {
    static let shared = NotchBanners()

    struct Banner: Identifiable, Equatable {
        enum Source: Equatable {
            case message(handle: String, chatID: String = "")
            case app(bundleID: String)
            /// A coding agent waiting for you.
            case agent(sessionID: String, appBundleID: String)
        }
        let id = UUID()
        let source: Source
        let title: String
        let detail: String
        /// Stays until dismissed or no longer relevant (an agent waiting for you).
        var persistent = false
    }

    @Published private(set) var current: Banner?
    @Published var showsText: Bool = UserDefaults.standard.object(forKey: "banners.showText") as? Bool ?? true {
        didSet { UserDefaults.standard.set(showsText, forKey: "banners.showText") }
    }
    private var queue: [Banner] = []
    private var panel: NSPanel?
    private var hideWork: DispatchWorkItem?
    var hovering = false { didSet { if !hovering { scheduleHide() } } }
    /// Typing a reply in the card: it stays, grows for the field and takes the keyboard.
    @Published private(set) var replying = false
    @Published private(set) var sending = false
    @Published var replyText = ""
    /// The conversation the open reply was started for; the reply goes only there.
    private var replyChat: String?
    static let size = NSSize(width: 380, height: 92)
    static let replySize = NSSize(width: 380, height: 124)
    static let showsFor: TimeInterval = 6

    func post(_ banner: Banner) {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" || ProcessInfo.processInfo.environment["MACSPACES_FEATURE_QA"] != nil else { return }
        queue.append(banner)
        if current == nil { next() }
    }

    func dismiss() {
        hideWork?.cancel()
        if replying { endReply() }
        current = nil
        next()
    }

    /// Opens the reply field in the card and gives it the keyboard.
    func beginReply() {
        guard case .message(_, let chatID)? = current?.source, !chatID.isEmpty else { return }
        hideWork?.cancel()
        replyChat = chatID
        replying = true
        replyText = ""
        if let panel {
            panel.setFrame(frame(for: Self.replySize), display: true, animate: true)
            panel.makeKey()
        }
    }

    func endReply() {
        replying = false
        sending = false
        replyChat = nil
        panel?.resignKey()
        if let panel { panel.setFrame(frame(for: Self.size), display: true, animate: true) }
    }

    /// Sends the reply to that exact conversation, then closes the card.
    func sendReply() {
        guard replying, let chatID = replyChat, case .message(_, chatID)? = current?.source, !sending else { return }
        sending = true
        AppServices.shared.messages.quickReply(replyText, toChat: chatID) { [weak self] accepted in
            guard let self else { return }
            self.sending = false
            if accepted { self.dismiss() }
        }
    }

    /// Withdraws an agent's card once it's been answered elsewhere.
    func withdraw(agentSession session: String) {
        queue.removeAll { if case .agent(let id, _) = $0.source { return id == session }; return false }
        if case .agent(let id, _)? = current?.source, id == session { dismiss() }
    }

    func activate(_ banner: Banner) {
        switch banner.source {
        case .message(let handle, _):
            let address = handle.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? handle
            if let url = URL(string: "imessage:\(address)") { NSWorkspace.shared.open(url) }
        case .app(let bundleID), .agent(_, let bundleID):
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
        if current?.persistent == true { Haptics.tap() }
        scheduleHide()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        guard current?.persistent != true, !replying else { return }
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
        panel.setFrame(frame(for: Self.size), display: true)
        panel.orderFrontRegardless()
    }

    /// The card's frame under the notch for a size (it grows downward).
    private func frame(for size: NSSize) -> NSRect {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) ?? NSScreen.main else {
            return NSRect(origin: .zero, size: size)
        }
        let top = screen.frame.maxY - max(screen.safeAreaInsets.top, NSStatusBar.system.thickness)
        return NSRect(x: screen.frame.midX - size.width / 2, y: top - size.height - 4, width: size.width, height: size.height)
    }

    private func make() -> NSPanel {
        let panel = BannerPanel(contentRect: NSRect(origin: .zero, size: Self.size),
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

/// A non-activating panel that can still take the keyboard for a quick reply.
private final class BannerPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

struct NotchBannerView: View {
    @ObservedObject var banners: NotchBanners
    @ObservedObject private var theme = ThemeStore.shared
    @FocusState private var fieldFocused: Bool

    var body: some View {
        Group {
            if let banner = banners.current {
                VStack(spacing: 10) {
                    HStack(spacing: 12) {
                        icon(banner)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(banner.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(banners.showsText ? banner.detail : "New notification")
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        actions(banner)
                        Button { banners.dismiss() } label: { Image(systemName: "xmark") }
                            .buttonStyle(WidgetChipStyle(height: 24)).accessibilityLabel("Dismiss")
                    }
                    if banners.replying {
                        HStack(spacing: 8) {
                            TextField("Reply", text: $banners.replyText)
                                .textFieldStyle(.plain).font(.system(size: 12))
                                .focused($fieldFocused)
                                .onSubmit { banners.sendReply() }
                                .onExitCommand { banners.endReply() }
                                .padding(.horizontal, 12).padding(.vertical, 7)
                                .background(Color.primary.opacity(0.08), in: Capsule())
                            Button { banners.sendReply() } label: {
                                Image(systemName: banners.sending ? "ellipsis" : "arrow.up").font(.system(size: 12, weight: .bold))
                                    .frame(width: 28, height: 28).foregroundStyle(.white)
                                    .background(Color(red: 0.2, green: 0.5, blue: 1), in: Circle())
                            }
                            .buttonStyle(.plain)
                            .disabled(banners.replyText.trimmingCharacters(in: .whitespaces).isEmpty || banners.sending)
                            .accessibilityLabel("Send reply")
                        }
                        .transition(.move(edge: .top).combined(with: .opacity))
                        .onAppear { DispatchQueue.main.async { fieldFocused = true } }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 12)
                .contentShape(Rectangle())
                .onTapGesture { if !banners.replying { banners.activate(banner) } }
                .id(banner.id)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(theme.notch.surface)
        .foregroundStyle(theme.nookForeground)
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 10, bottomLeadingRadius: 24, bottomTrailingRadius: 24, topTrailingRadius: 10))
        .onHover { banners.hovering = $0 }
        .animation(.spring(response: 0.35, dampingFraction: 0.85), value: banners.current?.id)
        .animation(.spring(response: 0.3, dampingFraction: 0.85), value: banners.replying)
        .preferredColorScheme(theme.notch.colorScheme)
    }

    @ViewBuilder
    private func actions(_ banner: NotchBanners.Banner) -> some View {
        switch banner.source {
        case .message(_, let chatID) where !chatID.isEmpty:
            if !banners.replying {
                Button("Reply") { banners.beginReply() }
                    .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
            }
        case .message:
            Button("Reply") { banners.activate(banner) }
                .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
        case .agent(_, let bundleID):
            Button(bundleID.isEmpty ? "Open" : "Go") { banners.activate(banner) }
                .buttonStyle(WidgetChipStyle(prominent: true, height: 26))
        case .app:
            EmptyView()
        }
    }

    @ViewBuilder
    private func icon(_ banner: NotchBanners.Banner) -> some View {
        switch banner.source {
        case .message(let handle, _):
            // The sender's photo from Contacts, with a small Messages badge; the Messages icon otherwise.
            if let photo = AppServices.shared.messages.contactPhotos[handle] {
                Image(nsImage: photo).resizable().scaledToFill().frame(width: 38, height: 38).clipShape(Circle())
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: "message.fill").font(.system(size: 8)).foregroundStyle(.white)
                            .frame(width: 15, height: 15).background(Color.green, in: Circle())
                            .overlay(Circle().stroke(theme.notch.surface, lineWidth: 1.5)).offset(x: 3, y: 3)
                    }
            } else {
                Image(systemName: "message.fill").font(.system(size: 18)).foregroundStyle(.white)
                    .frame(width: 38, height: 38).background(Color.green, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        case .app(let bundleID):
            AppIcon(bundleID: bundleID).frame(width: 38, height: 38)
        case .agent(_, let bundleID):
            if bundleID.isEmpty {
                Image(systemName: "sparkles").font(.system(size: 18)).foregroundStyle(.orange)
                    .frame(width: 38, height: 38).background(Color.orange.opacity(0.15), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            } else {
                AppIcon(bundleID: bundleID).frame(width: 38, height: 38)
            }
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
