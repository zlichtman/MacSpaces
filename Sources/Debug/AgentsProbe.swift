import AppKit
import Foundation

/// MACSPACES_AGENTS_PROBE=1: checks the agents channel against the installed Tsukumo from the
/// real, signed app (Tsukumo verifies the caller's signature, so a script can't do this), then
/// quits. Prints counts and states only, never names, messages or code.
enum AgentsProbe {
    @MainActor
    static func runIfRequested() -> Bool {
        guard ProcessInfo.processInfo.environment["MACSPACES_AGENTS_PROBE"] == "1" else { return false }
        Task.detached {
            func exchange(_ data: Data) throws -> Data { try LocalBridgeTransport.exchange(data) }
            do {
                let discover = try JSONDecoder().decode(MacSpacesBridge.Response.self,
                    from: try exchange(JSONEncoder().encode(MacSpacesBridge.Request(version: 1, operation: .discover))))
                let offered = discover.capabilities?.operations.contains(MacSpacesAgents.capability) == true
                print("discover: version \(discover.version), agents.v3 offered: \(offered)\(discover.error.map { ", error: \($0)" } ?? "")")
                guard offered else { exit(offered ? 0 : 2) }
                for operation in [MacSpacesAgents.Operation.hello, .list, .approvals] {
                    let request = MacSpacesAgents.Request(operation: operation)
                    let reply = try exchange(MacSpacesAgents.encoder.encode(request))
                    let response = try MacSpacesAgents.decoder.decode(MacSpacesAgents.Response.self, from: reply)
                    let states = (response.agents ?? []).map(\.state).sorted().joined(separator: ",")
                    print("\(operation.rawValue): request echoed \(response.request == request.id), bots \(response.agents?.count ?? 0) [\(states)], feed \(response.feed?.count ?? 0), approvals \(response.approvals?.count ?? 0), avatar bytes \(response.kemoSabeAvatar?.count ?? 0), operations \(response.operations?.count ?? 0)\(response.error.map { ", error: \($0)" } ?? "")")
                }
                let changes = MacSpacesAgents.Request(operation: .changes, wait: 0)
                let reply = try MacSpacesAgents.decoder.decode(MacSpacesAgents.Response.self, from: try exchange(MacSpacesAgents.encoder.encode(changes)))
                print("changes: cursor \(reply.cursor.map(String.init) ?? "none"), reset \(reply.reset ?? false)\(reply.error.map { ", error: \($0)" } ?? "")")
                exit(0)
            } catch {
                print("probe failed: \(error.localizedDescription)")
                exit(1)
            }
        }
        return true
    }
}
