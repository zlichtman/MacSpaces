import Foundation

@main enum BridgeChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("receipts.json")
        var request = MacSpacesBridge.Request(operation: .submit, conversation: UUID(), prompt: "Only this selected prompt")
        try request.validate()
        let store = try BridgeReceiptStore(url: url)
        let empty = try store.existing(request, owner: "one"); precondition(empty == nil)
        try store.reserve(request, owner: "one")
        let restarted = try BridgeReceiptStore(url: url)
        let uncertain = try restarted.existing(request, owner: "one")
        precondition(uncertain?.error != nil, "A crash after reservation must not submit twice")
        try restarted.complete(request, owner: "one", response: .init(status: "accepted"))
        let replay = try BridgeReceiptStore(url: url).existing(request, owner: "one")
        precondition(replay?.status == "accepted")
        let other = try restarted.existing(request, owner: "two"); precondition(other == nil, "Accounts must be isolated")
        request.prompt = "Changed prompt"
        do { _ = try restarted.existing(request, owner: "one"); preconditionFailure("Payload collision accepted") } catch {}
        request.version = 9
        do { try request.validate(); preconditionFailure("Version accepted") } catch {}
        request.version = 1; request.prompt = " "
        do { try request.validate(); preconditionFailure("Empty prompt accepted") } catch {}
        request.prompt = String(repeating: "a", count: 65_537)
        do { try request.validate(); preconditionFailure("Oversized prompt accepted") } catch {}
        try agentsChecks()
        print("Bridge checks passed: validation, durable receipts, restart uncertainty, replay, payload collisions, account isolation and the agents channel")
    }

    /// The agents channel (version 3): fixtures decode, requests validate, and old decoders never see it.
    static func agentsChecks() throws {
        guard let list = AgentsFixtures.decode(AgentsFixtures.list), let agents = list.agents else { fatalError("Agents fixture must decode") }
        let states = Set(agents.map(\.state))
        precondition(states == ["idle", "working", "thinking", "talking", "chirping", "needsYou", "done", "sleeping"], "A fixture bot in every state")
        precondition(list.feed?.count == 4 && list.reset == true && list.cursor == 42)
        precondition(AgentsFixtures.decode(AgentsFixtures.approvals)?.approvals?.contains { !$0.canAnswerHere && $0.risky } == true)
        precondition(AgentsFixtures.decode(AgentsFixtures.review)?.review?.canAccept == true)
        // Frames are recognisable without decoding, and version 1/2 decoding rejects them.
        let hello = try MacSpacesAgents.encoder.encode(MacSpacesAgents.Request(operation: .hello))
        precondition(MacSpacesAgents.isAgentsFrame(hello))
        let discover = try JSONEncoder().encode(MacSpacesBridge.Request(operation: .discover))
        precondition(!MacSpacesAgents.isAgentsFrame(discover))
        // Validation: explicit targets, bounded text and waits.
        let bot = agents[1].id
        try MacSpacesAgents.Request(operation: .send, agents: [bot], text: "Hi").validate()
        try MacSpacesAgents.Request(operation: .send, text: "Hi", together: true).validate()
        func fails(_ request: MacSpacesAgents.Request) -> Bool { (try? request.validate()) == nil }
        precondition(fails(.init(operation: .send, text: "Hi")), "A send needs a bot or Together")
        precondition(fails(.init(operation: .send, agents: [bot, bot], text: "Hi")), "Tag each bot once")
        precondition(fails(.init(operation: .send, agents: [bot], text: "  ")))
        precondition(fails(.init(operation: .changes, wait: 4)))
        precondition(fails(.init(operation: .approve, agent: bot)), "An approval needs its ID")
        precondition(fails(.init(operation: .requestChanges, agent: bot, text: String(repeating: "x", count: 301))))
        precondition(fails(.init(operation: .accept, agent: bot)), "Accept names the reviewed tree")
    }
}
