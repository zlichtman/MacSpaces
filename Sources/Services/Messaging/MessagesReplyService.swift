import AppKit
import Combine
import CoreGraphics

/// Lightweight display state; observing it never starts message access.
@MainActor final class MessageActivityState: ObservableObject {
    static let shared = MessageActivityState()
    @Published var count = 0
}

@MainActor final class MessagesReplyService: ObservableObject {
    @Published private(set) var conversations: [MessageConversation] = []
    @Published var reply = MessageReplyState() { didSet { saveDraft() } }
    @Published private(set) var incoming: [IncomingMessage] = [] { didSet { MessageActivityState.shared.count = incoming.count } }
    @Published private(set) var incomingEnabled = UserDefaults.standard.bool(forKey: "messages.incomingEnabled")
    @Published private(set) var incomingNeedsAccess = false
    @Published private(set) var incomingNeedsAttention = false
    @Published private(set) var incomingStatus = "Incoming messages are off."
    @Published private(set) var sessionHidden = false
    private var incomingTask: Task<Void, Never>?
    private var demanded = false
    private var lockObservers: [NSObjectProtocol] = []
    func start() {
        demanded = true
        let center = DistributedNotificationCenter.default()
        if lockObservers.isEmpty {
            for name in ["com.apple.screenIsLocked", "com.apple.screenIsUnlocked"] {
                lockObservers.append(center.addObserver(forName: .init(name), object: nil, queue: .main) { [weak self] note in
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        self.sessionHidden = note.name.rawValue == "com.apple.screenIsLocked"
                        self.incoming = []
                    }
                })
            }
        }
        beginIncoming()
    }
    func stop() {
        demanded = false; incomingTask?.cancel(); incomingTask = nil; incoming = []
        for observer in lockObservers { DistributedNotificationCenter.default().removeObserver(observer) }
        lockObservers = []
    }
    func setIncomingEnabled(_ enabled: Bool) {
        incomingEnabled = enabled
        incomingNeedsAttention = false
        incomingNeedsAccess = false
        UserDefaults.standard.set(enabled, forKey: "messages.incomingEnabled")
        // Incoming Messages keeps the service running even without the widget on Home.
        AppServices.shared.reconcileDemand(app: AppSettings.shared, nook: NookSettings.shared)
        incomingTask?.cancel(); incomingTask = nil; incoming = []
        if enabled { beginIncoming() } else { incomingStatus = "Incoming messages are off." }
    }
    func retryIncoming() { incomingTask?.cancel(); incomingTask = nil; beginIncoming() }
    func dismissIncoming(_ message: IncomingMessage) { incoming.removeAll { $0.id == message.id } }
    func selectIncoming(_ message: IncomingMessage) -> Bool {
        // Never route by display name or fuzzy phone matching.
        guard let exact = conversations.first(where: { $0.id == message.conversationID }) else {
            status = "Open Messages to reply: this conversation has not been verified."; return false
        }
        guard reply.phase == .editing, reply.select(exact) else {
            status = "Finish or discard the current draft before replying to another conversation."; return false
        }
        dismissIncoming(message); return true
    }
    func incomingTitle(_ message: IncomingMessage) -> String {
        let title = conversations.first(where: { $0.id == message.conversationID })?.title ?? message.sender
        return ContactNames.isHandle(title) ? (contactNames[message.sender] ?? title) : title
    }
    /// Names found in Contacts for senders' handles this session.
    @Published private(set) var contactNames: [String: String] = [:]
    private func beginIncoming() {
        guard demanded, incomingEnabled, incomingTask == nil,
              Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        incomingNeedsAttention = false
        incomingNeedsAccess = false
        incomingStatus = "Checking incoming Messages access…"
        let reader = IncomingMessagesReader(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db"))
        incomingTask = Task { [weak self] in
            var cursor: Int64?
            while !Task.isCancelled {
                do {
                    let snapshot = try await Task.detached(priority: .utility) { try reader.read(after: cursor) }.value
                    guard !Task.isCancelled, let self else { return }
                    let session = CGSessionCopyCurrentDictionary() as? [String: Any]
                    self.sessionHidden = session == nil || session?["CGSSessionScreenIsLocked"] as? Bool == true || session?["kCGSessionOnConsoleKey"] as? Bool == false
                    cursor = snapshot.cursor
                    if self.sessionHidden { self.incoming = [] }
                    else if !snapshot.messages.isEmpty {
                        self.incoming = Array((snapshot.messages + self.incoming).prefix(20))
                        self.connect()
                        // Each new message also comes through the notch, under the
                        // sender's name from Contacts when the handle is a number or address.
                        for message in snapshot.messages.reversed() {
                            var title = self.incomingTitle(message)
                            if ContactNames.isHandle(title), let name = await ContactNames.shared.name(for: message.sender) {
                                title = name
                                self.contactNames[message.sender] = name
                            }
                            NotchBanners.shared.post(.init(source: .message(handle: message.sender),
                                                           title: title, detail: message.text))
                        }
                    }
                    self.incomingStatus = "Listening for new Messages."
                } catch IncomingMessagesReader.Failure.busy {
                    guard !Task.isCancelled, let self else { return }
                    self.incomingStatus = "Messages is updating. Retrying incoming reception…"
                } catch {
                    guard !Task.isCancelled, let self else { return }
                    self.incomingNeedsAccess = (error as? IncomingMessagesReader.Failure) == .access
                    self.incoming = []; self.incomingNeedsAttention = true; self.incomingStatus = error.localizedDescription
                    // No repeated protected reads when access is denied.
                    return
                }
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }
    private var draftStorageFailed = false
    private let draftURL: URL
    @Published private(set) var status = "Connect only when you want to reply. Messages automation access is required."
    @Published private(set) var loading = false
    init() {
        let root = Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces"
            ? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSpaces")
            : FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures/" + (Bundle.main.bundleIdentifier ?? "tests"))
        draftURL = root.appendingPathComponent("message-draft-v1.json")
        do {
            if FileManager.default.fileExists(atPath: draftURL.path) {
                guard (try draftURL.resourceValues(forKeys: [.fileSizeKey])).fileSize ?? Int.max <= 128 * 1024 else { throw CocoaError(.fileReadTooLarge) }
                reply = try JSONDecoder().decode(MessageReplyState.self, from: Data(contentsOf: draftURL))
                reply.recoverAfterRelaunch()
                if reply.phase == .uncertain { status = "The previous send was interrupted. Check Messages before starting another reply." }
            }
        } catch { draftStorageFailed = true; status = "The saved message draft could not be read. It was preserved; sending is disabled." }
    }
    private func saveDraft() {
        guard !draftStorageFailed else { return }
        do {
            let data = try JSONEncoder().encode(reply)
            guard data.count <= 128 * 1024 else { throw CocoaError(.fileWriteOutOfSpace) }
            try FileManager.default.createDirectory(at: draftURL.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: draftURL.deletingLastPathComponent().path)
            try data.write(to: draftURL, options: [.atomic, .completeFileProtectionUnlessOpen])
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: draftURL.path)
        } catch { draftStorageFailed = true; status = "The draft could not be saved; nothing further will be sent. " + error.localizedDescription }
    }
    func connect() {
        guard !loading, reply.phase != .sending else { return }
        loading = true
        AppleScriptRunner.run(MessagesScripts.discovery) { [weak self] result in
            guard let self else { return }; self.loading = false
            guard !result.failed, let list = result.descriptor else {
                self.status = "Messages access is unavailable. Open Messages and allow automation access, then try Connect again."; return
            }
            var found: [MessageConversation] = []
            for index in 0..<list.numberOfItems {
                guard let row = list.atIndex(index + 1), let id = row.atIndex(1)?.stringValue,
                      let members = row.atIndex(3), let labels = row.atIndex(4) else { continue }
                let memberIDs = (0..<members.numberOfItems).compactMap { members.atIndex($0 + 1)?.stringValue }
                let memberLabels = (0..<labels.numberOfItems).compactMap { labels.atIndex($0 + 1)?.stringValue }
                guard !id.isEmpty, !memberIDs.isEmpty else { continue }
                let title = memberLabels.count == 1 ? memberLabels[0] : (row.atIndex(2)?.stringValue ?? memberLabels.joined(separator: ", "))
                found.append(.init(id: id, title: title, participantIDs: memberIDs, participantLabels: memberLabels))
            }
            self.conversations = found
            self.status = found.isEmpty ? "No available Messages conversations." : "Choose the exact recipients, then write your reply."
        }
    }
    func send() {
        guard !draftStorageFailed, let selected = reply.recipient,
              let current = conversations.first(where: { $0.id == selected.id }), reply.begin(current: current) else { return }
        guard !draftStorageFailed else { reply.finish(accepted: false); return }
        let body = reply.draft
        status = "Sending to Messages…"
        AppleScriptRunner.runHandler(MessagesScripts.reply, name: "replyToConversation", arguments: [.text(selected.id), .strings(selected.participantIDs), .text(body)]) { [weak self] result in
            guard let self else { return }
            let accepted = !result.failed && result.descriptor?.stringValue == "submitted"
            self.reply.finish(accepted: accepted)
            self.status = accepted ? "Submitted to Messages. Delivery status is shown there." : "Delivery is uncertain. Your draft is retained. Check Messages before starting a new reply; nothing is retried automatically."
        }
    }
    #if DEBUG
    func setIncomingAccessPreview(needsAccess: Bool) {
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.FeatureQA")
        incomingEnabled = true
        incomingNeedsAccess = needsAccess
        incomingNeedsAttention = needsAccess
        incomingStatus = needsAccess ? IncomingMessagesReader.Failure.access.localizedDescription : "Listening for new Messages."
    }
    #endif
    func openIncomingAccessSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") else { return }
        NSWorkspace.shared.open(url)
    }
    func openMessages() {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.apple.MobileSMS") { NSWorkspace.shared.openApplication(at: url, configuration: .init()) }
    }
}
