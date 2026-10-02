import Foundation

/// Bridge version 3, the agents channel: Tsukumo's bots on MacSpaces' notch tab. Proposed as the
/// fourth shared file (byte-identical in both repos, like `MacSpacesBridgeContract.swift`).
///
/// Negotiation: a version 2 discovery reply lists `agents.v3` in `capabilities.operations` when the
/// server speaks this channel. Only then does a client send `MacSpacesAgents.Request` frames, which
/// carry `"channel": "agents"` and are answered with `MacSpacesAgents.Response`. Version 1 and 2
/// requests and replies are unchanged, and a client that never sends this channel sees nothing new.
///
/// Direction of data: MacSpaces sends only what the person typed or picked (a message, the bots it's
/// for, an approval answer, a review decision). Tsukumo sends back its bots, their states, their
/// conversations, and review excerpts for display on this Mac only: MacSpaces keeps them in memory,
/// never writes them to disk, and never sends them anywhere else. The personal KemoSabe chat of
/// versions 1 and 2 still sends nothing back.
enum MacSpacesAgents {
    static let channel = "agents"
    static let version = 3
    /// In a version 2 discovery reply's `capabilities.operations`.
    static let capability = "agents.v3"
    /// A frame is still at most `MacSpacesBridge.maxBytes` (128 KiB); these keep replies well under it.
    static let maxAgents = 16
    static let maxFeedItems = 25
    static let maxItemCharacters = 1200
    static let maxMessageBytes = 16 * 1024
    static let maxReviewFiles = 50
    static let maxDiffExcerptBytes = 24 * 1024
    static let maxApprovalCharacters = 500
    static let maxNoteCharacters = 300
    /// `changes` may wait for something to change, briefly: Tsukumo answers within the bridge's 5 seconds.
    static let maxWait: Double = 3

    enum Operation: String, Codable, CaseIterable {
        /// The channel's limits and operations, and KemoSabe's avatar.
        case hello
        /// Every bot, with the latest Together items.
        case list
        /// What changed since a cursor: bots, new Together items, removed bots. Polling, optionally waiting up to `maxWait`.
        case changes
        /// The person's typed message to one or more bots. Once per request UUID.
        case send
        /// Pending approvals of the bots' coding tasks.
        case approvals
        /// Allow once, or deny, one pending approval. Once per request UUID. Risky ones only in Tsukumo.
        case approve, deny
        /// A bot's task: its changed files and a bounded excerpt of the reviewed diff.
        case review
        /// Accept exactly the reviewed tree, or send a one-line note asking for changes. Once per request UUID.
        case accept, requestChanges
        /// Follow the bot's edits in the owner's editor, on or off.
        case follow
        /// Bring the bot's task (or Tsukumo) forward in Tsukumo.
        case open
        var sends: Bool { [.send, .approve, .deny, .accept, .requestChanges].contains(self) }
    }

    struct Request: Codable, Equatable {
        var channel = MacSpacesAgents.channel
        var version = MacSpacesAgents.version
        var id = UUID()
        var operation: Operation
        /// The bot an operation is about.
        var agent: UUID?
        /// `send`: the bots it's for (tagged chips); empty with `together` routes as Together does.
        var agents: [UUID]?
        /// `send`: what the person typed. `requestChanges`: their one-line note.
        var text: String?
        /// `send`: from the Together thread (shown there).
        var together: Bool?
        /// `changes`: the last reply's `epoch` and `cursor`; `wait`: seconds to wait for a change.
        var epoch: UUID?
        var cursor: Int?
        var wait: Double?
        /// `approve` and `deny`: the approval's ID from `approvals`.
        var approval: String?
        /// `accept`: the tree from the `review` reply that the person looked at.
        var tree: String?
        /// `follow`.
        var on: Bool?

        func validate() throws {
            guard channel == MacSpacesAgents.channel else { throw MacSpacesBridge.Failure("Not an agents request.") }
            guard version == MacSpacesAgents.version else { throw MacSpacesBridge.Failure("Update both apps to use the same agents version.") }
            switch operation {
            case .hello, .list, .approvals: break
            case .changes:
                if let wait, !(0...MacSpacesAgents.maxWait).contains(wait) { throw MacSpacesBridge.Failure("Wait up to 3 seconds.") }
                if let cursor, cursor < 0 { throw MacSpacesBridge.Failure("That cursor isn't valid.") }
            case .send:
                let tagged = agents ?? []
                guard tagged.count <= MacSpacesAgents.maxAgents, Set(tagged).count == tagged.count else { throw MacSpacesBridge.Failure("Tag each bot once.") }
                guard !tagged.isEmpty || together == true else { throw MacSpacesBridge.Failure("Choose a bot first.") }
                guard let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.utf8.count <= MacSpacesAgents.maxMessageBytes else {
                    throw MacSpacesBridge.Failure("Enter a message of up to 16 KiB.")
                }
            case .approve, .deny:
                guard agent != nil, let approval, !approval.isEmpty, approval.utf8.count <= 200 else { throw MacSpacesBridge.Failure("Choose an approval first.") }
            case .accept:
                guard agent != nil, let tree, !tree.isEmpty, tree.utf8.count <= 100 else { throw MacSpacesBridge.Failure("Review the changes before accepting.") }
            case .requestChanges:
                guard agent != nil, let text, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= MacSpacesAgents.maxNoteCharacters else {
                    throw MacSpacesBridge.Failure("Write a note of up to 300 characters.")
                }
            case .follow:
                guard agent != nil, on != nil else { throw MacSpacesBridge.Failure("Choose a bot and whether to follow it.") }
            case .review, .open:
                guard agent != nil || operation == .open else { throw MacSpacesBridge.Failure("Choose a bot first.") }
            }
        }
    }

    /// How to draw a bot: the same parts Tsukumo draws (design/MACSPACES-AGENTS-TAB.md#characters).
    struct Character: Codable, Equatable {
        /// "bean", "gumdrop", "block", "mochi", "sprout", "pebble"; "kemosabe" for KemoSabe (use `hello`'s avatar).
        var shape: String
        /// Palette colors as "RRGGBB": body, accent (cheeks, dots, keyboard key), ink (eyes, mouth).
        var body: String
        var accent: String
        var ink: String
        /// "dots", "ovals", "sparkle", "visor".
        var eyes: String
        /// "none", "pencil", "hardHat", "glasses", "wrench", "headset", "paintbrush", "book", "antenna".
        var prop: String
    }
    /// A coding bot's task at a glance.
    struct Work: Codable, Equatable {
        /// Tsukumo's task status: "Preparing", "Working", "Needs you", "Review", "Interrupted", "Failed", "Done", "Ready".
        var status: String
        /// One line: "2 of 4: Update ETAEstimator", "Running tests", "Ready for review", "Needs your OK: …".
        var headline: String
        var step: Int?
        var steps: Int?
        /// Steps done of all, 0…1.
        var progress: Double?
        /// "ETAEstimator.swift:42".
        var file: String?
        /// "running", "passed", "failed".
        var tests: String?
        var ready: Bool
        var project: String?
        /// "readOnly", "edit" (Ask first), "autoEdit".
        var access: String
        var follow: Bool
    }
    struct Agent: Codable, Equatable, Identifiable {
        var id: UUID
        var name: String
        var job: String
        /// "kemosabe", or the engine's chat ID: "claude-code", "codex", "muse", "cursor-agent", "acp:<id>".
        var engine: String
        /// "KemoSabe", "Claude Code", "Codex", …
        var engineName: String
        var character: Character
        /// What the character acts out: "idle", "working", "thinking", "talking", "chirping", "needsYou", "done", "sleeping".
        var state: String
        /// The reply streaming in, shortened.
        var partial: String?
        var work: Work?
        /// Whether a message can go to it now (false while it's answering).
        var canSend: Bool
    }
    struct FeedItem: Codable, Equatable, Identifiable {
        var id: UUID
        var date: Date
        /// "owner", "reply", "chirp", "problem".
        var kind: String
        /// Who spoke (every kind but "owner").
        var agent: UUID?
        /// Who an owner's message went to.
        var to: [UUID]?
        var text: String
        var truncated: Bool?
        var together: Bool
    }
    struct Approval: Codable, Equatable, Identifiable {
        var id: String
        var agent: UUID
        /// "command", "files", "question".
        var kind: String
        /// The command, or what it wants to edit.
        var text: String
        var risky: Bool
        var reason: String?
        /// False for risky ones: "Open in Tsukumo" instead of approving here.
        var canAnswerHere: Bool
    }
    struct ReviewFile: Codable, Equatable {
        var path: String
        /// "added", "deleted", "modified", "renamed".
        var change: String
        var additions: Int
        var deletions: Int
    }
    struct Review: Codable, Equatable {
        var agent: UUID
        /// The reviewed snapshot; `accept` must name it.
        var tree: String
        var files: [ReviewFile]
        var additions: Int
        var deletions: Int
        /// The start of the unified diff, cut at a line.
        var excerpt: String
        var truncated: Bool
        var canAccept: Bool
    }
    struct Limits: Codable, Equatable {
        var maxAgents = MacSpacesAgents.maxAgents
        var maxFeedItems = MacSpacesAgents.maxFeedItems
        var maxItemCharacters = MacSpacesAgents.maxItemCharacters
        var maxMessageBytes = MacSpacesAgents.maxMessageBytes
        var maxNoteCharacters = MacSpacesAgents.maxNoteCharacters
        var maxWait = MacSpacesAgents.maxWait
    }
    struct Response: Codable, Equatable {
        var channel = MacSpacesAgents.channel
        var version = MacSpacesAgents.version
        /// The request this answers.
        var request: UUID?
        /// Changes to Tsukumo's feed: send back with `changes`. A new epoch (Tsukumo restarted, or the
        /// account changed) comes with `reset: true` and everything, so drop what you had.
        var epoch: UUID?
        var cursor: Int?
        var reset: Bool?
        var agents: [Agent]?
        var removed: [UUID]?
        var feed: [FeedItem]?
        var approvals: [Approval]?
        var review: Review?
        var status: String?
        var error: String?
        /// A sending request whose outcome isn't known: keep the same request UUID until the person checks.
        var uncertain: Bool?
        /// `hello`: operations, limits, and KemoSabe's avatar (a small PNG).
        var operations: [String]?
        var limits: Limits?
        var kemoSabeAvatar: Data?
    }

    /// Whether a frame is on this channel, without decoding the rest.
    static func isAgentsFrame(_ data: Data) -> Bool {
        struct Probe: Decodable { var channel: String? }
        return (try? JSONDecoder().decode(Probe.self, from: data))?.channel == channel
    }
    static var encoder: JSONEncoder { let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601; return encoder }
    static var decoder: JSONDecoder { let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601; return decoder }
}
