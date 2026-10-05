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
                            NotchBanners.shared.post(.init(source: .message(handle: message.sender, chatID: message.conversationID),
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
    private var afterConnect: [() -> Void] = []
    func connect(then action: (() -> Void)? = nil) {
        if let action { afterConnect.append(action) }
        guard !loading, reply.phase != .sending else { return }
        loading = true
        AppleScriptRunner.run(MessagesScripts.discovery) { [weak self] result in
            guard let self else { return }; self.loading = false
            defer { let pending = self.afterConnect; self.afterConnect = []; pending.forEach { $0() } }
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
    func send(completion: ((Bool) -> Void)? = nil) {
        guard !draftStorageFailed, let selected = reply.recipient,
              let current = conversations.first(where: { $0.id == selected.id }), reply.begin(current: current) else { completion?(false); return }
        guard !draftStorageFailed else { reply.finish(accepted: false); completion?(false); return }
        let body = reply.draft
        status = "Sending to Messages…"
        AppleScriptRunner.runHandler(MessagesScripts.reply, name: "replyToConversation", arguments: [.text(selected.id), .strings(selected.participantIDs), .text(body)]) { [weak self] result in
            guard let self else { return }
            let accepted = !result.failed && result.descriptor?.stringValue == "submitted"
            self.reply.finish(accepted: accepted)
            completion?(accepted)
            if accepted { self.refreshInbox() }
            self.status = accepted ? "Submitted to Messages. Delivery status is shown there." : "Delivery is uncertain. Your draft is retained. Check Messages before starting a new reply; nothing is retried automatically."
        }
    }
    // MARK: Quick replies and the inbox

    /// Sends `text` to one exact conversation (the chat's own id, never a name or
    /// fuzzy number match), connecting to Messages first if needed.
    func quickReply(_ text: String, toChat chatID: String, completion: @escaping (Bool) -> Void) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { completion(false); return }
        let go = { [weak self] in
            guard let self, let conversation = self.conversations.first(where: { $0.id == chatID }) else {
                self?.status = "Open Messages to reply: this conversation has not been verified."; completion(false); return
            }
            guard self.reply.phase != .sending else { completion(false); return }
            if self.reply.phase != .editing || self.reply.recipient != conversation { self.reply.newDraft() }
            guard self.reply.select(conversation) else { completion(false); return }
            self.reply.draft = body
            self.send(completion: completion)
        }
        if conversations.contains(where: { $0.id == chatID }) { go() } else { connect(then: go) }
    }

    @Published private(set) var inbox: [MessageInboxReader.Chat] = []
    @Published private(set) var thread: [MessageInboxReader.Line] = []
    @Published var selectedChat: String? { didSet { if selectedChat != oldValue { thread = []; refreshInbox() } } }
    @Published private(set) var inboxNeedsAccess = false
    private var inboxTask: Task<Void, Never>?
    private var inboxReader: MessageInboxReader {
        MessageInboxReader(url: FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Messages/chat.db"))
    }

    /// While the Messages page shows: the conversation list and the open thread, every few seconds.
    func startInbox() {
        guard inboxTask == nil, Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        inboxTask = Task { [weak self] in
            while !Task.isCancelled {
                self?.refreshInbox()
                do { try await Task.sleep(for: .seconds(3)) } catch { return }
            }
        }
        if conversations.isEmpty { connect() }
    }

    func stopInbox() {
        inboxTask?.cancel(); inboxTask = nil
        inbox = []; thread = []
    }

    func refreshInbox() {
        guard inboxTask != nil else { return }
        let reader = inboxReader, chat = selectedChat
        Task.detached(priority: .utility) { [weak self] in
            do {
                let chats = try reader.chats()
                let lines = try chat.map { try reader.thread($0) } ?? []
                await MainActor.run { [weak self] in
                    guard let self else { return }
                    self.inboxNeedsAccess = false
                    if self.inbox != chats { self.inbox = chats }
                    if self.selectedChat == chat, self.thread != lines { self.thread = lines }
                    if self.selectedChat == nil { self.selectedChat = chats.first?.id }
                }
                for handle in Set(chats.map(\.handle)) where ContactNames.isHandle(handle) {
                    if let name = await ContactNames.shared.name(for: handle) {
                        await MainActor.run { [weak self] in if self?.contactNames[handle] != name { self?.contactNames[handle] = name } }
                    }
                }
            } catch {
                await MainActor.run { [weak self] in self?.inboxNeedsAccess = (error as? IncomingMessagesReader.Failure) == .access }
            }
        }
    }

    /// A conversation's name: the group's, the contact's, or the handle.
    func title(for chat: MessageInboxReader.Chat) -> String {
        if !chat.groupName.isEmpty { return chat.groupName }
        if let verified = conversations.first(where: { $0.id == chat.id })?.title, !ContactNames.isHandle(verified) { return verified }
        return contactNames[chat.handle] ?? (chat.handle.isEmpty ? "Conversation" : chat.handle)
    }

    #if DEBUG
    func setInboxPreview(_ chats: [MessageInboxReader.Chat], thread: [MessageInboxReader.Line]) {
        inbox = chats; self.thread = thread; selectedChat = chats.first?.id; self.thread = thread
    }

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
