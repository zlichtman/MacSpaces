#if DEBUG
import AppKit
import EventKit
import JavaScriptCore

@MainActor enum ReviewRegressionChecks {
    static func run() async throws {
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.FeatureQA")
        let suite = "dev.opensource.MacSpaces.Review." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(Date().addingTimeInterval(-30), forKey: "timer.endDate")
        defaults.set(60, forKey: "timer.total")
        let expired = TimerService(defaults: defaults)
        precondition(!expired.isRunning && expired.missedDeadline != nil, "Expired timers are shown as finished, not restarted")
        defaults.set(100, forKey: "timer.pausedRemaining")
        let paused = TimerService(defaults: defaults)
        precondition(paused.isPaused && paused.remaining == 100, "Paused timer restoration")
        paused.name = "Fixture timer"
        precondition(defaults.string(forKey: "timer.name") == "Fixture timer")

        let reminder = EKReminder(eventStore: EKEventStore()) // Nothing is fetched from EventKit.
        reminder.title = "Fixture reminder"
        let calendar = CalendarService()
        let row = TodoItem(id: "fixture", title: "Fixture reminder", dueDate: nil)
        calendar.setReminderFixtureRows([row])
        calendar.reminderFixture = (resolve: { _ in reminder }, create: { _ in reminder }, save: { _ in throw NSError(domain: "Fixture", code: 1) })
        precondition(!calendar.complete(row) && !reminder.isCompleted && calendar.reminders == [row] && calendar.reminderError != nil, "Failed completion keeps the row and rolls back its object")
        precondition(!calendar.addReminder(title: "Draft") && calendar.reminderError != nil, "Failed add never reports success")
        calendar.reminderFixture = (resolve: { _ in reminder }, create: { _ in reminder }, save: { _ in })
        precondition(calendar.complete(row) && calendar.reminders.isEmpty && reminder.isCompleted, "Only successful save removes row")

        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MacSpaces-review-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let a = root.appendingPathComponent("A.txt"), b = root.appendingPathComponent("B.txt"), c = root.appendingPathComponent("C.txt")
        for url in [a, b, c] { try Data("Fixture".utf8).write(to: url) }
        let basketID = UUID(), shelf = ShelfStore(basketID: basketID)
        defer { shelf.forgetSavedList() }
        shelf.add(url: a); shelf.add(url: b)
        shelf.selectAll(); precondition(shelf.selectedItems.count == 2)
        shelf.removeSelected(); shelf.add(url: c); shelf.undoRemoval()
        precondition(Set(shelf.items.map(\.url)) == Set([a, b, c]), "Undo preserves files added after removal")
        try FileManager.default.removeItem(at: b); shelf.pruneMissingItems()
        precondition(shelf.items.count == 3 && shelf.unavailableIDs.count == 1, "Missing file references are retained")
        let reloaded = ShelfStore(basketID: basketID)
        precondition(reloaded.items.count == 3 && reloaded.unavailableIDs.count == 1, "Offline references survive reload")

        shelf.select(shelf.items.first { $0.url == a })
        shelf.quickLook()
        precondition(NSApp.windows.contains { $0.isVisible && String(describing: type(of: $0)).contains("ShelfPreviewWindow") }, "Quick Look opens a native preview for selected fixtures")
        shelf.quickLook()

        let damagedID = UUID()
        let shelfDirectory = FileManager.default.temporaryDirectory.appendingPathComponent("MacSpacesFixtures/dev.opensource.MacSpaces.FeatureQA/MacSpaces")
        let damagedPath = shelfDirectory.appendingPathComponent("basket-" + damagedID.uuidString + ".json")
        let damagedData = Data("{broken fixture".utf8)
        try damagedData.write(to: damagedPath)
        let damaged = ShelfStore(basketID: damagedID)
        precondition(damaged.needsRecovery, "Malformed shelf requires explicit recovery")
        damaged.add(url: a)
        let beforeRecovery = try Data(contentsOf: damagedPath)
        precondition(beforeRecovery == damagedData, "A failed decode is never overwritten automatically")
        damaged.recoverPersistence()
        let backups = try FileManager.default.contentsOfDirectory(at: shelfDirectory, includingPropertiesForKeys: nil).filter { $0.lastPathComponent.hasPrefix(damagedPath.lastPathComponent + ".recovery-") }
        precondition(!damaged.needsRecovery && backups.count == 1)
        let recoveredOriginal = try Data(contentsOf: backups[0])
        precondition(recoveredOriginal == damagedData, "Recovery preserves original damaged bytes")
        damaged.forgetSavedList(); for backup in backups { try FileManager.default.removeItem(at: backup) }

        let model = NotchViewModel(geometry: .synthetic, availableWidth: 1440, settings: NookSettings(defaults: defaults), shelf: shelf,
                                  nowPlaying: AppServices.shared.nowPlaying, powerMonitor: AppServices.shared.powerMonitor, timerService: expired,
                                  bluetoothMonitor: AppServices.shared.bluetooth, systemActivityMonitor: AppServices.shared.systemActivity,
                                  teleprompter: AppServices.shared.teleprompter)
        model.state = .expanded; model.isPageEditing = true
        precondition(model.isInUse, "Editing protects notification destination even when pointer is outside")
        model.isPageEditing = false; model.isPinned = true
        precondition(model.isInUse, "Keyboard pin protects notification destination")
        let manager = NotchManager(); var prepared = false
        precondition(!manager.present(.messages, for: 4, prepare: { prepared = true }) && !prepared, "No destination is mutated when presentation cannot happen")

        for (name, source) in [("Music playlist", MusicPlaylist.script), ("Meet Safari", MeetingControls.browserScript(safari: true)), ("Meet Chrome", MeetingControls.browserScript(safari: false))] {
            if name == "Meet Chrome", NSWorkspace.shared.urlForApplication(withBundleIdentifier: "com.google.Chrome") == nil {
                print("Chrome integration requires Chrome; script compilation skipped on this Mac")
                continue
            }
            var error: NSDictionary?
            let script = NSAppleScript(source: source)!
            precondition(script.compileAndReturnError(&error), "\(name) must compile: \(String(describing: error))")
        }
        let context = JSContext()!
        context.evaluateScript("""
        var location={protocol:'https:',hostname:'meet.google.com'}, clicks=0;
        function button(label) { return {disabled:false,label, getClientRects(){return [1]}, getAttribute(){return this.label}, click(){clicks++; this.label=this.label.replace('Turn off','TMP').replace('Turn on','Turn off').replace('TMP','Turn on')}} }
        var mic=button('Turn off microphone (Ctrl+D)'), camera=button('Turn on camera (Ctrl+E)'), rows=[mic,camera];
        var document={querySelectorAll(){return rows}};
        """)
        let read = context.evaluateScript(MeetingControls.meetScript(action: "read"))!.toString()!
        precondition(read.contains("\"muted\":false") && read.contains("\"cameraOff\":true"), "Meet reads actual labelled state")
        context.evaluateScript(MeetingControls.meetScript(action: "mute"))
        context.evaluateScript(MeetingControls.meetScript(action: "mute"))
        precondition(context.evaluateScript("clicks")!.toInt32() == 1, "Mute is idempotent")
        context.evaluateScript("rows=[mic,button('Turn off microphone (Ctrl+D)')]")
        context.evaluateScript(MeetingControls.meetScript(action: "unmute"))
        precondition(context.evaluateScript("clicks")!.toInt32() == 1, "Ambiguous controls cannot be pressed")
        context.evaluateScript("location.hostname='example.com';rows=[mic,camera]")
        context.evaluateScript(MeetingControls.meetScript(action: "unmute"))
        precondition(context.evaluateScript("clicks")!.toInt32() == 1, "Wrong origin cannot be controlled")
        let start = Date()
        let long = await ShortcutsService.checkProcess(arguments: ["-c", "exec /bin/sleep 22"])
        precondition(long.0 == 0 && Date().timeIntervalSince(start) >= 21, "Explicit runs are not killed after 20 seconds")
        let cancelStart = Date()
        let cancelled = await ShortcutsService.checkProcess(arguments: ["-c", "exec /bin/sleep 30"], cancelAfter: 0.2)
        precondition(cancelled.0 != 0 && Date().timeIntervalSince(cancelStart) < 5, "Explicit cancellation stops the child")
        print("Review regressions passed: reminders, timers, Tray, presentation gate, provider scripts and long/cancelled runs")
    }
}
#endif
