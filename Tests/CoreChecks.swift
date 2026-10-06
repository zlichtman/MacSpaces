import Foundation

@main struct CoreChecks {
    enum ProbeError: Error { case failed }
    @MainActor static func main() async throws {
        precondition(Set(FeatureCatalog.all.map(\.id)) == Set(FeatureID.allCases))
        precondition(FeatureCatalog.all.count == FeatureID.allCases.count)
        var events: [String] = []
        func registration(_ id: String, dependencies: Set<String> = [], fails: Bool = false) -> ServiceLifecycle.Registration {
            .init(dependencies: dependencies) {
                events.append("create:\(id)")
                return ServiceCallbacks(start: {
                    events.append("start:\(id)")
                    if fails { throw ProbeError.failed }
                }, stop: { events.append("stop:\(id)") })
            }
        }
        let lifecycle = ServiceLifecycle([
            "music": registration("music"),
            "lyrics": registration("lyrics", dependencies: ["music"]),
            "broken": registration("broken", dependencies: ["music"], fails: true)
        ])
        try lifecycle.reconcile([])
        precondition(events.isEmpty, "Empty demand must not instantiate services")
        try lifecycle.reconcile(["lyrics"])
        precondition(events == ["create:music", "start:music", "create:lyrics", "start:lyrics"])
        events.removeAll()
        try lifecycle.reconcile(["lyrics"])
        precondition(events.isEmpty, "Repeated demand must be idempotent")
        do { try lifecycle.reconcile(["missing"]); preconditionFailure() }
        catch ServiceLifecycle.Failure.unknown("missing") {}
        precondition(events.isEmpty && lifecycle.activeIDs == ["music", "lyrics"])
        do { try lifecycle.reconcile(["broken"]); preconditionFailure() }
        catch ProbeError.failed {}
        precondition(lifecycle.activeIDs == ["music", "lyrics"], "Failed starts must preserve prior demand")
        precondition(events == ["create:broken", "start:broken", "stop:broken"])
        events.removeAll()
        lifecycle.stopAll()
        precondition(events == ["stop:lyrics", "stop:music"])
        events.removeAll()
        do { try lifecycle.reconcile(["broken"]); preconditionFailure() }
        catch ProbeError.failed {}
        precondition(lifecycle.activeIDs.isEmpty)
        precondition(events == ["create:music", "start:music", "create:broken", "start:broken", "stop:broken", "stop:music"])
        events.removeAll()
        let cycle = ServiceLifecycle(["a": registration("a", dependencies: ["b"]), "b": registration("b", dependencies: ["a"])])
        do { try cycle.reconcile(["a"]); preconditionFailure() }
        catch ServiceLifecycle.Failure.cycle {}
        precondition(events.isEmpty)

        let actions = ActionRegistry()
        var calls = 0
        var enabled = false
        actions.register("play", entry: .init(feature: .media, title: "Play", available: { enabled }, perform: { _ in
            calls += 1
            return ActionResult(message: "played")
        }))
        let request = ActionRequest(action: "play")
        do { _ = try await actions.execute(request); preconditionFailure() }
        catch ActionRegistry.Failure.unavailable {}
        precondition(calls == 0)
        enabled = true
        let result = try await actions.execute(request)
        precondition(result.message == "played" && calls == 1)
        do { _ = try await actions.execute(request); preconditionFailure() }
        catch ActionRegistry.Failure.alreadySubmitted {}
        precondition(calls == 1)
        actions.register("wait", entry: .init(feature: .timer, title: "Wait", available: { true }, perform: { _ in
            try await Task.sleep(nanoseconds: 60_000_000_000)
            return ActionResult(message: "unexpected")
        }))
        let pending = ActionRequest(action: "wait")
        let task = Task { try await actions.execute(pending) }
        // Wait until the async request has entered the registry before cancelling.
        while !actions.isRunning(pending.id) { await Task.yield() }
        actions.cancel(pending.id)
        do { _ = try await task.value; preconditionFailure() }
        catch is CancellationError {}
        precondition(!actions.isRunning(pending.id))
        // Focus Off follows what MacSpaces turned on, not the current preference (audit 2.75 #6).
        var focus = FocusSilencing()
        precondition(focus.session(active: true, silencing: true, shortcutsReady: true) == .on)
        precondition(focus.silencingDisabled() == .off, "Turning silencing off mid-session turns Focus off")
        precondition(focus.session(active: false, silencing: false, shortcutsReady: false) == nil, "Off runs once")
        _ = focus.session(active: true, silencing: true, shortcutsReady: true)
        precondition(focus.session(active: false, silencing: false, shortcutsReady: false) == .off, "Pause cleans up even with silencing now off")
        precondition(focus.session(active: true, silencing: false, shortcutsReady: true) == nil
                     && focus.session(active: false, silencing: false, shortcutsReady: true) == nil, "Nothing to undo when MacSpaces never turned it on")
        precondition(focus.session(active: true, silencing: true, shortcutsReady: false) == nil && !focus.turnedOn)
        print("Core checks passed: catalog, lazy lifecycle, ordering, rollback, cycles, actions, cancellation, Focus cleanup")
    }
}
