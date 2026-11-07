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
        // Bounded, so a request that never registers fails here instead of hanging CI.
        var spins = 0
        while !actions.isRunning(pending.id) { spins += 1; precondition(spins < 100_000, "The request never started"); await Task.yield() }
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
        var restored = FocusSilencing(turnedOn: true)
        precondition(restored.session(active: true, silencing: true, shortcutsReady: true) == nil, "A relaunch doesn't run On again")
        precondition(restored.session(active: false, silencing: true, shortcutsReady: true) == .off, "A relaunch still owes Off")
        var failed = FocusSilencing(turnedOn: true)
        precondition(failed.session(active: false, silencing: true, shortcutsReady: true) == .off)
        failed.offFailed()
        precondition(failed.turnedOn && failed.session(active: false, silencing: true, shortcutsReady: false) == .off, "A failed Off is owed again")
        // A finished timer: a short name for the lane, and When done never starts a stopped song.
        // Theme names split for the list, and how they sort.
        let hardDark = ThemeDisplayName("Everforest Dark Hard")
        precondition(hardDark.family == "Everforest" && hardDark.level == 3)
        precondition(ThemeDisplayName("Everforest Light (Medium)") == ThemeDisplayName("Everforest Light Med"))
        precondition(ThemeDisplayName("Everforest Light Soft Lost").level == 1 && ThemeDisplayName("Everforest Light Soft Lost").family == "Everforest")
        precondition(ThemeDisplayName("Dark Modern").family == "Dark Modern", "A first word is part of the name")
        precondition(ThemeDisplayName("Hard Reset").level == nil && ThemeDisplayName("TokyoNight Storm").family == "TokyoNight Storm")
        precondition(ThemeDisplayName("Gruvbox dark, hard").family == "Gruvbox" && ThemeDisplayName("Gruvbox dark, hard").level == 3)
        precondition(ThemeDisplayName("everslate").family == "Everslate" && ThemeDisplayName("boo-shnickle-light").family == "Boo Shnickle")
        precondition(ThemeDisplayName("iTerm2 Solarized Dark").family == "iTerm2 Solarized" && ThemeDisplayName("12-bit Rainbow").family == "12-bit Rainbow")
        precondition(ThemeDisplayName("datum (dark)").family == "Datum" && ThemeDisplayName("Gruvbox dark, pale").family == "Gruvbox Pale")
        precondition(ThemeClassics.contains("Dracula") && ThemeClassics.contains("Catppuccin Latte") && ThemeClassics.contains("iTerm2 Default"))
        precondition(!ThemeClassics.contains("Everforest Dark Hard") && !ThemeClassics.contains("Catppuccin Frappe") && !ThemeClassics.contains("Nordfox"), "One pick of each, not every version")
        precondition(ThemeDisplayName("Vs Code Dark+").family == "VS Code Dark+")
        precondition(ThemeDisplayName("iTerm2 Dark Background").family == "iTerm2" && ThemeDisplayName("iTerm2 Pastel Dark Background").family == "iTerm2 Pastel")
        let sorted = [("Everforest Light Soft", false, 2), ("Everforest Dark Hard", true, 2), ("Everforest Dark Soft", true, 2),
                      ("Everforest", true, 1), ("Ayu", true, 2), ("Everforest Light Hard Lost", false, 3)]
            .map { ThemeSortKey(name: $0.0, isDark: $0.1, pack: $0.2) }.sorted().map(\.name)
        precondition(sorted == ["ayu", "everforest", "everforest dark soft", "everforest dark hard", "everforest light soft", "everforest light hard lost"],
                     "Family, dark first, pack, level")
        let hidden = ThemeDuplicates.hidden(names: ["Merino Dark", "GitHub Dark Default", "Solo", "A Copy", "A"], colours: ["1", "1", "2", "3", "3"])
        precondition(hidden == ["Merino Dark": "GitHub Dark Default", "A Copy": "A"], "The known name, else the shortest")
        precondition(TimerDone.laneLabel("  Tea ") == "Tea" && TimerDone.laneLabel(" ") == "Timer")
        precondition(TimerDone.laneLabel("A very long timer name").count == TimerDone.laneLabelLimit)
        precondition(TimerDone.shouldPauseMusic(.pauseMusic, isPlaying: true))
        precondition(!TimerDone.shouldPauseMusic(.pauseMusic, isPlaying: false) && !TimerDone.shouldPauseMusic(.nothing, isPlaying: true))
        precondition(TimerWhenDone(rawValue: "") == nil && TimerWhenDone.allCases.first == .nothing, "An unset timer does nothing")
        precondition(!TimerDone.shouldPauseMusic(.startBreak, isPlaying: true), "A break leaves the music alone")
        precondition(GridMove.target(from: nil, count: 5, columns: 3, .down) == 0, "With nothing chosen, the first")
        precondition(GridMove.target(from: 0, count: 0, columns: 3, .right) == nil)
        precondition(GridMove.target(from: 2, count: 7, columns: 3, .right) == 3, "Right runs on to the next row")
        precondition(GridMove.target(from: 3, count: 7, columns: 3, .left) == 2 && GridMove.target(from: 0, count: 7, columns: 3, .left) == nil)
        precondition(GridMove.target(from: 1, count: 7, columns: 3, .down) == 4 && GridMove.target(from: 4, count: 7, columns: 3, .up) == 1)
        precondition(GridMove.target(from: 5, count: 7, columns: 3, .down) == 6, "A short last row is still reachable")
        precondition(GridMove.target(from: 6, count: 7, columns: 3, .down) == nil && GridMove.target(from: 1, count: 7, columns: 3, .up) == nil)
        precondition(TimerRow.split(running: 3, done: 0) == (3, 0) && TimerRow.split(running: 4, done: 0) == (4, 0))
        precondition(TimerRow.split(running: 7, done: 0) == (4, 3), "Past four, the rest are counted")
        precondition(TimerRow.split(running: 3, done: 2) == (2, 1) && TimerRow.split(running: 1, done: 6) == (0, 1), "Finished ones go first")
        precondition(TimerDone.pulseProgress(elapsed: -1) == nil && TimerDone.pulseProgress(elapsed: 0) == 0)
        precondition(abs((TimerDone.pulseProgress(elapsed: 1.65) ?? 0) - 0.5) < 0.001, "Halfway through the second pulse")
        precondition(TimerDone.pulseProgress(elapsed: TimerDone.pulseDuration) == nil, "Three pulses, then still")
        print("Core checks passed: catalog, lazy lifecycle, ordering, rollback, cycles, actions, cancellation, Focus cleanup, timer done state")
    }
}
