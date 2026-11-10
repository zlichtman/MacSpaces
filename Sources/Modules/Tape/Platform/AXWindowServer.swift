import AppKit
import ApplicationServices
import QuartzCore

/// Remote AX calls stay off the main thread; frame writes are serial within each app.
/// A deadline replaces pending workers if an app hangs.
/// Registry locks are held only while copying handles, never during remote calls.
final class AXWindowServer: WindowServer {
    var onChange: (() -> Void)?
    var onStall: (() -> Void)?
    var onFocusChange: ((WindowID) -> Void)?
    var onDesktopChange: (() -> Void)?
    var onWindowRemoved: ((WindowID) -> Void)?
    var onWindowInteraction: ((WindowID, CGRect, WindowInteraction, Bool) -> Void)?
    var pointerPosition: CGPoint? {
        let point = NSEvent.mouseLocation
        return CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.maxY ?? 0) - point.y)
    }
    private let lock = NSLock()
    private var queue = DispatchQueue(label: "dev.opensource.MacSpaces.tape.windows", qos: .userInteractive)
    private var scanQueue = DispatchQueue(label: "dev.opensource.MacSpaces.tape.scan", qos: .userInitiated)
    /// Deadlines are armed for every write and job. Main-queue timers would wake the main thread
    /// for each one, hundreds of times a second while scrolling, even after being cancelled.
    private let watchdog = DispatchQueue(label: "dev.opensource.MacSpaces.tape.watchdog", qos: .utility)
    private var focusQueue = DispatchQueue(label: "dev.opensource.MacSpaces.tape.focus", qos: .userInteractive)
    private var focusSequence = 0
    private var focusReads = FocusReadGate()
    private var generation = 0
    private var running = false
    private var discoveryRetries = 0
    private var lastDiscoverySummary: String?
    private var elements: [WindowID: AXUIElement] = [:]
    /// Reverse index (CF types hash with CFHash/CFEqual): notifications arrive for every frame
    /// Tape writes, and a linear search per notification ran on the main thread.
    private var elementIDs: [AXUIElement: WindowID] = [:]
    private var observers: [pid_t: AXObserver] = [:]
    /// App-level notifications an app was too busy to accept; retried on later scans.
    private var pendingAppNotifications: [pid_t: [String]] = [:]
    private var observedWindows: Set<WindowID> = []
    private var lastFrames: [WindowID: CGRect] = [:]
    private var knownSnapshots: [WindowID: WindowSnapshot] = [:]
    private var lastWriteTimes: [WindowID: TimeInterval] = [:]
    /// Restorations an app was too busy to read or accept during the current Pause/Quit.
    private var refusedRestores: Set<WindowID> = []
    private var baseTraits: [WindowID: WindowTraits] = [:]
    private var lastChildren: [WindowID: [AXUIElement]] = [:]
    private var elementPIDs: [WindowID: pid_t] = [:]
    private var frameWriter: FrameWriteQueue?
    private var workspaceTokens: [NSObjectProtocol] = []
    private var activeSpaceToken: NSObjectProtocol?
    private var mouseReleaseMonitor: Any?
    private var interaction: (WindowID, WindowInteraction)?
    private var interactionRead: DispatchWorkItem?
    private var interactionReadScheduled = false
    private var interactionReadInFlight = false
    private var interactionReadAgain = false
    private var interactionFinished = false
    private var interactionEpoch = 0
    private var interactionHasReported = false

    func start() {
        guard !running else { return }
        running = true
        discoveryRetries = 0
        mouseReleaseMonitor = NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { [weak self] _ in
            guard let self, self.interaction != nil else { return }
            self.interactionFinished = true
            self.scheduleInteractionRead(immediately: true)
        }
        let center = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didLaunchApplicationNotification, NSWorkspace.didTerminateApplicationNotification,
                     NSWorkspace.didActivateApplicationNotification, NSWorkspace.didHideApplicationNotification,
                     NSWorkspace.didUnhideApplicationNotification] {
            workspaceTokens.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                if name == NSWorkspace.didActivateApplicationNotification {
                    self?.reportFocus()
                } else { self?.onChange?() }
            })
        }
        activeSpaceToken = center.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.cancelInteraction()
            self?.onDesktopChange?()
        }
    }

    func stop() {
        running = false
        if let mouseReleaseMonitor { NSEvent.removeMonitor(mouseReleaseMonitor) }
        mouseReleaseMonitor = nil
        cancelInteraction()
        workspaceTokens.forEach { NSWorkspace.shared.notificationCenter.removeObserver($0) }
        workspaceTokens.removeAll()
        if let activeSpaceToken { NSWorkspace.shared.notificationCenter.removeObserver(activeSpaceToken) }
        activeSpaceToken = nil
        invalidatePending(replaceFrameWriter: false)
        lock.lock()
        let oldObservers = Array(observers.values)
        observers.removeAll()
        pendingAppNotifications.removeAll()
        observedWindows.removeAll()
        lock.unlock()
        oldObservers.forEach { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource($0), .commonModes) }
    }

    private func invalidatePending(replaceFrameWriter: Bool = true) {
        lock.lock()
        generation += 1
        frameWriter?.cancelPending()
        if replaceFrameWriter { frameWriter = nil }
        lastFrames.removeAll()
        lastWriteTimes.removeAll()
        focusSequence += 1
        queue = DispatchQueue(label: "dev.opensource.MacSpaces.tape.windows.\(generation)", qos: .userInteractive)
        scanQueue = DispatchQueue(label: "dev.opensource.MacSpaces.tape.scan.\(generation)", qos: .userInitiated)
        focusQueue = DispatchQueue(label: "dev.opensource.MacSpaces.tape.focus.\(generation)", qos: .userInteractive)
        lock.unlock()
    }

    private func valid(_ token: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return generation == token
    }

    private enum Work { case frames, scan, focus }
    private func submit(on kind: Work = .frames, _ operation: @escaping (Int) -> Void) {
        lock.lock()
        let worker = kind == .scan ? scanQueue : kind == .focus ? focusQueue : queue
        let token = generation
        lock.unlock()
        let deadline = stallDeadline(token, "Window worker timed out; pending writes cancelled.")
        worker.async { [weak self] in
            guard let self, self.valid(token) else { return }
            // Start the deadline when work begins, so a queue backlog cannot trigger it.
            self.watchdog.asyncAfter(deadline: .now() + 8, execute: deadline)
            operation(token)
            deadline.cancel()
        }
    }

    private func stallDeadline(_ token: Int, _ message: String?) -> DispatchWorkItem {
        DispatchWorkItem { [weak self] in
            DispatchQueue.main.async {
                guard let self, self.valid(token) else { return }
                self.invalidatePending()
                if let message { TapeLog.shared.write(message) }
                self.onStall?()
            }
        }
    }

    func scan(policy: AppPolicy, completion: @escaping ([WindowSnapshot], WindowID?, [SpaceDisplay]?) -> Void) {
        let running = NSWorkspace.shared.runningApplications
        let activePID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let ownPID = getpid()
        submit(on: .scan) { [weak self] token in
            guard let self else { return }
            // Activation policy and bundle ID each cost a LaunchServices round trip per app.
            // NSRunningApplication properties are thread safe, so keep those calls off the main thread.
            let runningApps = running.filter { WindowDiscovery.includesApp(policy: $0.activationPolicy, isOwnApp: $0.processIdentifier == ownPID) }
            let apps = runningApps.filter { policy.manages($0.bundleIdentifier) }
            // Now, not from SpacesMonitor, whose reading waits for a swipe to settle: the first scan
            // on a desktop already has to know whether it's off.
            let spaces = ManagedSpaces.read()
            let visible = Self.visibleWindows()
            var snapshots: [WindowSnapshot] = []
            var seen: Set<WindowID> = []
            var focusedID: WindowID?
            var hadReadFailure = false
            for app in apps {
                guard self.valid(token) else { return }
                let axApp = AXUIElementCreateApplication(app.processIdentifier)
                AXUIElementSetMessagingTimeout(axApp, 0.05)
                let observer = self.observer(for: app.processIdentifier, application: axApp, token: token)
                // Keep listening for the first window, even while there is nothing to read.
                guard visible[app.processIdentifier] != nil else { continue }
                let focused = app.processIdentifier == activePID ? Self.windowAttribute(axApp, kAXFocusedWindowAttribute) : nil
                guard let windows = Self.attribute(axApp, kAXWindowsAttribute) as? [AXUIElement] else {
                    hadReadFailure = true
                    continue
                }
                for element in windows {
                    guard self.valid(token) else { return }
                    AXUIElementSetMessagingTimeout(element, 0.05)
                    let readStarted = CACurrentMediaTime()
                    guard let state = Self.state(element) else { hadReadFailure = true; continue }
                    let frame = state.frame
                    let id = self.id(for: element)
                    // Some apps list a window twice; report it once.
                    guard seen.insert(id).inserted else { continue }
                    self.observe(element, id: id, observer: observer, token: token)
                    let onScreen = visible[app.processIdentifier]?.contains { WindowDiscovery.visibleMatch($0, frame) } ?? false
                    guard onScreen else { continue }
                    self.lock.lock()
                    if (self.lastWriteTimes[id] ?? 0) <= readStarted { self.lastFrames[id] = frame }
                    self.lock.unlock()
                    self.lock.lock()
                    var traits = self.baseTraits[id]
                    let children = self.lastChildren[id]
                    self.lock.unlock()
                    if traits == nil {
                        let subrole = Self.optionalSubrole(element)
                        guard subrole.readable, let role = Self.attribute(element, kAXRoleAttribute) as? String,
                              let canMove = Self.settable(element, kAXPositionAttribute),
                              let canResize = Self.settable(element, kAXSizeAttribute) else {
                            hadReadFailure = true
                            continue
                        }
                        traits = WindowTraits(
                            isStandard: WindowDiscovery.isNormalWindow(role: role, subrole: subrole.value,
                                                                       hasTitleBarButton: Self.hasTitleBarButton(element)),
                            canMove: canMove,
                            canResize: canResize,
                            isFixedSizeApp: Self.fixedSizeBundleIDs.contains(app.bundleIdentifier ?? "") || Self.zoomDisabled(element),
                            isModal: Self.bool(element, kAXModalAttribute))
                    }
                    if children == nil || !Self.sameChildren(children ?? [], state.children) {
                        traits?.hasSheet = state.children.contains { Self.attribute($0, kAXRoleAttribute) as? String == (kAXSheetRole as String) }
                    }
                    self.lock.lock()
                    // Never freeze a startup capability failure into the lifetime cache.
                    if traits?.canMove == true && traits?.canResize == true { self.baseTraits[id] = traits }
                    self.lastChildren[id] = state.children
                    self.lock.unlock()
                    traits?.isMinimized = state.minimized
                    traits?.isFullscreen = state.fullscreen
                    traits?.isTooSmall = WindowDiscovery.isTooSmall(frame.size)
                    let title = Self.attribute(element, kAXTitleAttribute) as? String
                    snapshots.append(WindowSnapshot(id: id, frame: frame, processID: app.processIdentifier, isTileable: traits?.isTileable == true, isTileableAtAnySize: traits?.isTileableAtAnySize == true, bundleIdentifier: app.bundleIdentifier, title: title))
                    if app.processIdentifier == activePID, let focused, CFEqual(element, focused) { focusedID = id }
                }
            }
            if hadReadFailure {
                self.lock.lock()
                let known = self.knownSnapshots
                let latestFrames = self.lastFrames
                let liveIDs = Set(self.elements.keys)
                self.lock.unlock()
                let discovered = Set(snapshots.map(\.id))
                // A transient AX failure must not dismantle a known strip. Retain
                // only previously classified windows corroborated by geometry.
                for (id, prior) in known where !discovered.contains(id) && liveIDs.contains(id) && policy.manages(prior.bundleIdentifier) {
                    let frame = latestFrames[id] ?? prior.frame
                    guard visible[prior.processID]?.contains(where: { WindowDiscovery.visibleMatch($0, frame) }) == true else { continue }
                    snapshots.append(WindowSnapshot(id: id, frame: frame, processID: prior.processID, isTileable: prior.isTileable, isTileableAtAnySize: prior.isTileableAtAnySize, bundleIdentifier: prior.bundleIdentifier, title: prior.title))
                }
            }
            self.lock.lock()
            for snapshot in snapshots { self.knownSnapshots[snapshot.id] = snapshot }
            self.lock.unlock()
            // Remove dead applications, including their AX run-loop sources.
            // Keep handles for excluded but running apps until queued restoration finishes.
            let pids = Set(runningApps.map(\.processIdentifier))
            self.lock.lock()
            let dead = self.observers.filter { !pids.contains($0.key) }
            for pid in dead.keys { self.observers.removeValue(forKey: pid); self.pendingAppNotifications.removeValue(forKey: pid) }
            let deadIDs = self.elements.filter { _, element in
                var pid: pid_t = 0
                AXUIElementGetPid(element, &pid)
                return !pids.contains(pid)
            }.map(\.key)
            for id in deadIDs {
                if let element = self.elements.removeValue(forKey: id) { self.elementIDs.removeValue(forKey: element) }
                self.elementPIDs.removeValue(forKey: id)
                self.observedWindows.remove(id)
                self.lastFrames.removeValue(forKey: id)
                self.knownSnapshots.removeValue(forKey: id)
                self.lastWriteTimes.removeValue(forKey: id)
                self.baseTraits.removeValue(forKey: id)
                self.lastChildren.removeValue(forKey: id)
            }
            self.lock.unlock()
            guard self.valid(token) else { return }
            self.lock.lock()
            let retry = hadReadFailure && self.discoveryRetries < 2
            self.discoveryRetries = hadReadFailure ? min(self.discoveryRetries + 1, 2) : 0
            self.lock.unlock()
            DispatchQueue.main.async {
                for observer in dead.values { CFRunLoopRemoveSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(observer), .commonModes) }
                guard self.valid(token) else { return }
                let tileable = snapshots.filter(\.isTileable).count
                let summary = "Window discovery: \(apps.count) apps, \(snapshots.count) visible windows, \(tileable) tileable; reads \(hadReadFailure ? "incomplete" : "complete")."
                if summary != self.lastDiscoverySummary {
                    self.lastDiscoverySummary = summary
                    TapeLog.shared.write(summary)
                }
                completion(snapshots, focusedID, spaces)
                // At most two notification-style retries; never poll an unresponsive app.
                if retry, self.running, self.valid(token) { self.onChange?() }
            }
        }
    }

    func apply(frames: [WindowID: CGRect]) {
        lock.lock()
        if frameWriter == nil {
            frameWriter = FrameWriteQueue { [weak self] job in self?.writeFrame(job) }
        }
        let writer = frameWriter!
        let token = generation
        let jobs = frames.compactMap { id, frame -> (pid_t, FrameWrite)? in
            guard let pid = elementPIDs[id] else { return nil }
            return (pid, FrameWrite(id: id, frame: frame, generation: token))
        }
        lock.unlock()
        writer.enqueue(jobs)
    }

    func cancelPendingWrites() {
        lock.lock(); let writer = frameWriter; lock.unlock()
        // Keep each app's lane alive: the new layout must run after any write
        // already in flight, rather than racing it on a replacement queue.
        writer?.cancelPending()
    }

    func settle(completion: @escaping () -> Void) {
        lock.lock(); let writer = frameWriter; let token = generation; lock.unlock()
        let settled = { [weak self] in
            DispatchQueue.main.async {
                guard self?.valid(token) == true else { return }
                completion()
            }
        }
        if let writer { writer.whenIdle(settled) } else { settled() }
    }

    private func writeFrame(_ job: FrameWrite) {
        guard valid(job.generation) else { return }
        lock.lock()
        let element = elements[job.id]
        let previous = lastFrames[job.id]
        lock.unlock()
        guard let element, previous.map({ !Self.matches($0, job.frame, tolerance: 0.5) }) ?? true else { return }
        let deadline = stallDeadline(job.generation, "Window write timed out; pending writes cancelled.")
        watchdog.asyncAfter(deadline: .now() + 8, execute: deadline)
        defer { deadline.cancel() }
        if job.restoring {
            let subrole = Self.optionalSubrole(element)
            guard let state = Self.state(element), subrole.readable else { refuse(job); return }
            guard !state.fullscreen,
                  Self.attribute(element, kAXRoleAttribute) as? String == (kAXWindowRole as String),
                  WindowDiscovery.isNormalWindow(role: kAXWindowRole as String, subrole: subrole.value),
                  Self.settable(element, kAXPositionAttribute) == true, Self.settable(element, kAXSizeAttribute) == true,
                  !state.children.contains(where: { Self.attribute($0, kAXRoleAttribute) as? String == (kAXSheetRole as String) }) else { return }
        }
        lock.lock()
        if generation == job.generation { lastWriteTimes[job.id] = CACurrentMediaTime() }
        lock.unlock()
        if Self.write(job.frame, previous: previous, to: element, valid: { self.valid(job.generation) }) {
            lock.lock()
            if generation == job.generation { lastFrames[job.id] = job.frame }
            lock.unlock()
        } else if job.restoring { refuse(job) }
    }
    private func refuse(_ job: FrameWrite) {
        lock.lock()
        if generation == job.generation { refusedRestores.insert(job.id) }
        lock.unlock()
    }

    func focus(_ id: WindowID, activate: Bool) {
        guard let element = element(id) else { return }
        AXUIElementSetMessagingTimeout(element, 0.05)
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        // Activation starts now; raising is independent of scan and animation backlogs.
        if activate { NSRunningApplication(processIdentifier: pid)?.activate(options: [.activateIgnoringOtherApps]) }
        lock.lock(); focusSequence += 1; let sequence = focusSequence; lock.unlock()
        submit(on: .focus) { [weak self] token in
            guard let self, self.valid(token), self.isLatestFocus(sequence) else { return }
            AXUIElementPerformAction(element, kAXRaiseAction as CFString)
            guard activate, self.valid(token), self.isLatestFocus(sequence) else { return }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.05)
            AXUIElementSetAttributeValue(application, kAXFocusedWindowAttribute as CFString, element)
        }
    }
    func raise(_ ids: [WindowID], preservingFocus focused: WindowID?) {
        var ordered = ids.filter { $0 != focused }
        if let focused { ordered.append(focused) }
        lock.lock(); let sequence = focusSequence; lock.unlock()
        submit(on: .focus) { [weak self] token in
            guard let self else { return }
            for id in ordered {
                guard self.valid(token), self.isLatestFocus(sequence) else { return }
                if let element = self.element(id) { AXUIElementPerformAction(element, kAXRaiseAction as CFString) }
            }
        }
    }
    private func isLatestFocus(_ sequence: Int) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return focusSequence == sequence
    }
    private func isLatestFocusRead(_ ticket: FocusReadTicket) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return focusReads.accepts(ticket, command: focusSequence)
    }
    private func reportFocus() {
        guard running, let pid = NSWorkspace.shared.frontmostApplication?.processIdentifier, pid != getpid() else { return }
        lock.lock()
        let ticket = focusReads.request(command: focusSequence)
        lock.unlock()
        submit(on: .focus) { [weak self] token in
            guard let self, self.valid(token), self.isLatestFocusRead(ticket) else { return }
            let application = AXUIElementCreateApplication(pid)
            AXUIElementSetMessagingTimeout(application, 0.05)
            let focused = Self.windowAttribute(application, kAXFocusedWindowAttribute)
            let id = focused.map { self.id(for: $0) }
            DispatchQueue.main.async {
                guard self.running, self.valid(token), self.isLatestFocusRead(ticket), NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else { return }
                if let id { self.onFocusChange?(id) } else { self.onChange?() }
            }
        }
    }

    func restore(frames: [WindowID: CGRect], completion: @escaping () -> Void) {
        // Restoration must follow any AX write already in flight in each app's
        // lane. Replacing those lanes could let an old parked frame win on Quit.
        invalidatePending(replaceFrameWriter: false)
        lock.lock()
        if frameWriter == nil { frameWriter = FrameWriteQueue { [weak self] in self?.writeFrame($0) } }
        let writer = frameWriter!, token = generation
        let jobs = frames.compactMap { id, frame -> (pid_t, FrameWrite)? in
            guard let pid = elementPIDs[id] else { return nil }
            return (pid, FrameWrite(id: id, frame: frame, generation: token, restoring: true))
        }
        refusedRestores.removeAll()
        lock.unlock()
        let deadline = stallDeadline(token, nil)
        watchdog.asyncAfter(deadline: .now() + 8, execute: deadline)
        writer.enqueue(jobs)
        finishRestore(jobs, writer: writer, token: token, attempt: 0, deadline: deadline, completion: completion)
    }

    private func finishRestore(_ jobs: [(pid_t, FrameWrite)], writer: FrameWriteQueue, token: Int, attempt: Int,
                               deadline: DispatchWorkItem, completion: @escaping () -> Void) {
        writer.whenIdle { [weak self] in
            guard let self else { return }
            self.lock.lock(); let refused = self.refusedRestores; self.refusedRestores.removeAll(); self.lock.unlock()
            let retry = jobs.filter { refused.contains($0.1.id) }
            // A busy app gets two more chances; otherwise its windows would stay parked off-screen.
            if !retry.isEmpty, attempt < 2, self.valid(token) {
                self.watchdog.asyncAfter(deadline: .now() + 0.25) {
                    writer.enqueue(retry)
                    self.finishRestore(retry, writer: writer, token: token, attempt: attempt + 1, deadline: deadline, completion: completion)
                }
                return
            }
            if !retry.isEmpty { TapeLog.shared.write("\(retry.count) windows did not accept their restored frame.") }
            DispatchQueue.main.async {
                deadline.cancel()
                guard self.valid(token) else { return }
                completion()
            }
        }
    }

    private func element(_ id: WindowID) -> AXUIElement? {
        lock.lock(); defer { lock.unlock() }
        return elements[id]
    }

    private func id(for element: AXUIElement) -> WindowID {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        // Every stored handle is later used for writes; a slow app must fail fast, not stall the worker.
        AXUIElementSetMessagingTimeout(element, 0.05)
        lock.lock(); defer { lock.unlock() }
        if let existing = elementIDs[element] { return existing }
        let id = WindowID()
        elements[id] = element
        elementIDs[element] = id
        elementPIDs[id] = pid
        return id
    }

    private func observer(for pid: pid_t, application: AXUIElement, token: Int) -> AXObserver? {
        lock.lock()
        let existing = observers[pid]
        let retry = pendingAppNotifications[pid] ?? []
        lock.unlock()
        if let existing {
            guard !retry.isEmpty else { return existing }
            let failed = retry.filter { Self.register(existing, application, $0, self) == .cannotComplete }
            lock.lock()
            if observers[pid] === existing { pendingAppNotifications[pid] = failed.isEmpty ? nil : failed }
            lock.unlock()
            return existing
        }
        var value: AXObserver?
        guard AXObserverCreate(pid, { _, element, notification, context in
            guard let context else { return }
            let server = Unmanaged<AXWindowServer>.fromOpaque(context).takeUnretainedValue()
            let name = notification as String
            if name == kAXFocusedWindowChangedNotification { server.reportFocus(); return }
            if name == kAXUIElementDestroyedNotification {
                server.lock.lock()
                let removed = server.elementIDs.removeValue(forKey: element)
                if let id = removed {
                    server.elements.removeValue(forKey: id)
                    server.elementPIDs.removeValue(forKey: id)
                    server.baseTraits.removeValue(forKey: id)
                    server.lastChildren.removeValue(forKey: id)
                    server.observedWindows.remove(id)
                    server.lastFrames.removeValue(forKey: id)
                    server.knownSnapshots.removeValue(forKey: id)
                    server.lastWriteTimes.removeValue(forKey: id)
                }
                server.lock.unlock()
                if let removed, server.running { server.onWindowRemoved?(removed) }
                if server.interaction?.0 == removed {
                    server.cancelInteraction()
                }
            }
            if name == kAXWindowMovedNotification || name == kAXWindowResizedNotification {
                server.lock.lock()
                let id = server.elementIDs[element]
                let written = id.flatMap { server.lastWriteTimes[$0] }
                server.lock.unlock()
                if let id, NSEvent.pressedMouseButtons & 1 != 0 {
                    // Only the window beneath the pointer can initiate a native drag.
                    // Once owned, keep it even when the pointer leaves its old frame.
                    // Validate against the freshly read frame, so a fast drag can
                    // leave its previous rectangle before the first AX notification.
                    if server.interaction?.0 == id || server.interaction == nil {
                        if server.interaction == nil {
                            server.interactionEpoch += 1
                            server.interactionHasReported = false
                            server.interaction = (id, name == kAXWindowResizedNotification ? .resize : .move)
                            server.interactionFinished = false
                        } else if name == kAXWindowResizedNotification { server.interaction = (id, .resize) }
                        server.scheduleInteractionRead()
                        return
                    }
                }
                // A reconciliation scan runs after each animation; don't rescan its own writes.
                if let written, CACurrentMediaTime() - written < 0.2 { return }
            }
            if server.running { server.onChange?() }
        }, &value) == .success, let value else { return nil }
        var failed: [String] = []
        for name in [kAXWindowCreatedNotification, kAXFocusedWindowChangedNotification, kAXSheetCreatedNotification] {
            guard valid(token) else { return nil }
            // A busy app can refuse during launch; without a retry it would never report new windows.
            if Self.register(value, application, name, self) == .cannotComplete { failed.append(name) }
        }
        // Commit under the lock so a Pause that cleared the registry cannot be undone by this older scan.
        lock.lock()
        guard generation == token else { lock.unlock(); return nil }
        observers[pid] = value
        pendingAppNotifications[pid] = failed.isEmpty ? nil : failed
        lock.unlock()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            guard self.running, self.valid(token) else {
                // Never keep an observer whose source was not installed: its app would go silent.
                self.forget(observer: value, of: pid)
                return
            }
            CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(value), .commonModes)
        }
        return value
    }

    private func forget(observer: AXObserver, of pid: pid_t) {
        lock.lock()
        if observers[pid] === observer {
            observers.removeValue(forKey: pid)
            pendingAppNotifications.removeValue(forKey: pid)
            // Windows registered on it must register again on the replacement.
            observedWindows = observedWindows.filter { elementPIDs[$0] != pid }
        }
        lock.unlock()
    }

    private static func register(_ observer: AXObserver, _ element: AXUIElement, _ name: String, _ server: AXWindowServer) -> AXError {
        AXObserverAddNotification(observer, element, name as CFString, Unmanaged.passUnretained(server).toOpaque())
    }

    private func scheduleInteractionRead(immediately: Bool = false) {
        guard running, interaction != nil else { return }
        if interactionReadInFlight { interactionReadAgain = true; return }
        // Throttle rather than debounce: native drags notify faster than 60 Hz, and restarting
        // the delay on each notification postponed the read until the pointer paused.
        if interactionReadScheduled && !immediately { return }
        interactionRead?.cancel()
        interactionReadScheduled = true
        let work = DispatchWorkItem { [weak self] in
            self?.interactionReadScheduled = false
            self?.readInteraction()
        }
        interactionRead = work
        DispatchQueue.main.asyncAfter(deadline: .now() + (immediately ? 0 : 1.0 / 60), execute: work)
    }

    private func cancelInteraction() {
        interactionEpoch += 1
        interactionRead?.cancel()
        interactionReadScheduled = false
        interaction = nil
        interactionReadInFlight = false
        interactionReadAgain = false
        interactionFinished = false
        interactionHasReported = false
    }

    private func readInteraction() {
        guard running, let (id, kind) = interaction else { return }
        guard let element = element(id) else {
            // The window's app quit mid-drag; let the next drag start cleanly.
            cancelInteraction()
            onChange?()
            return
        }
        interactionReadInFlight = true
        let ticket = interactionEpoch
        let finished = interactionFinished || NSEvent.pressedMouseButtons & 1 == 0
        submit(on: .focus) { [weak self] token in
            guard let self else { return }
            self.lock.lock(); let previous = self.lastFrames[id]; self.lock.unlock()
            let frame = Self.state(element)?.frame ?? (finished ? previous : nil)
            DispatchQueue.main.async {
                guard self.running, self.valid(token), self.interaction?.0 == id, self.interactionEpoch == ticket else { return }
                self.interactionReadInFlight = false
                if !self.interactionHasReported {
                    guard let frame, let pointer = self.pointerPosition,
                          frame.insetBy(dx: -16, dy: -16).contains(pointer),
                          previous.map({ !Self.matches($0, frame, tolerance: 0.5) }) ?? true else {
                        self.cancelInteraction()
                        return
                    }
                }
                let repeatRead = self.interactionReadAgain || (self.interactionFinished && !finished)
                self.interactionReadAgain = false
                if let frame {
                    self.interactionHasReported = true
                    self.lock.lock(); self.lastFrames[id] = frame; self.lock.unlock()
                    self.onWindowInteraction?(id, frame, kind, finished)
                }
                if finished {
                    self.interaction = nil
                    self.interactionFinished = false
                    self.onChange?()
                } else if repeatRead { self.scheduleInteractionRead(immediately: self.interactionFinished) }
            }
        }
    }

    private func observe(_ element: AXUIElement, id: WindowID, observer: AXObserver?, token: Int) {
        guard let observer else { return }
        lock.lock()
        // A scan that outlived Pause must not mark windows observed on the cleared registry.
        let inserted = generation == token && observedWindows.insert(id).inserted
        lock.unlock()
        guard inserted else { return }
        var busy = false
        for name in [kAXUIElementDestroyedNotification, kAXWindowMovedNotification, kAXWindowResizedNotification,
                     kAXWindowMiniaturizedNotification, kAXWindowDeminiaturizedNotification] {
            if Self.register(observer, element, name, self) == .cannotComplete { busy = true }
        }
        // Retry on the next scan rather than missing this window's close and drag notifications for good.
        if busy { lock.lock(); observedWindows.remove(id); lock.unlock() }
    }

    private static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success ? value : nil
    }
    private static func optionalSubrole(_ element: AXUIElement) -> (value: String?, readable: Bool) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &value)
        switch status {
        case .success: return (value as? String, value is String)
        case .attributeUnsupported, .noValue: return (nil, true)
        default: return (nil, false) // A failed read is not evidence that a dialog is normal.
        }
    }
    private static let fixedSizeBundleIDs: Set<String> = ["com.apple.calculator"]
    /// A title bar's close or minimize button, which real windows have and popups don't.
    private static func hasTitleBarButton(_ element: AXUIElement) -> Bool {
        windowAttribute(element, kAXCloseButtonAttribute) != nil || windowAttribute(element, kAXMinimizeButtonAttribute) != nil
    }
    /// The green button is there but disabled: the window keeps its size whatever Tape asks.
    private static func zoomDisabled(_ element: AXUIElement) -> Bool {
        guard let zoom = windowAttribute(element, kAXZoomButtonAttribute) else { return false }
        return (attribute(zoom, kAXEnabledAttribute) as? Bool) == false
    }
    private static func windowAttribute(_ element: AXUIElement, _ name: String) -> AXUIElement? {
        guard let value = attribute(element, name), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return (value as! AXUIElement)
    }
    private static func bool(_ element: AXUIElement, _ name: String) -> Bool { attribute(element, name) as? Bool ?? false }
    private static func settable(_ element: AXUIElement, _ name: String) -> Bool? {
        var value: DarwinBoolean = false
        guard AXUIElementIsAttributeSettable(element, name as CFString, &value) == .success else { return nil }
        return value.boolValue
    }
    private static func sameChildren(_ lhs: [AXUIElement], _ rhs: [AXUIElement]) -> Bool {
        lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { CFEqual($0, $1) }
    }
    private struct State { let frame: CGRect; let minimized: Bool; let fullscreen: Bool; let children: [AXUIElement] }
    private static func state(_ element: AXUIElement) -> State? {
        var result: CFArray?
        let names = [kAXPositionAttribute, kAXSizeAttribute, kAXMinimizedAttribute, "AXFullScreen", kAXChildrenAttribute] as CFArray
        guard AXUIElementCopyMultipleAttributeValues(element, names, [], &result) == .success,
              let values = result as? [AnyObject], values.count == 5,
              CFGetTypeID(values[0]) == AXValueGetTypeID(), CFGetTypeID(values[1]) == AXValueGetTypeID() else { return nil }
        let position = values[0], size = values[1]
        var point = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(position as! AXValue, .cgPoint, &point), AXValueGetValue(size as! AXValue, .cgSize, &dimensions),
              dimensions.width > 0, dimensions.height > 0,
              // A failed read is not evidence of "not minimized", "not full screen" or "no sheet";
              // report the window as unreadable so a known window keeps its classification.
              !values[2...4].contains(where: failedRead) else { return nil }
        return State(frame: CGRect(origin: point, size: dimensions), minimized: values[2] as? Bool ?? false,
                     fullscreen: values[3] as? Bool ?? false, children: values[4] as? [AXUIElement] ?? [])
    }
    /// Without stop-on-error, each failed attribute comes back as an AXError value; unsupported is a real answer.
    private static func failedRead(_ value: AnyObject) -> Bool {
        guard CFGetTypeID(value) == AXValueGetTypeID(), AXValueGetType(value as! AXValue) == .axError else { return false }
        var error = AXError.success
        AXValueGetValue(value as! AXValue, .axError, &error)
        return error != .attributeUnsupported && error != .noValue
    }
    private static func write(_ frame: CGRect, previous: CGRect?, to element: AXUIElement, valid: () -> Bool) -> Bool {
        var point = frame.origin
        var size = frame.size
        guard valid(), let sizeValue = AXValueCreate(.cgSize, &size), let pointValue = AXValueCreate(.cgPoint, &point) else { return false }
        // Resize first so the old width cannot make a move cross a display edge.
        let resized = FrameMotion.needsResize(from: previous, to: frame)
            ? AXUIElementSetAttributeValue(element, kAXSizeAttribute as CFString, sizeValue) : .success
        guard valid() else { return false }
        let moved = FrameMotion.needsMove(from: previous, to: frame)
            ? AXUIElementSetAttributeValue(element, kAXPositionAttribute as CFString, pointValue) : .success
        return resized == .success && moved == .success
    }
    private static func matches(_ lhs: CGRect, _ rhs: CGRect, tolerance: CGFloat = 3) -> Bool {
        abs(lhs.minX - rhs.minX) < tolerance && abs(lhs.minY - rhs.minY) < tolerance &&
        abs(lhs.width - rhs.width) < tolerance && abs(lhs.height - rhs.height) < tolerance
    }
    private static func visibleWindows() -> [pid_t: [CGRect]] {
        let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        var result: [pid_t: [CGRect]] = [:]
        for window in list {
            guard let pid = window[kCGWindowOwnerPID as String] as? Int32,
                  let layer = window[kCGWindowLayer as String] as? Int, layer == 0,
                  let bounds = window[kCGWindowBounds as String] as? [String: Any],
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            result[pid, default: []].append(rect)
        }
        return result
    }
}
