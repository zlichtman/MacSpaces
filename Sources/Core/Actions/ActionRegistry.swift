import Foundation

struct ActionRequest: Sendable {
    let id: UUID
    let contextID: String?
    let number: Double?
    let action: String
    let selectedText: String?
    let selectedFiles: [URL]
    init(id: UUID = UUID(), action: String, selectedText: String? = nil, selectedFiles: [URL] = [], contextID: String? = nil, number: Double? = nil) {
        self.contextID = contextID; self.number = number
        self.id = id; self.action = action; self.selectedText = selectedText; self.selectedFiles = selectedFiles
    }
}
struct ActionResult: Equatable, Sendable { let message: String }

/// Every entry point uses the same availability check and in-flight identity.
/// Retries must explicitly choose a new request; uncertain external sends are
/// never automatically repeated.
@MainActor final class ActionRegistry {
    struct Entry {
        let feature: FeatureID
        let title: String
        let available: () -> Bool
        let perform: (ActionRequest) async throws -> ActionResult
    }
    enum Failure: Error, Equatable { case unknown, unavailable, alreadySubmitted }
    private var entries: [String: Entry] = [:]
    private var submitted: Set<UUID> = []
    private var tasks: [UUID: Task<ActionResult, Error>] = [:]
    func register(_ id: String, entry: Entry) { precondition(entries[id] == nil); entries[id] = entry }
    func availableActions() -> [(id: String, title: String)] {
        entries.filter { $0.value.available() }.map { ($0.key, $0.value.title) }.sorted { $0.title < $1.title }
    }
    func execute(_ request: ActionRequest) async throws -> ActionResult {
        guard let entry = entries[request.action] else { throw Failure.unknown }
        guard entry.available() else { throw Failure.unavailable }
        guard submitted.insert(request.id).inserted else { throw Failure.alreadySubmitted }
        let task = Task { try Task.checkCancellation(); return try await entry.perform(request) }
        tasks[request.id] = task
        defer { tasks.removeValue(forKey: request.id) }
        return try await withTaskCancellationHandler { try await task.value } onCancel: { task.cancel() }
    }
    func isRunning(_ id: UUID) -> Bool { tasks[id] != nil }
    func cancel(_ id: UUID) { tasks[id]?.cancel() }
    func cancelAll() { tasks.values.forEach { $0.cancel() } }
}
