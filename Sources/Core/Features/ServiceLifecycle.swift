import Foundation

@MainActor protocol ManagedFeatureService: AnyObject {
    func start() throws
    func stop()
}

/// Lifecycle is independent of windows. Repeated demand is idempotent, and
/// stopping never invokes a factory. Dependencies outlive their consumers.
@MainActor final class ServiceLifecycle {
    struct Registration {
        let dependencies: Set<String>
        let create: () throws -> any ManagedFeatureService
        init(dependencies: Set<String> = [], create: @escaping () throws -> any ManagedFeatureService) {
            self.dependencies = dependencies; self.create = create
        }
    }
    enum Failure: Error, Equatable { case unknown(String), cycle(String) }
    private let registrations: [String: Registration]
    private var active: [String: any ManagedFeatureService] = [:]
    private var startOrder: [String] = []
    var activeIDs: Set<String> { Set(active.keys) }
    init(_ registrations: [String: Registration]) { self.registrations = registrations }

    func reconcile(_ demand: Set<String>) throws {
        var order: [String] = [], visited: Set<String> = [], visiting: Set<String> = []
        func visit(_ id: String) throws {
            guard !visited.contains(id) else { return }
            guard let registration = registrations[id] else { throw Failure.unknown(id) }
            guard visiting.insert(id).inserted else { throw Failure.cycle(id) }
            for dependency in registration.dependencies.sorted() { try visit(dependency) }
            visiting.remove(id); visited.insert(id); order.append(id)
        }
        for id in demand.sorted() { try visit(id) }
        // Resolve/validate first: invalid demand cannot partially stop working services.
        var started: [String] = []
        do {
            for id in order where active[id] == nil {
                let service = try registrations[id]!.create()
                do { try service.start() } catch { service.stop(); throw error }
                active[id] = service; started.append(id)
            }
        } catch {
            for id in started.reversed() { active.removeValue(forKey: id)?.stop() }
            throw error
        }
        for id in startOrder.reversed() where !visited.contains(id) {
            active.removeValue(forKey: id)?.stop()
        }
        startOrder = order
    }
    func stopAll() {
        for id in startOrder.reversed() { active.removeValue(forKey: id)?.stop() }
        startOrder.removeAll()
    }
}

@MainActor final class ServiceCallbacks: ManagedFeatureService {
    private let onStart: () throws -> Void
    private let onStop: () -> Void
    init(start: @escaping () throws -> Void, stop: @escaping () -> Void) {
        onStart = start; onStop = stop
    }
    func start() throws { try onStart() }
    func stop() { onStop() }
}
