#if DEBUG
import AppKit
import SwiftUI
import os
import CoreLocation
@preconcurrency import AVFoundation

/// Real model/worker regressions with deterministic slow readers; no user data or permissions.
@MainActor enum PerformanceRegressionChecks {
    static func run() async {
        precondition(Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces.FeatureQA")
        let calls = OSAllocatedUnfairLock(initialState: 0)
        MissionControl.queryOverride = { _ in
            precondition(!Thread.isMainThread, "WindowServer work must leave the main thread")
            calls.withLock { $0 += 1 }
            Thread.sleep(forTimeInterval: 0.12)
            return false
        }
        async let first = MissionControl.isActive()
        async let second = MissionControl.isActive()
        try? await Task.sleep(nanoseconds: 20_000_000)
        let results = await (first, second)
        precondition(!results.0 && !results.1 && calls.withLock { $0 } == 1,
                     "Concurrent display checks must share one background query")

        let settings = NookSettings.shared
        settings.expandOnHover = true; settings.hoverDelay = 0.15
        let model = NotchViewModel(geometry: .synthetic, availableWidth: 1440, settings: settings,
            shelf: ShelfStore.shared, nowPlaying: AppServices.shared.nowPlaying,
            powerMonitor: AppServices.shared.powerMonitor, timerService: AppServices.shared.timerService,
            bluetoothMonitor: AppServices.shared.bluetooth, systemActivityMonitor: AppServices.shared.systemActivity,
            teleprompter: AppServices.shared.teleprompter)
        model.hoverChanged(true)
        try? await Task.sleep(nanoseconds: 40_000_000)
        model.hoverChanged(false)
        try? await Task.sleep(nanoseconds: 160_000_000)
        precondition(model.state == .collapsed, "A late hover query must not open after pointer exit")
        model.hoverChanged(true)
        try? await Task.sleep(nanoseconds: 180_000_000)
        precondition(model.state == .expanded, "A valid hover still opens")
        model.selectedTab = .tray
        model.hoverChanged(false)
        try? await Task.sleep(nanoseconds: 380_000_000)
        precondition(model.state == .expanded, "Page navigation must not collapse while the pointer settles")
        try? await Task.sleep(nanoseconds: 320_000_000)
        precondition(model.state == .collapsed, "Pointer-exit collapse resumes after navigation")
        model.collapse(); model.hoverChanged(false)
        settings.hoverDelay = 0.01
        MissionControl.queryOverride = { _ in true }
        model.hoverChanged(true)
        try? await Task.sleep(nanoseconds: 60_000_000)
        precondition(model.state == .collapsed, "Mission Control must suppress hover opening")
        model.hoverChanged(false)
        MissionControl.queryOverride = { _ in false }
        // SwiftUI can report hover over where the open panel was; only the closed notch opens.
        settings.hoverDelay = 0.05
        settings.scrollGesturesEnabled = true
        var pointer = NSPoint(x: 720, y: 820)
        model.screenFrame = NSRect(x: 0, y: 0, width: 1440, height: 900)
        model.pointerLocation = { pointer }
        model.hoverChanged(true)
        model.handleScroll(deltaX: 0, deltaY: 40)
        try? await Task.sleep(nanoseconds: 250_000_000)
        precondition(model.state == .collapsed && !model.isHoveringCollapsed,
                     "Hover or scroll off the closed notch must not peek or open")
        pointer = NSPoint(x: 720, y: 890)
        try? await Task.sleep(nanoseconds: 300_000_000)
        precondition(model.state == .expanded, "A hover that began off the notch opens once the pointer reaches it")
        model.collapse(); model.hoverChanged(false)
        model.screenFrame = nil
        MissionControl.queryOverride = nil

        precondition(AppServices.prewarmedServices(dock: [.weather, .calendar, .reminders, .system],
            calendarAllowed: false, remindersAllowed: false) == ["weather", "stats", "power"],
            "Hover warming must not request Calendar, Reminders or Bluetooth permissions")
        precondition(AppServices.prewarmedServices(dock: [.calendar, .reminders],
            calendarAllowed: true, remindersAllowed: true) == ["events", "reminders"])
        let gate = DispatchSemaphore(value: 0)
        let stats = SystemStatsService()
        stats.beforeSample = {
            precondition(!Thread.isMainThread, "Statistics must sample on the worker")
            _ = gate.wait(timeout: .now() + 2)
        }
        let started = Date()
        stats.start()
        precondition(Date().timeIntervalSince(started) < 0.2, "Starting stats must not wait for I/O")
        try? await Task.sleep(nanoseconds: 20_000_000)
        stats.stop(); gate.signal()
        try? await Task.sleep(nanoseconds: 120_000_000)
        precondition(stats.history.isEmpty, "Stopped statistics must reject an in-flight result")
        stats.beforeSample = nil
        stats.start()
        await waitUntil { !stats.history.isEmpty }
        stats.stop()

        let resources = MotifImages.shared
        resources.prepare(.petals)
        await waitUntil { resources.image(for: "ThemeBlossom") != nil }
        let prepared = resources.image(for: "ThemeBlossom")!
        resources.prepare(.petals)
        precondition(resources.image(for: "ThemeBlossom") === prepared,
                     "Closing/reopening must reuse the decoded current scene")
        resources.prepare(.waves); resources.prepare(.petals)
        await waitUntil { resources.image(for: "ThemeBlossom") != nil }
        precondition(resources.image(for: "ThemeTidal") == nil, "A stale theme decode cannot replace the selected scene")

        let bitmap = CGContext(data: nil, width: 16, height: 16, bitsPerComponent: 8,
            bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        bitmap.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1)); bitmap.fill(CGRect(x: 0, y: 0, width: 16, height: 16))
        let artwork = NSImage(cgImage: bitmap.makeImage()!, size: NSSize(width: 16, height: 16))
        let washes = ArtworkWashStore.shared
        washes.prepare(artwork); washes.prepare(nil)
        try? await Task.sleep(nanoseconds: 150_000_000)
        precondition(washes.image == nil, "A late artwork wash must not resurrect a cleared cover")
        washes.prepare(artwork)
        await waitUntil { washes.image != nil }
        let wash = washes.image
        washes.prepare(artwork)
        precondition(washes.image === wash, "Repeated media polls must reuse the prepared wash")
        washes.prepare(nil)
        await checkMirrorLifecycle()
        await checkWeatherCacheAndPolling()
        print("Performance checks passed: background/coalesced Mission Control during hover delay, hover cancellation and suppression, hover off the closed notch, safe dock warming, nonblocking stats and stopped-result rejection, retained scenes and artwork, persistent Weather cache and forced polling")
    }

    private static func checkMirrorLifecycle() async {
        let suite = "dev.opensource.MacSpaces.MirrorQA." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let probe = MirrorDriverProbe()
        var factoryCalls = 0
        let camera = CameraController(defaults: defaults, authorization: { .authorized }, workerFactory: { event in
            factoryCalls += 1; probe.event = event; return probe
        })
        camera.prewarm()
        precondition(probe.requests.count == 1 && !probe.requests[0].running, "Mirror prewarming configures without starting capture")
        await waitUntil { camera.session != nil }
        let retainedSession = camera.session
        let ownerA = UUID(), ownerB = UUID(), first = UUID(), second = UUID()
        camera.startIfAuthorized(id: first, owner: ownerA)
        precondition(camera.status == .starting && probe.requests.last!.running, "Visible Mirror starts immediately, then waits for video")
        let firstGeneration = probe.requests.last!.generation
        probe.event?(.firstFrame(firstGeneration))
        await waitUntil { camera.status == .running }
        camera.startIfAuthorized(id: second, owner: ownerB)
        let view = CameraPreviewHostView()
        view.camera = camera; view.ownerID = ownerA; view.presentationID = first
        view.preview.session = camera.session; view.preview.isHidden = false
        camera.register(view)
        camera.endPresentation(owner: ownerA)
        precondition(view.preview.isHidden && view.preview.session == nil,
                     "Leaving a page must synchronously hide and detach its layer before removal")
        precondition(!camera.isPresentationActive(first) && camera.isPresentationActive(second) && probe.stops == 0,
                     "Closing one display must preserve the other display's camera")
        camera.endPresentation(owner: ownerB)
        precondition(camera.status == .idle && probe.stops == 1)
        probe.event?(.firstFrame(firstGeneration))
        try? await Task.sleep(nanoseconds: 20_000_000)
        precondition(camera.status == .idle, "A late frame must not resurrect a closed Mirror")
        let reopened = UUID()
        camera.startIfAuthorized(id: reopened, owner: ownerA)
        precondition(camera.status == .starting && factoryCalls == 1 && camera.session === retainedSession,
                     "Reopening reuses the configured session and driver")
        let request = probe.requests.last!.generation
        probe.event?(.interrupted(request))
        await waitUntil { camera.status == .interrupted }
        probe.event?(.resuming(request))
        await waitUntil { camera.status == .starting }
        probe.event?(.firstFrame(request))
        await waitUntil { camera.status == .running }
        probe.event?(.failed(request, "Synthetic camera error"))
        await waitUntil { camera.status == .failed("Synthetic camera error") }
        camera.retry()
        precondition(camera.status == .starting && probe.requests.last!.generation != request)
        camera.selectCamera(.init(id: "camera-2", name: "Synthetic camera 2", systemImage: "video"))
        precondition(defaults.string(forKey: "mirror.selectedCameraID") == "camera-2")
        // An unplugged camera: Mirror shows the fallback the driver chose, keeps the
        // person's choice and asks for it again (so it returns when plugged back in).
        probe.event?(.prepared(probe.requests.last!.generation, probe.session, [.init(id: "camera-1", name: "Built-in", systemImage: "video")], "camera-1"))
        await waitUntil { camera.selectedCameraID == "camera-1" }
        precondition(defaults.string(forKey: "mirror.selectedCameraID") == "camera-2" && camera.preferredCameraID == "camera-2",
                     "A fallback never replaces the chosen camera")
        camera.refreshAvailableCameras()
        precondition(probe.selections.last == "camera-2", "The chosen camera is requested again")
        camera.endPresentation(owner: ownerA)

        let unrequested = CameraController(defaults: defaults, authorization: { .notDetermined }, workerFactory: { _ in
            preconditionFailure("Prewarming or showing permission UI must not configure a camera")
        })
        unrequested.prewarm()
        unrequested.startIfAuthorized(id: UUID(), owner: ownerA)
        precondition(unrequested.status == .permissionRequired)
        unrequested.endPresentation(owner: ownerA)

        let discoveries = OSAllocatedUnfairLock(initialState: 0)
        let prepared = OSAllocatedUnfairLock(initialState: [ObjectIdentifier]())
        let worker = CameraSessionWorker(discover: {
            precondition(!Thread.isMainThread, "Device discovery must leave the UI thread")
            discoveries.withLock { $0 += 1 }; return []
        }, event: { event in
            if case .prepared(_, let session, _, _) = event { prepared.withLock { $0.append(ObjectIdentifier(session)) } }
        })
        worker.configure(selectedID: nil, generation: 1, startRunning: false, forceDiscovery: false)
        await waitUntil { prepared.withLock { $0.count } == 1 }
        worker.configure(selectedID: nil, generation: 2, startRunning: false, forceDiscovery: false)
        await waitUntil { prepared.withLock { $0.count } == 2 }
        precondition(discoveries.withLock { $0 } == 1 && prepared.withLock { Set($0).count } == 1,
                     "Discovery and the session must be reused on quick revisits")
        worker.configure(selectedID: nil, generation: 3, startRunning: false, forceDiscovery: true)
        await waitUntil { prepared.withLock { $0.count } == 3 }
        precondition(discoveries.withLock { $0 } == 2, "Device changes invalidate discovery")
        worker.shutdown()
        print("Mirror checks passed: shared session, off-main cached discovery, configuration-only prewarming, first-frame readiness, multi-display ownership, transition detachment, interruption/error recovery and late-result rejection")
    }

    private static func checkWeatherCacheAndPolling() async {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("macspaces-weather-qa-" + UUID().uuidString)
        let cache = directory.appendingPathComponent("forecast.json")
        defer { try? FileManager.default.removeItem(at: directory) }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [WeatherFixtureProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        WeatherFixtureProtocol.forecastRequests.withLock { $0 = 0 }
        let first = WeatherService(cacheURL: cache, networkSession: session)
        first.locationAuthorizationOverride = .denied
        first.startIfNeeded(allowLocationPrompt: false)
        await waitUntil { first.snapshot?.temperature == 57 && FileManager.default.fileExists(atPath: cache.path) }
        first.stop()
        let firstCount = WeatherFixtureProtocol.forecastRequests.withLock { $0 }

        var earlier = try! JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as! [String: Any]
        earlier["fetchedAt"] = Date().addingTimeInterval(-14 * 60).timeIntervalSinceReferenceDate
        try! JSONSerialization.data(withJSONObject: earlier).write(to: cache, options: .atomic)

        let restored = WeatherService(cacheURL: cache, networkSession: session)
        restored.locationAuthorizationOverride = .denied
        restored.startIfNeeded(allowLocationPrompt: false)
        await waitUntil { restored.snapshot?.temperature == 57 }
        precondition(restored.locationName == "Chicago", "A cold service restores its last forecast and location without the network")
        precondition((restored.nextRefreshDate?.timeIntervalSinceNow ?? .infinity) < 62,
                     "Cold cache restoration must schedule the remaining minute, not another full 15 minutes")
        try? await Task.sleep(nanoseconds: 80_000_000)
        precondition(WeatherFixtureProtocol.forecastRequests.withLock { $0 } == firstCount,
                     "Reopening with a fresh persisted forecast must not download again")
        restored.refresh()
        await waitUntil { WeatherFixtureProtocol.forecastRequests.withLock { $0 } > firstCount }
        restored.stop()
        precondition(restored.snapshot?.temperature == 57, "Stopping or refreshing retains usable conditions")

        var invalidUnit = try! JSONSerialization.jsonObject(with: Data(contentsOf: cache)) as! [String: Any]
        invalidUnit["unit"] = WidgetOptions.shared.temperatureUnit == .fahrenheit ? "celsius" : "fahrenheit"
        try! JSONSerialization.data(withJSONObject: invalidUnit).write(to: cache, options: .atomic)
        let mismatched = WeatherService(cacheURL: cache, networkSession: session)
        try? await Task.sleep(nanoseconds: 80_000_000)
        precondition(mismatched.snapshot == nil, "Cached temperatures in another system unit must not be shown")
        try! Data("bad cache".utf8).write(to: cache, options: .atomic)
        let malformed = WeatherService(cacheURL: cache, networkSession: session)
        try? await Task.sleep(nanoseconds: 80_000_000)
        precondition(malformed.snapshot == nil, "A corrupt cache must leave live fetching available")
    }

    private static func waitUntil(_ condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        preconditionFailure("Timed out waiting for the background result")
    }
}

private final class MirrorDriverProbe: MirrorSessionDriving, @unchecked Sendable {
    struct Request { let generation: Int; let running: Bool }
    var requests: [Request] = []
    var selections: [String?] = []
    var stops = 0
    var event: (@Sendable (MirrorCameraEvent) -> Void)?
    let session = AVCaptureSession()
    func configure(selectedID: String?, generation: Int, startRunning: Bool, forceDiscovery: Bool) {
        requests.append(.init(generation: generation, running: startRunning))
        selections.append(selectedID)
        let options = [MirrorCameraOption(id: "camera-1", name: "Synthetic camera 1", systemImage: "video"),
                       MirrorCameraOption(id: "camera-2", name: "Synthetic camera 2", systemImage: "video")]
        event?(.prepared(generation, session, options, selectedID ?? "camera-1"))
    }
    func stop(generation: Int) { stops += 1 }
    func shutdown() {}
}

/// All weather checks use synthetic locations and forecasts, never the network
/// or the user's location permission.
private final class WeatherFixtureProtocol: URLProtocol, @unchecked Sendable {
    static let forecastRequests = OSAllocatedUnfairLock(initialState: 0)
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let forecast = request.url?.host == "api.open-meteo.com"
        if forecast { Self.forecastRequests.withLock { $0 += 1 } }
        let json = forecast
            ? #"{"current":{"temperature_2m":57,"weather_code":51},"daily":{"temperature_2m_max":[59],"temperature_2m_min":[55]}}"#
            : #"{"latitude":41.9,"longitude":-87.6,"city":"Chicago"}"#
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(json.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
