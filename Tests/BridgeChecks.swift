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
        print("Bridge checks passed: validation, durable receipts, restart uncertainty, replay, payload collisions and account isolation")
    }
}
