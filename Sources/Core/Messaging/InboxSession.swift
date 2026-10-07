import Foundation

/// Reply drafts on the Messages page, one per conversation. A draft belongs to the
/// chat it was typed for: changing the selection (here or on another display)
/// shows that chat's own draft and never moves text to a different recipient.
struct ChatDrafts: Equatable {
    private var texts: [String: String] = [:]

    func text(for chat: String?) -> String { chat.flatMap { texts[$0] } ?? "" }

    mutating func set(_ text: String, for chat: String) {
        texts[chat] = text.isEmpty ? nil : text
    }

    /// After a send: clears the chat's draft only if it still holds what was sent,
    /// so anything typed while sending is kept.
    mutating func clear(_ chat: String, ifStill sent: String) {
        if texts[chat] == sent { texts[chat] = nil }
    }
}

/// Who is showing the inbox, and which reads may still land. Each Messages page
/// (one per display) attaches with its own id; the inbox runs while any is
/// attached and stops only when the last leaves. Every start or stop begins a new
/// generation, so a read that finishes after its page closed, or behind a newer
/// read, is rejected instead of repopulating the inbox.
struct InboxSession {
    struct Ticket: Equatable {
        let generation: Int
        let request: Int
    }

    private(set) var consumers: Set<UUID> = []
    private(set) var generation = 0
    private var issued = 0
    private var applied = 0

    var isActive: Bool { !consumers.isEmpty }

    /// Returns true for the first consumer: the inbox should start.
    mutating func attach(_ id: UUID) -> Bool {
        let first = consumers.isEmpty
        consumers.insert(id)
        if first { generation += 1 }
        return first
    }

    /// Returns true when the last consumer leaves: the inbox should stop and clear.
    mutating func detach(_ id: UUID) -> Bool {
        guard consumers.remove(id) != nil, consumers.isEmpty else { return false }
        generation += 1
        return true
    }

    mutating func beginRead() -> Ticket? {
        guard isActive else { return nil }
        issued += 1
        return Ticket(generation: generation, request: issued)
    }

    /// Whether a read's results may still be shown (its session is current).
    func isCurrent(_ ticket: Ticket) -> Bool { isActive && ticket.generation == generation }

    /// Accepts a finished read only for the current session and only if no newer
    /// read has already been applied.
    mutating func accept(_ ticket: Ticket) -> Bool {
        guard isCurrent(ticket), ticket.request > applied else { return false }
        applied = ticket.request
        return true
    }
}
