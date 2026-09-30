import Foundation
import Combine

@MainActor final class CodingUsageService: ObservableObject {
    @Published private(set) var snapshot = CodingUsageSnapshot()
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    @Published private(set) var updatedAt: Date?
    private var loop: Task<Void, Never>?
    func start() {
        guard loop == nil else { return }
        loop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                do { try await Task.sleep(for: .seconds(60)) } catch { return }
            }
        }
    }
    func stop() { loop?.cancel(); loop = nil; isLoading = false }
    private func refresh() async {
        isLoading = true
        let worker = Task.detached(priority: .utility) { try CodingUsageReader.read() }
        do {
            let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
            guard !Task.isCancelled else { return }
            snapshot = value; updatedAt = Date(); error = nil
        } catch is CancellationError { return }
        catch { self.error = "Local usage logs could not be read. Try reopening Coding." }
        isLoading = false
    }
    #if DEBUG
    func setPreview() {
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.FeatureQA")
        snapshot.rows = [.init(provider: "Codex", model: "Sample model", input: 82000, output: 12000, cached: 18000)]
        updatedAt = Date()
    }
    #endif
}
