import Foundation

struct MessageConversation: Identifiable, Equatable, Codable {
    let id: String
    let title: String
    let participantIDs: [String]
    let participantLabels: [String]
}

/// A failed external send is uncertain, never a reason to retry automatically.
struct MessageReplyState: Codable {
    enum Phase: String, Equatable, Codable { case editing, sending, submitted, uncertain }
    private(set) var phase: Phase = .editing
    private(set) var recipient: MessageConversation?
    var draft = ""
    mutating func select(_ conversation: MessageConversation?) -> Bool {
        guard phase != .sending else { return false }
        guard recipient == nil || recipient == conversation || draft.isEmpty else { return false }
        recipient = conversation; phase = .editing
        return true
    }
    mutating func begin(current: MessageConversation) -> Bool {
        guard phase == .editing, let recipient, recipient == current,
              !recipient.id.isEmpty, !recipient.participantIDs.isEmpty,
              !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, draft.utf8.count <= 16 * 1024 else { return false }
        phase = .sending; return true
    }
    mutating func finish(accepted: Bool) {
        guard phase == .sending else { return }
        phase = accepted ? .submitted : .uncertain
        if accepted { draft = "" }
    }
    mutating func recoverAfterRelaunch() { if phase == .sending { phase = .uncertain } }
    mutating func newDraft() { guard phase != .sending else { return }; draft = ""; phase = .editing }
}
