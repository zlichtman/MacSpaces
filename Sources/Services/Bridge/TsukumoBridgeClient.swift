import Foundation
import AppKit

@MainActor final class TsukumoBridgeClient: ObservableObject {
    @Published private(set) var conversations: [MacSpacesBridge.Conversation] = []
    @Published private(set) var message = "Connect to Tsukumo to choose a conversation."
    @Published private(set) var busy = false
    @Published private(set) var sending = false
    private var generation = 0
    func disconnect() { generation += 1 }
    func discover() async { await run(.init(operation: .discover)) }
    func submit(_ prompt: String, to conversation: UUID) async -> Bool {
        guard !busy else { return false }
        sending = true; defer { sending = false }
        return await run(.init(operation: .submit, conversation: conversation, prompt: prompt))
    }
    func status(_ conversation: UUID) async { await run(.init(operation: .status, conversation: conversation)) }
    func cancel(_ conversation: UUID) async { await run(.init(operation: .cancel, conversation: conversation)) }
    func open(_ conversation: UUID) async { await run(.init(operation: .open, conversation: conversation)) }

    @discardableResult private func run(_ request: MacSpacesBridge.Request) async -> Bool {
        guard !busy else { return false }
        busy = true; defer { busy = false }
        do {
            let response = try await exchange(request)
            if let error = response.error { throw MacSpacesBridge.Failure(error) }
            if request.operation == .discover { conversations = response.conversations }
            else { for item in response.conversations {
                if let index = conversations.firstIndex(where: { $0.id == item.id }) { conversations[index] = item }
            } }
            message = response.status ?? "Connected to Tsukumo."
            return true
        } catch { message = error.localizedDescription; return false }
    }
    private func exchange(_ request: MacSpacesBridge.Request) async throws -> MacSpacesBridge.Response {
        try request.validate()
        let data = try JSONEncoder().encode(request), generation = self.generation
        let reply = try await Task.detached { try LocalBridgeTransport.exchange(data) }.value
        guard self.generation == generation else { throw CancellationError() }
        let response = try JSONDecoder().decode(MacSpacesBridge.Response.self, from: reply)
        guard response.version == MacSpacesBridge.version else { throw MacSpacesBridge.Failure("Update both apps to the same bridge version.") }
        return response
    }
}
