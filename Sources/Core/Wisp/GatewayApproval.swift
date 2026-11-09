import Foundation

/// Ask me before sharing (Settings › Tsukumo › Gateway): an answer that passed the levels and the
/// rules waits in the chat as a card showing exactly what would go, until the owner shares it,
/// declines it, or leaves it, which declines it after `timeout`. Ported from Tsukumo's share card.
struct GatewayApproval: Equatable, Identifiable {
    /// How long a card waits before it declines on its own.
    static let timeout: TimeInterval = 120
    /// What the model is told for an answer the owner didn't share, whether declined or left.
    static let declinedAnswer = "The user declined to share that."

    enum Decision: Equatable { case share, decline, timedOut }

    let id: UUID
    /// The service that asked, such as "Claude".
    let service: String
    /// The question as the model asked it.
    let question: String
    /// Exactly what would be sent.
    let draft: String
    let asked: Date
    /// The on-device agent asked (Wisp or KemoSabe), and the question in the chat's words.
    let agent: String
    let phrase: String

    init(id: UUID = UUID(), service: String, question: String, draft: String, asked: Date = Date(),
         agent: String = "KemoSabe", phrase: String? = nil) {
        self.id = id
        self.service = service
        self.question = question
        self.draft = draft
        self.asked = asked
        self.agent = agent
        self.phrase = phrase ?? "“\(question)”"
    }

    var deadline: Date { asked.addingTimeInterval(Self.timeout) }

    /// Whole seconds left, never below zero.
    func secondsLeft(at now: Date) -> Int {
        max(0, Int(deadline.timeIntervalSince(now).rounded(.up)))
    }

    /// "1:05", for the card's countdown.
    static func countdown(_ seconds: Int) -> String {
        let seconds = max(0, seconds)
        return "\(seconds / 60):" + String(format: "%02d", seconds % 60)
    }

    /// The line that goes back to the model: the draft when shared, otherwise only that it was declined.
    func modelLine(_ decision: Decision) -> String {
        "\(question): " + (decision == .share ? draft : Self.declinedAnswer)
    }

    /// What replaces the card in the chat: the usual shared line, or a note that nothing went.
    func chatLine(_ decision: Decision) -> (shared: Bool, text: String) {
        switch decision {
        case .share: return (true, GatewayAsk.chatLine(service: service, agent: agent, phrase: phrase, answer: draft))
        case .decline: return (false, "You didn't share that with \(service).")
        case .timedOut: return (false, "Not shared with \(service): no answer in \(Int(Self.timeout / 60)) minutes.")
        }
    }
}

/// The cards waiting on the owner. Only the first answer to a card counts: a later one, or a
/// timeout after it was answered, changes nothing.
struct GatewayApprovalBook {
    private(set) var waiting: [GatewayApproval] = []

    mutating func add(_ approval: GatewayApproval) {
        guard !waiting.contains(where: { $0.id == approval.id }) else { return }
        waiting.append(approval)
    }

    /// The card this answers, the first time only.
    mutating func resolve(_ id: UUID) -> GatewayApproval? {
        guard let index = waiting.firstIndex(where: { $0.id == id }) else { return nil }
        return waiting.remove(at: index)
    }

    /// Cards whose time ran out by `now`, oldest first.
    func expired(at now: Date) -> [UUID] {
        waiting.filter { $0.deadline <= now }.map(\.id)
    }

    /// The card Return and Escape answer: the oldest still waiting.
    var first: GatewayApproval? { waiting.first }
}
