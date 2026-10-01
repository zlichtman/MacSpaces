import AppKit
import Foundation

/// The Tsukumo page's connection to Tsukumo's bots over the local bridge (agents channel, version 3;
/// see Sources/Core/Bridge/MacSpacesAgentsContract.swift).
///
/// Everything Tsukumo sends is kept in memory only: never written to disk or logs, never sent
/// anywhere, and dropped when the page leaves the screen. MacSpaces sends only what the person
/// typed or picked. Polling runs only while the page is on screen.
@MainActor
final class TsukumoAgentsClient: ObservableObject {
    static let shared = TsukumoAgentsClient()

    enum Availability: Equatable { case unknown, unavailable, available }

    @Published private(set) var availability: Availability = .unknown
    @Published private(set) var agents: [MacSpacesAgents.Agent] = []
    @Published private(set) var feed: [MacSpacesAgents.FeedItem] = []
    @Published private(set) var approvals: [MacSpacesAgents.Approval] = []
    @Published private(set) var review: MacSpacesAgents.Review?
    @Published private(set) var avatar: NSImage?
    @Published private(set) var error: String?
    @Published private(set) var status: String?
    @Published private(set) var busy = false
    /// A send whose reply was lost. It keeps its request ID so checking it again can never send twice.
    @Published private(set) var pendingSend: MacSpacesAgents.Request?

    /// What the person is typing; kept while the Nook closes.
    @Published var draft = ""
    /// Tagged bots (the chips) for the Together box.
    @Published var tagged: [UUID] = []
    /// The bot shown on its own, or nil for Together.
    @Published var focused: UUID?

    private var epoch: UUID?
    private var cursor: Int?
    private var lastDiscovery: Date?
    private var loop: Task<Void, Never>?
    private var isPreview = false
    private static let keptFeedItems = 100

    // MARK: Availability

    /// Asks Tsukumo whether it offers the agents channel. Cheap when Tsukumo isn't running (the
    /// socket isn't there), and cached for a minute.
    func refreshAvailability(force: Bool = false) {
        guard !isPreview else { return }
        if !force, let lastDiscovery, Date().timeIntervalSince(lastDiscovery) < 60 { return }
        lastDiscovery = Date()
        Task {
            switch await Self.discoverAgentsChannel() {
            case .some(true): availability = .available
            case .some(false): availability = .unavailable
            case .none:
                // Tsukumo is running but not ready (signing in): keep what we knew and ask again soon.
                lastDiscovery = Date().addingTimeInterval(-45)
            }
        }
    }

    /// True or false when Tsukumo answered (or isn't there); nil when it answered with an error,
    /// such as "Sign in to Tsukumo…", which says nothing about the channel.
    nonisolated private static func discoverAgentsChannel() async -> Bool? {
        await Task.detached {
            // Every Tsukumo answers a version 1 discovery and lists its operations in capabilities.
            let request = MacSpacesBridge.Request(version: 1, operation: .discover)
            guard let data = try? JSONEncoder().encode(request),
                  let reply = try? LocalBridgeTransport.exchange(data),
                  let response = try? JSONDecoder().decode(MacSpacesBridge.Response.self, from: reply)
            else { return false }
            if response.error != nil { return nil }
            return response.capabilities?.operations.contains(MacSpacesAgents.capability) == true
        }.value
    }

    // MARK: Page lifecycle

    /// Called when the page appears: loads everything, then long-polls for changes until `stop()`.
    func start() {
        guard !isPreview, loop == nil else { return }
        loop = Task { [weak self] in await self?.run() }
    }

    /// Called when the page leaves the screen: stops polling and drops what Tsukumo sent.
    func stop() {
        loop?.cancel(); loop = nil
        guard !isPreview else { return }
        agents = []; feed = []; approvals = []; review = nil; status = nil; error = nil
        epoch = nil; cursor = nil
    }

    private func run() async {
        if avatar == nil, let hello = try? await call(.init(operation: .hello)),
           let data = hello.kemoSabeAvatar, let image = NSImage(data: data) {
            avatar = image
        }
        while !Task.isCancelled {
            do {
                if epoch == nil {
                    apply(try await call(.init(operation: .list)))
                    try await refreshApprovals()
                }
                let changes = try await call(.init(operation: .changes, epoch: epoch, cursor: cursor, wait: MacSpacesAgents.maxWait))
                let hadChanges = !(changes.agents ?? []).isEmpty || !(changes.removed ?? []).isEmpty || changes.reset == true
                apply(changes)
                if hadChanges { try await refreshApprovals() }
                error = nil
            } catch is CancellationError {
                return
            } catch {
                self.error = error.localizedDescription
                if (error as? AgentsUnavailable) != nil { availability = .unavailable }
                // After an error, wait before trying again.
                try? await Task.sleep(for: .seconds(10))
            }
        }
    }

    private func refreshApprovals() async throws {
        approvals = try await call(.init(operation: .approvals)).approvals ?? []
    }

    private func apply(_ response: MacSpacesAgents.Response) {
        if response.reset == true {
            agents = response.agents ?? []
            feed = response.feed ?? []
        } else {
            for agent in response.agents ?? [] {
                if let index = agents.firstIndex(where: { $0.id == agent.id }) { agents[index] = agent } else { agents.append(agent) }
            }
            let removed = Set(response.removed ?? [])
            agents.removeAll { removed.contains($0.id) }
            appendFeed(response.feed ?? [])
        }
        tagged.removeAll { id in !agents.contains { $0.id == id } }
        if let focused, !agents.contains(where: { $0.id == focused }) { self.focused = nil }
        if let epoch = response.epoch { self.epoch = epoch }
        if let cursor = response.cursor { self.cursor = cursor }
    }

    private func appendFeed(_ items: [MacSpacesAgents.FeedItem]) {
        let known = Set(feed.map(\.id))
        feed.append(contentsOf: items.filter { !known.contains($0.id) })
        if feed.count > Self.keptFeedItems { feed.removeFirst(feed.count - Self.keptFeedItems) }
    }

    // MARK: Actions (each an explicit choice by the person)

    func toggleTag(_ id: UUID) {
        if let index = tagged.firstIndex(of: id) { tagged.remove(at: index) } else { tagged.append(id) }
    }

    func agent(_ id: UUID?) -> MacSpacesAgents.Agent? { id.flatMap { id in agents.first { $0.id == id } } }

    /// Sends the draft: to the focused bot, or to Together with the tagged chips.
    func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !busy, pendingSend == nil, !text.isEmpty else { return }
        let request: MacSpacesAgents.Request = focused.map {
            .init(operation: .send, agents: [$0], text: text)
        } ?? .init(operation: .send, agents: tagged, text: text, together: true)
        perform(request) { [weak self] response in
            self?.draft = ""
            self?.appendFeed(response.feed ?? [])
        }
    }

    /// Asks again with the same request ID: Tsukumo replays its answer and never sends twice.
    func checkPendingSend() {
        guard let pendingSend else { return }
        self.pendingSend = nil
        perform(pendingSend) { [weak self] response in
            self?.draft = ""
            self?.appendFeed(response.feed ?? [])
        }
    }

    func discardPendingSend() { pendingSend = nil; error = nil }

    func answer(_ approval: MacSpacesAgents.Approval, allow: Bool) {
        perform(.init(operation: allow ? .approve : .deny, agent: approval.agent, approval: approval.id)) { [weak self] _ in
            Task { try? await self?.refreshApprovals() }
        }
    }

    func openReview(for agent: UUID) {
        perform(.init(operation: .review, agent: agent)) { [weak self] response in self?.review = response.review }
    }

    func closeReview() { review = nil }

    func acceptReview() {
        guard let review else { return }
        perform(.init(operation: .accept, agent: review.agent, tree: review.tree)) { [weak self] _ in self?.review = nil }
    }

    func requestChanges(_ note: String) {
        guard let review else { return }
        perform(.init(operation: .requestChanges, agent: review.agent, text: note)) { [weak self] _ in self?.review = nil }
    }

    func setFollow(_ agent: UUID, on: Bool) {
        perform(.init(operation: .follow, agent: agent, on: on)) { _ in }
    }

    func openInTsukumo(_ agent: UUID? = nil) {
        perform(.init(operation: .open, agent: agent)) { _ in }
    }

    private func perform(_ request: MacSpacesAgents.Request, then: @escaping (MacSpacesAgents.Response) -> Void) {
        guard !isPreview else { return }
        do { try request.validate() } catch { self.error = error.localizedDescription; return }
        busy = true
        Task {
            defer { busy = false }
            do {
                let response = try await call(request)
                status = response.status
                error = nil
                then(response)
            } catch let failure as MacSpacesBridge.Failure where failure.uncertain && request.operation == .send {
                pendingSend = request
                error = failure.message
            } catch let failure as AgentsUncertain where request.operation == .send {
                pendingSend = request
                error = failure.message
            } catch {
                self.error = error.localizedDescription
            }
        }
    }

    // MARK: Transport

    private struct AgentsUnavailable: LocalizedError {
        var errorDescription: String? { "Open an updated Tsukumo to see your bots here." }
    }
    private struct AgentsUncertain: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    private func call(_ request: MacSpacesAgents.Request) async throws -> MacSpacesAgents.Response {
        try request.validate()
        let data = try MacSpacesAgents.encoder.encode(request)
        let reply = try await Task.detached { try LocalBridgeTransport.exchange(data) }.value
        try Task.checkCancellation()
        // An older Tsukumo answers an agents frame with a plain version 1 error: not offered.
        guard MacSpacesAgents.isAgentsFrame(reply) else { throw AgentsUnavailable() }
        let response = try MacSpacesAgents.decoder.decode(MacSpacesAgents.Response.self, from: reply)
        if response.uncertain == true { throw AgentsUncertain(message: response.error ?? "The earlier request has an uncertain outcome. Check it in Tsukumo.") }
        if let message = response.error { throw MacSpacesBridge.Failure(message) }
        return response
    }

    // MARK: QA

    /// Synthetic fixtures for QA and promo captures (FeatureQA bundle only). Never real content.
    func loadPreview() {
        isPreview = true
        availability = .available
        if let list = AgentsFixtures.decode(AgentsFixtures.list) { apply(list) }
        approvals = AgentsFixtures.decode(AgentsFixtures.approvals)?.approvals ?? []
    }

    func setPreview(focused: UUID?, tagged: [UUID], review: Bool, draft: String = "") {
        self.focused = focused
        self.tagged = tagged
        self.review = review ? AgentsFixtures.decode(AgentsFixtures.review)?.review : nil
        self.draft = draft
    }
}
