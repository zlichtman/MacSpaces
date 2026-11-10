import AppKit
import ApplicationServices
import Carbon
import CoreGraphics
import Foundation

// The Tape engine and controller against fake window servers, clocks and logging: nothing here
// touches a real window. Ported from Tape's own test suite.

func expect(_ condition: Bool, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(condition, message(), file: file, line: line)
}
func expectFalse(_ condition: Bool, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(!condition, message(), file: file, line: line)
}
func expectEqual<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(a == b, "\(a) != \(b) \(message())", file: file, line: line)
}
func expectEqual<T: BinaryFloatingPoint>(_ a: T, _ b: T, accuracy: T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(abs(a - b) <= accuracy, "\(a) != \(b) \(message())", file: file, line: line)
}
func expectNotEqual<T: Equatable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(a != b, "both \(a) \(message())", file: file, line: line)
}
func expectNil<T>(_ value: T?, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(value == nil, "\(String(describing: value)) isn't nil \(message())", file: file, line: line)
}
func expectNotNil<T>(_ value: T?, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(value != nil, message(), file: file, line: line)
}
func expectLess<T: Comparable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(a < b, "\(a) isn't under \(b) \(message())", file: file, line: line)
}
func expectGreater<T: Comparable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(a > b, "\(a) isn't over \(b) \(message())", file: file, line: line)
}
func expectAtMost<T: Comparable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(a <= b, "\(a) is over \(b) \(message())", file: file, line: line)
}
func expectAtLeast<T: Comparable>(_ a: T, _ b: T, _ message: @autoclosure () -> String = "", file: StaticString = #fileID, line: UInt = #line) {
    precondition(a >= b, "\(a) is under \(b) \(message())", file: file, line: line)
}
func fail(_ message: String, file: StaticString = #fileID, line: UInt = #line) {
    preconditionFailure(message, file: file, line: line)
}

/// One empty domain per call; `Scripts/check-tape.sh` deletes its file afterwards.
func freshDefaults() -> UserDefaults {
    let name = "dev.opensource.MacSpaces.TapeChecks"
    let defaults = UserDefaults(suiteName: name)!
    defaults.removePersistentDomain(forName: name)
    return defaults
}

/// The separate app's settings, copied once on the first switch-on.
@MainActor func importingTapeSettings() {
    typealias Keys = WidgetOptions.Keys
    var policy = AppPolicy()
    policy.setManaged(false, bundleID: "app.excluded")
    let good: [String: Any] = [
        "gap": 12.0, "edgeGap": 0.0, "centering": "always", "reduceMotion": true, "layout.sharedWidths": true,
        "apps.policy": try! JSONEncoder().encode(policy), "apps.paths": ["app.excluded": "/Applications/X.app"],
        "displays.disabled": ["display"], "completedOnboarding": true,
    ]
    var defaults = freshDefaults()
    var asked = 0
    TapeSettings.importOnce(into: defaults) { asked += 1; return good }
    var settings = TapeSettings(defaults: defaults)
    expectEqual(settings.gap, 12); expectEqual(settings.edgeGap, 0); expectEqual(settings.centering, .always)
    expect(settings.reduceMotion); expect(settings.sharedWidths); expectEqual(settings.appPolicy, policy)
    expectEqual(settings.appPaths, ["app.excluded": "/Applications/X.app"]); expectEqual(settings.disabledDisplays, ["display"])
    expectNil(defaults.object(forKey: "completedOnboarding"), "Only the listed settings come across")
    // Once only: a change here stands, and the other app isn't looked at again.
    settings.gap = 20
    TapeSettings.importOnce(into: defaults) { asked += 1; return good }
    expectEqual(asked, 1)
    expectEqual(TapeSettings(defaults: defaults).gap, 20)
    // Anything out of range or of the wrong kind falls back to the default.
    defaults = freshDefaults()
    TapeSettings.importOnce(into: defaults) {
        ["gap": 900.0, "edgeGap": "wide", "centering": "sometimes", "reduceMotion": "yes", "layout.sharedWidths": 3,
         "apps.policy": Data([1, 2, 3]), "apps.paths": ["a": 1], "displays.disabled": "display"]
    }
    settings = TapeSettings(defaults: defaults)
    expectEqual(settings.gap, 8); expectEqual(settings.edgeGap, 8); expectEqual(settings.centering, .never)
    expectFalse(settings.reduceMotion); expectFalse(settings.sharedWidths); expectEqual(settings.appPolicy, AppPolicy())
    expectEqual(settings.appPaths, [:]); expectEqual(settings.disabledDisplays, [])
    expect(defaults.bool(forKey: Keys.tapeImported), "Looked at once, whatever it held")
    // No separate app: the same, and it stays done.
    defaults = freshDefaults()
    TapeSettings.importOnce(into: defaults) { nil }
    expect(defaults.bool(forKey: Keys.tapeImported))
    expectEqual(TapeSettings(defaults: defaults).gap, 8)
}

/// Tape on or off per desktop, against a fake list of Spaces.
final class DesktopTests {
    private let a = TapeDisplay(id: "AAAA", name: "Built-in", geometry: ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900)))
    private let b = TapeDisplay(id: "BBBB", name: "External", geometry: ScreenGeometry(frame: CGRect(x: 1600, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 1600, y: 30, width: 1600, height: 900)))
    private func entry(_ identifier: String, showing: String) -> SpaceDisplay {
        let desktops = ["one", "two"].enumerated().map { SpaceDesktop(uuid: identifier + $0.element, number: $0.offset + 1) }
        return SpaceDisplay(identifier: identifier, desktops: desktops, current: desktops.first { $0.uuid == identifier + showing },
                            order: desktops.map(\.uuid), showing: identifier + showing)
    }
    private func windows(on display: TapeDisplay, count: Int = 2) -> [WindowSnapshot] {
        (0..<count).map {
            WindowSnapshot(id: WindowID(), frame: CGRect(x: display.geometry.frame.minX + 30 + Double($0) * 450, y: 50, width: 400, height: 700),
                           processID: 0, isTileable: true, bundleIdentifier: "fixture")
        }
    }
    @MainActor private func fixture(displays: [TapeDisplay]? = nil) -> (TapeController, TapeSettings, FakeWindows, FakeAnimator, TestFrameClock) {
        let settings = TapeSettings(defaults: freshDefaults()), server = FakeWindows(), animator = FakeAnimator(), clock = TestFrameClock()
        let controller = TapeController(settings: settings, server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false,
                                        scrollClock: clock, log: { _ in }, displays: displays ?? [a],
                                        animatorFactory: { FakeAnimator() }, clockFactory: { TestFrameClock() })
        return (controller, settings, server, animator, clock)
    }
    @MainActor private func settle() async { try? await Task.sleep(nanoseconds: 150_000_000) }
    @MainActor private func finishScan(_ server: FakeWindows, _ windows: [WindowSnapshot], focus: WindowID?) async {
        await settle()
        guard let scan = server.scans.last else { return fail("Expected a scan") }
        server.scans.removeAll()
        scan(windows, focus)
    }
    private func at(_ windows: [WindowSnapshot], _ frames: [WindowID: CGRect]) -> [WindowSnapshot] {
        windows.map { WindowSnapshot(id: $0.id, frame: frames[$0.id] ?? $0.frame, processID: 0, isTileable: true, bundleIdentifier: $0.bundleIdentifier) }
    }

    @MainActor func testArrivingOnAnOffDesktopLeavesItAlone() async {
        let (controller, settings, server, animator, clock) = fixture()
        settings.disabledSpaces = ["AAAAone"]
        server.spaces = [entry("AAAA", showing: "one")]
        let list = windows(on: a)
        controller.resume()
        await finishScan(server, list, focus: list[0].id)
        expectEqual(controller.managedCount, 0)
        expect(controller.isOffOnThisDesktop)
        expect(animator.animations.isEmpty && server.writes.isEmpty, "Nothing moves on an off desktop")
        expect(controller.managedWindowChoices.isEmpty && controller.windowChoices.isEmpty)
        expect(controller.scrollTargets.isEmpty, "Scrolling stays with the app")
        controller.perform(.strip(.right)); controller.perform(.center)
        controller.scroll(by: 40); clock.tick?()
        expect(server.writes.isEmpty && server.focused.isEmpty, "Keys and scrolling do nothing there")
        controller.pause()
        expect(server.restored.isEmpty, "Tape never touched them, so nothing goes back")
    }
    @MainActor func testTurningOffTheDesktopYouAreOnPutsItsWindowsBack() async {
        let (controller, settings, server, animator, _) = fixture()
        server.spaces = [entry("AAAA", showing: "one")]
        let list = windows(on: a)
        controller.resume()
        await finishScan(server, list, focus: list[0].id)
        expectEqual(controller.managedCount, 2)
        expect(!animator.current.isEmpty)
        let moved = animator.current
        settings.disabledSpaces = ["AAAAone"]
        await finishScan(server, at(list, moved), focus: list[0].id)
        expectEqual(controller.managedCount, 0)
        for window in list { expectEqual(server.writes.last?[window.id], window.frame) }
        // Back on: arranged again, and pausing still puts them where they started.
        settings.disabledSpaces = []
        await finishScan(server, list, focus: list[0].id)
        expectEqual(controller.managedCount, 2)
        controller.pause()
        expectEqual(server.restored, Dictionary(uniqueKeysWithValues: list.map { ($0.id, $0.frame) }))
    }
    @MainActor func testTurningOffAnotherDesktopWaitsForTheNextVisit() async {
        let (controller, settings, server, animator, _) = fixture()
        server.spaces = [entry("AAAA", showing: "one")]
        let first = windows(on: a), second = windows(on: a, count: 1)
        controller.resume()
        await finishScan(server, first, focus: first[0].id)
        let moved = animator.current
        // Over on desktop two, turning desktop one off moves nothing yet.
        server.spaces = [entry("AAAA", showing: "two")]
        server.onDesktopChange?()
        await finishScan(server, second, focus: second[0].id)
        let writes = server.writes.count
        settings.disabledSpaces = ["AAAAone"]
        await finishScan(server, at(second, animator.current), focus: second[0].id)
        for write in server.writes[writes...] { expectNil(write[first[0].id]); expectNil(write[first[1].id]) }
        expectEqual(controller.managedCount, 1)
        // Going back shows them parked where Tape left them, and they return.
        server.spaces = [entry("AAAA", showing: "one")]
        server.onDesktopChange?()
        await finishScan(server, at(first, moved), focus: first[0].id)
        expectEqual(controller.managedCount, 0)
        for window in first { expectEqual(server.writes.last?[window.id], window.frame) }
        controller.pause()
        expectNil(server.restored[first[0].id], "Already back")
    }
    @MainActor func testPausingRestoresADesktopTurnedOffFromElsewhere() async {
        let (controller, settings, server, _, _) = fixture()
        server.spaces = [entry("AAAA", showing: "one")]
        let first = windows(on: a), second = windows(on: a, count: 1)
        controller.resume()
        await finishScan(server, first, focus: first[0].id)
        server.spaces = [entry("AAAA", showing: "two")]
        server.onDesktopChange?()
        await finishScan(server, second, focus: second[0].id)
        settings.disabledSpaces = ["AAAAone"]
        await settle()
        controller.pause()
        for window in first + second { expectEqual(server.restored[window.id], window.frame, "Nothing stays parked") }
    }
    @MainActor func testEachDisplayFollowsItsOwnDesktop() async {
        let (controller, settings, server, _, _) = fixture(displays: [a, b])
        settings.disabledSpaces = ["BBBBone"]
        server.spaces = [entry("aaaa", showing: "one"), entry("BBBB", showing: "one")]
        let left = windows(on: a), right = windows(on: b)
        controller.resume()
        await finishScan(server, left + right, focus: left[0].id)
        expectEqual(controller.displayChoices.map(\.windowCount), [2, 0], "Identifiers match whatever their case")
        expectFalse(controller.isOffOnThisDesktop)
        expectFalse(controller.canSendToDisplay, "An off desktop takes no windows")
        expectFalse(controller.canReceiveWindows("BBBB"))
        expectEqual(controller.scrollTargets, [a.geometry.frame])
        controller.pause()
    }
    @MainActor func testWithoutThePrivateListTapeRunsEverywhere() async {
        let (controller, settings, server, _, _) = fixture()
        settings.disabledSpaces = ["AAAAone"]
        server.spaces = nil
        let list = windows(on: a)
        controller.resume()
        await finishScan(server, list, focus: list[0].id)
        expectEqual(controller.managedCount, 2)
        expectFalse(controller.isOffOnThisDesktop)
        controller.pause()
    }
    func testWhatCountsAsOff() {
        let main = SpaceDisplay(identifier: "Main", desktops: [SpaceDesktop(uuid: "x", number: 1)], current: nil, order: ["x", "full"], showing: "full")
        expectFalse(SpaceLayout.isShowingDisabled(on: "AAAA", in: nil, disabled: ["x"]), "No list")
        expectFalse(SpaceLayout.isShowingDisabled(on: "AAAA", in: [main], disabled: []), "Nothing off")
        expectFalse(SpaceLayout.isShowingDisabled(on: "AAAA", in: [main], disabled: ["x"]), "A full-screen space isn't a desktop")
        expect(SpaceLayout.isShowingDisabled(on: "AAAA", in: [main], disabled: ["full"]), "Main covers every display")
        expectFalse(SpaceLayout.isShowingDisabled(on: "CCCC", in: [entry("AAAA", showing: "one"), entry("BBBB", showing: "one")], disabled: ["AAAAone"]), "A display not listed yet runs")
    }
}

/// Off means gone: nothing keeps the controller after it has put windows back.
@MainActor func switchingOffFreesTheController() async {
    weak var freed: TapeController?
    var finished = false
    await {
        let server = FakeWindows()
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
        let window = WindowSnapshot(id: WindowID(), frame: CGRect(x: 40, y: 60, width: 500, height: 600), processID: 0, isTileable: true, bundleIdentifier: "fixture")
        let controller = TapeController(settings: TapeSettings(defaults: freshDefaults()), server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: screen, log: { _ in })
        freed = controller
        controller.resume()
        try? await Task.sleep(nanoseconds: 100_000_000)
        server.scans.removeFirst()([window], window.id)
        controller.shutdown { finished = true }
        expect(finished)
        expectEqual(server.restored, [window.id: window.frame])
    }()
    try? await Task.sleep(nanoseconds: 300_000_000)
    expectNil(freed, "A controller outlived Turn Off")
}

final class Expectation: @unchecked Sendable {
    let done = DispatchSemaphore(value: 0)
    func fulfill() { done.signal() }
}
func expectation(description: String) -> Expectation { Expectation() }
func wait(for expectations: [Expectation], timeout: TimeInterval, file: StaticString = #fileID, line: UInt = #line) {
    for expectation in expectations {
        precondition(expectation.done.wait(timeout: .now() + timeout) == .success, "Timed out", file: file, line: line)
    }
}

final class LayoutTests {
    private let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1440, height: 900),
                                        visibleFrame: CGRect(x: 0, y: 25, width: 1440, height: 825))
    private let options = LayoutOptions(gap: 8, edgeGap: 8)
    private func strip(_ count: Int, width: ColumnWidth = .fraction(0.5)) -> Strip {
        var result = Strip()
        for _ in 0..<count { result.insert(WindowID(), foreground: true, width: width) }
        // These geometry fixtures exercise explicitly chosen widths.
        for index in result.columns.indices { result.columns[index].automaticWidth = false }
        result.focusedWindow = result.columns.first?.windows.first
        return result
    }

    func testEmptyStripHasNoFrames() {
        expect(StripLayout.frames(for: Strip(), screen: screen, options: options).isEmpty)
    }
    func testAutomaticLoneWindowFillsScreenAndTabNotificationsCannotHalveIt() {
        var model = Strip()
        let id = WindowID()
        model.insert(id, foreground: true)
        expectEqual(StripLayout.frames(for: model, screen: screen, options: options)[id]?.width, 1424)
        model.insert(id, foreground: true) // Same native window, another app tab.
        expectEqual(StripLayout.frames(for: model, screen: screen, options: options)[id]?.width, 1424)
        let other = WindowID()
        model.insert(other, foreground: true)
        expectEqual(StripLayout.frames(for: model, screen: screen, options: options)[id]?.width, 712)
        model.remove(other)
        expectEqual(StripLayout.frames(for: model, screen: screen, options: options)[id]?.width, 1424)
        model.perform(.setWidth(0.5))
        expectEqual(StripLayout.frames(for: model, screen: screen, options: options)[id]?.width, 712)
    }
    func testFramesRespectMenuBarDockAndEdgeGaps() {
        let model = strip(1)
        let frame = StripLayout.frames(for: model, screen: screen, options: options).values.first!
        expectEqual(frame.minX, 8)
        expectEqual(frame.minY, 33)
        expectEqual(frame.maxY, 842)
        expectEqual(frame.width, 712)
    }
    func testFullWidthExcludesBothEdgeGaps() {
        let frame = StripLayout.frames(for: strip(1, width: .fraction(1)), screen: screen, options: options).values.first!
        expectEqual(frame.width, 1424)
        expectEqual(frame.maxX, 1432)
    }
    func testAppMinimumWidthRetainsPresetAndPushesNextColumn() {
        var model = strip(2)
        model.columns[0].minimumWidth = 900
        let rects = StripLayout.columnRects(for: model, screen: screen, options: options)
        expectEqual(rects[0].width, 900)
        expectEqual(rects[1].minX, 916)
        expectEqual(model.columns[0].width, .fraction(0.5))
    }
    func testLogicalColumnsNeverOverlap() {
        let rects = StripLayout.columnRects(for: strip(12), screen: screen, options: options)
        for (left, right) in zip(rects, rects.dropFirst()) { expectEqual(right.minX - left.maxX, 8) }
    }
    func testZeroGapsAreSupported() {
        let rects = StripLayout.columnRects(for: strip(2), screen: screen, options: LayoutOptions(gap: 0, edgeGap: 0))
        expectEqual(rects[0].minX, 0)
        expectEqual(rects[0].maxX, rects[1].minX)
        expectEqual(rects[1].maxX, 1440)
    }
    func testViewportOffsetDoesNotChangeColumnWidth() {
        var model = strip(3)
        let before = StripLayout.columnRects(for: model, screen: screen, options: options)
        model.scrollOffset = 350
        let after = StripLayout.columnRects(for: model, screen: screen, options: options)
        for (old, new) in zip(before, after) {
            expectEqual(old.width, new.width)
            expectEqual(new.minX, old.minX - 350)
        }
    }
    func testFocusOnlyScrollsAsFarAsNeeded() {
        var model = strip(3)
        model.perform(.focus(.right))
        expectEqual(StripLayout.revealedOffset(for: model, screen: screen, options: options), 8)
        model.scrollOffset = 8
        expectEqual(StripLayout.revealedOffset(for: model, screen: screen, options: options), 8)
        model.perform(.focus(.last))
        expectEqual(StripLayout.revealedOffset(for: model, screen: screen, options: options), 728)
    }
    func testFocusLeftRevealsFirstColumn() {
        var model = strip(3)
        model.scrollOffset = 700
        expectEqual(StripLayout.revealedOffset(for: model, screen: screen, options: options), 0)
    }
    func testAlwaysCenterCanAddLeadingSpace() {
        let value = StripLayout.revealedOffset(for: strip(1), screen: screen, options: LayoutOptions(centering: .always))
        expectEqual(value, -356)
    }
    func testOverflowCenterOnlyAppliesToOverflowingStrip() {
        let options = LayoutOptions(centering: .overflow)
        expectEqual(StripLayout.revealedOffset(for: strip(1), screen: screen, options: options), 0)
        expectEqual(StripLayout.revealedOffset(for: strip(3), screen: screen, options: options), -356)
    }
    func testExplicitCenterWorksWithoutOverflow() {
        expectEqual(StripLayout.revealedOffset(for: strip(1), screen: screen, options: options, forceCenter: true), -356)
    }
    func testWidthsCannotExceedViewportOrCollapse() {
        expectEqual(ColumnWidth.fraction(2).resolve(in: 1424), 1424)
        expectEqual(ColumnWidth.points(-100).resolve(in: 1424), Double(WindowDiscovery.smallestTile.width), "Never under the smallest tile")
        expectEqual(ColumnWidth.fraction(0.05).resolve(in: 1000), Double(WindowDiscovery.smallestTile.width))
        expectEqual(ColumnWidth.fraction(.nan).resolve(in: 1424), 712)
        expectEqual(ColumnWidth.points(600).resolve(in: 100), 100)
    }
    func testGapsCannotInvertContentRect() {
        let content = StripLayout.contentRect(screen: screen, options: LayoutOptions(gap: -1, edgeGap: 10000))
        expectGreater(content.width, 0)
        expectGreater(content.height, 0)
    }
    func testLeftParkingKeepsSixPointsVisible() {
        let result = StripLayout.parked(CGRect(x: -3000, y: 33, width: 712, height: 809), on: screen)
        expectEqual(result.maxX, 6)
        expectGreater(result.intersection(screen.frame).width, 0)
    }
    func testRightParkingKeepsSixPointsVisible() {
        let result = StripLayout.parked(CGRect(x: 3000, y: 33, width: 712, height: 809), on: screen)
        expectEqual(result.minX, 1434)
        expectEqual(result.intersection(screen.frame).width, 6)
    }
    func testSharedRightEdgeNeverEntersNeighbor() {
        var screen = screen
        let neighbor = CGRect(x: 1440, y: 0, width: 1920, height: 1080)
        screen.neighbors = [neighbor]
        let result = StripLayout.parked(CGRect(x: 3000, y: 33, width: 712, height: 809), on: screen)
        expectFalse(result.intersects(neighbor))
        expectEqual(result.maxX, screen.frame.maxX)
    }
    func testSharedLeftEdgeNeverEntersNeighbor() {
        var screen = screen
        let neighbor = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        screen.neighbors = [neighbor]
        let result = StripLayout.parked(CGRect(x: -3000, y: 33, width: 712, height: 809), on: screen)
        expectFalse(result.intersects(neighbor))
        expectEqual(result.minX, 0)
    }
    func testStackedDisplayParkingStaysVerticallyContained() {
        var screen = screen
        screen.neighbors = [CGRect(x: 0, y: -900, width: 1440, height: 900), CGRect(x: 0, y: 900, width: 1440, height: 900)]
        for y: CGFloat in [-2000, 3000] {
            let result = StripLayout.parked(CGRect(x: -2000, y: y, width: 600, height: 2000), on: screen)
            expectAtLeast(result.minY, screen.visibleFrame.minY)
            expectAtMost(result.maxY, screen.visibleFrame.maxY)
            expectFalse(screen.neighbors.contains { $0.intersects(result) })
        }
    }
    func testSecondaryCoordinateSystemSupportsNegativeOrigin() {
        let screen = ScreenGeometry(frame: CGRect(x: -1600, y: -700, width: 1600, height: 900),
                                    visibleFrame: CGRect(x: -1600, y: -675, width: 1600, height: 825))
        let frame = StripLayout.frames(for: strip(1), screen: screen, options: options).values.first!
        expectEqual(frame.minX, -1592)
        expectEqual(frame.minY, -667)
    }
    func testRestoreClampsAnOldFrameToCurrentVisibleDisplay() {
        let result = StripLayout.restored(CGRect(x: -2000, y: 3000, width: 5000, height: 4000), on: screen)
        expectEqual(result, screen.visibleFrame)
    }
    func testParkingAcrossRandomFramesKeepsWindowsReachableAndOutOfNeighbors() {
        var screen = screen
        screen.neighbors = [CGRect(x: 1440, y: 0, width: 1920, height: 1080)]
        for x in stride(from: -6000.0, through: 6000, by: 120) {
            for width in [160.0, 712, 1424, 2500] {
                let result = StripLayout.parked(CGRect(x: x, y: -100, width: width, height: 1000), on: screen)
                expectGreater(result.intersection(screen.frame).width, 0)
                expectFalse(result.intersects(screen.neighbors[0]))
                expectAtLeast(result.minY, screen.visibleFrame.minY)
                expectAtMost(result.maxY, screen.visibleFrame.maxY)
            }
        }
    }
}

final class StripTests {
    func testBackgroundInsertionPreservesFocusWidthsAndScroll() {
        var strip = Strip()
        let first = WindowID(), background = WindowID()
        strip.insert(first, foreground: true, width: .fraction(2.0 / 3))
        strip.scrollOffset = 123
        strip.insert(background, foreground: false)
        expectEqual(strip.focusedWindow, first)
        expectEqual(strip.scrollOffset, 123)
        expectEqual(strip.columns[0].width, .fraction(2.0 / 3))
        expectEqual(strip.columns[1].windows, [background])
    }
    func testNewWindowOpensRightOfFocusedColumn() {
        var strip = Strip()
        let a = WindowID(), b = WindowID(), c = WindowID()
        strip.insert(a, foreground: true)
        strip.insert(b, foreground: true)
        strip.perform(.focus(.first))
        strip.insert(c, foreground: true)
        expectEqual(strip.columns.flatMap(\.windows), [a, c, b])
    }
    func testDuplicateWindowsAreIgnored() {
        var strip = Strip()
        let id = WindowID()
        strip.insert(id, foreground: true)
        strip.insert(id, foreground: true)
        expectEqual(strip.columns.count, 1)
    }
    func testMovePreservesFocusedWindowAndWidths() {
        var strip = Strip()
        let a = WindowID(), b = WindowID()
        strip.insert(a, foreground: true, width: .fraction(1.0 / 3))
        strip.insert(b, foreground: true, width: .fraction(2.0 / 3))
        strip.perform(.move(-1))
        expectEqual(strip.focusedWindow, b)
        expectEqual(strip.columns[0].windows, [b])
        expectEqual(strip.columns[0].width, .fraction(2.0 / 3))
        strip.perform(.move(-1))
        expectEqual(strip.columns[0].windows, [b])
    }
    func testFocusClampsAndMissingSlotDoesNothing() {
        var strip = Strip()
        let id = WindowID()
        strip.insert(id, foreground: true)
        for action: StripAction in [.focus(.left), .focus(.right), .focus(.slot(8)), .move(1)] {
            strip.perform(action)
            expectEqual(strip.focusedWindow, id)
        }
    }
    func testWidthPresetCycle() {
        var strip = Strip()
        strip.insert(WindowID(), foreground: true, width: .fraction(1.0 / 3))
        // A lone automatic column is shown full width, so the cycle continues from Full.
        for expected in [1.0 / 3, 0.5, 2.0 / 3, 1.0] {
            strip.perform(.nextWidth)
            expectEqual(strip.columns[0].width, .fraction(expected))
        }
    }
    func testRemoveFocusedWindowSelectsNearestRemainingColumn() {
        var strip = Strip()
        let a = WindowID(), b = WindowID(), c = WindowID()
        for id in [a, b, c] { strip.insert(id, foreground: true) }
        strip.remove(c)
        expectEqual(strip.focusedWindow, b)
        strip.remove(b)
        expectEqual(strip.focusedWindow, a)
        strip.remove(a)
        expectNil(strip.focusedWindow)
        expect(strip.columns.isEmpty)
    }
    func testFloatingClassification() {
        expect(WindowTraits().isTileable)
        expectFalse(WindowTraits(isStandard: false).isTileable)
        expectFalse(WindowTraits(canResize: false).isTileable)
        expectFalse(WindowTraits(canMove: false).isTileable)
        expectFalse(WindowTraits(isMinimized: true).isTileable)
        expectFalse(WindowTraits(isFullscreen: true).isTileable)
        expectFalse(WindowTraits(isOwnWindow: true).isTileable)
        expectFalse(WindowTraits(hasSheet: true).isTileable)
        expectFalse(WindowTraits(isFixedSizeApp: true).isTileable)
        expectFalse(WindowTraits(isModal: true).isTileable)
        expectFalse(WindowTraits(isTooSmall: true).isTileable)
        expect(WindowTraits(isTooSmall: true).isTileableAtAnySize, "Size alone is what a tiled window may break")
        expectFalse(WindowTraits(isModal: true, isTooSmall: true).isTileableAtAnySize)
        expect(WindowSnapshot(id: WindowID(), frame: .zero, processID: 0, isTileable: false, isTileableAtAnySize: true).tiledAtAnySize().isTileable)
        expectFalse(WindowSnapshot(id: WindowID(), frame: .zero, processID: 0, isTileable: false).tiledAtAnySize().isTileable)
        // No subrole counts only with a title bar's button; a standard window always does.
        expect(WindowDiscovery.isNormalWindow(role: kAXWindowRole as String, subrole: nil, hasTitleBarButton: true))
        expectFalse(WindowDiscovery.isNormalWindow(role: kAXWindowRole as String, subrole: nil, hasTitleBarButton: false))
        expect(WindowDiscovery.isNormalWindow(role: kAXWindowRole as String, subrole: kAXStandardWindowSubrole as String, hasTitleBarButton: false))
        expectFalse(WindowDiscovery.isNormalWindow(role: kAXWindowRole as String, subrole: kAXDialogSubrole as String))
        expect(WindowDiscovery.isTooSmall(CGSize(width: 200, height: 400)))
        expectFalse(WindowDiscovery.isTooSmall(CGSize(width: 800, height: 600)))
    }
}

final class InteractionTests {
    func testCompactKeyboardEndShortcutsKeepExistingBindings() {
        let first = HotKeyBinding.defaults.filter { $0.action == .strip(.first) }
        let last = HotKeyBinding.defaults.filter { $0.action == .strip(.last) }
        expectEqual(Set(first.map(\.keyCode)), Set([UInt32(kVK_Home), UInt32(kVK_ANSI_LeftBracket)]))
        expectEqual(Set(last.map(\.keyCode)), Set([UInt32(kVK_End), UInt32(kVK_ANSI_RightBracket)]))
        let signatures = HotKeyBinding.defaults.map { "\($0.keyCode):\($0.modifiers)" }
        expectEqual(Set(signatures).count, signatures.count, "Default commands must not compete for a binding")
    }
    func testResizeHappensOnceWhileTheWindowSlides() {
        let from = CGRect(x: 0, y: 20, width: 900, height: 700)
        let to = CGRect(x: 450, y: 20, width: 450, height: 700)
        let frames = (0...60).map { FrameMotion.interpolate(from: from, to: to, progress: Double($0) / 60) }
        expectEqual(frames.first?.minX, from.minX)
        expectEqual(frames.last, to)
        expect(frames.allSatisfy { $0.size == to.size })
        expectFalse(FrameMotion.needsResize(from: frames[0], to: frames[1]))
        expect(FrameMotion.needsMove(from: frames[0], to: frames[1]))
        expect(FrameMotion.needsResize(from: from, to: frames[0]))
    }
    func testStaleFocusDoesNotUndoRapidKeyboardNavigation() {
        let ids = (0..<3).map { _ in WindowID() }
        var intent = FocusIntent()
        intent.request(ids[1], now: 0)
        intent.request(ids[2], now: 0.1)
        expectEqual(intent.resolve(observed: ids[0], available: Set(ids), now: 0.2), ids[2])
        expectEqual(intent.resolve(observed: ids[1], available: Set(ids), now: 0.3), ids[2])
        expectEqual(intent.resolve(observed: ids[2], available: Set(ids), now: 0.4), ids[2])
        expectEqual(intent.resolve(observed: ids[0], available: Set(ids), now: 0.5), ids[0])
    }
    func testFocusIntentExpiresOrReleasesAClosedWindow() {
        let a = WindowID(), b = WindowID()
        var intent = FocusIntent()
        intent.request(b, now: 0)
        expectEqual(intent.resolve(observed: a, available: [a, b], now: 1), a)
        intent.request(b, now: 2)
        expectEqual(intent.resolve(observed: a, available: [a], now: 2.1), a)
    }
    func testAppChoicesWorkInBothModesAndPersist() throws {
        var policy = AppPolicy()
        expect(policy.manages("browser"))
        policy.setManaged(false, bundleID: "browser")
        expectFalse(policy.manages("browser"))
        expect(policy.manages("notes"))
        policy.setManaged(true, bundleID: "notes")
        policy.manageAll = false
        expect(policy.manages("notes"))
        expectFalse(policy.manages("new-app"))
        expectFalse(policy.manages(nil))
        let copy = try JSONDecoder().decode(AppPolicy.self, from: JSONEncoder().encode(policy))
        expectEqual(copy, policy)
    }
    func testExplicitWidthPreservesOtherColumns() {
        let a = WindowID(), b = WindowID()
        var strip = Strip(); strip.insert(a, foreground: true); strip.insert(b, foreground: false)
        strip.perform(.setWidth(2.0 / 3))
        expectEqual(strip.columns[0].width, .fraction(2.0 / 3))
        expectEqual(strip.columns[1].width, .fraction(0.5))
        strip.perform(.setWidth(.nan))
        expectEqual(strip.columns[0].width, .fraction(2.0 / 3))
    }
}

final class DiscoveryTests {
    func testMenuBarAppsWithNormalWindowsAreDiscoverable() {
        expect(WindowDiscovery.includesApp(policy: .regular, isOwnApp: false))
        expect(WindowDiscovery.includesApp(policy: .accessory, isOwnApp: false))
        expectFalse(WindowDiscovery.includesApp(policy: .prohibited, isOwnApp: false))
        expectFalse(WindowDiscovery.includesApp(policy: .accessory, isOwnApp: true))
    }
    func testNormalCustomWindowsRemainEligibleWhileDialogsStayFloating() {
        for subrole in [nil, kAXUnknownSubrole as String, kAXStandardWindowSubrole as String] {
            let normal = WindowDiscovery.isNormalWindow(role: kAXWindowRole as String, subrole: subrole)
            expect(normal)
            expect(WindowTraits(isStandard: normal, canMove: true, canResize: true).isTileable)
            expectFalse(WindowTraits(isStandard: normal, canMove: true, canResize: false).isTileable)
        }
        for subrole in [kAXDialogSubrole, kAXSystemDialogSubrole, kAXFloatingWindowSubrole] {
            expectFalse(WindowDiscovery.isNormalWindow(role: kAXWindowRole as String, subrole: subrole as String))
        }
        expectFalse(WindowDiscovery.isNormalWindow(role: kAXSheetRole as String, subrole: nil))
    }
    func testIndependentFrameReadsAllowSmallDriftWithoutMatchingOtherWindows() {
        let frame = CGRect(x: 100, y: 60, width: 700, height: 800)
        expect(WindowDiscovery.visibleMatch(frame, frame.offsetBy(dx: 4, dy: 4)))
        expectFalse(WindowDiscovery.visibleMatch(frame, frame.offsetBy(dx: 40, dy: 0)))
        expectFalse(WindowDiscovery.visibleMatch(frame, CGRect(x: 100, y: 60, width: 200, height: 100)))
    }
    func testCenteredEdgeDoesNotJumpOnFirstScrollPixel() {
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
        let options = LayoutOptions(centering: .always)
        var strip = Strip()
        for _ in 0..<3 { strip.insert(WindowID(), foreground: false) }
        strip.focusedWindow = strip.columns[0].windows[0]
        strip.scrollOffset = StripLayout.revealedOffset(for: strip, screen: screen, options: options)
        let start = strip.scrollOffset
        expectLess(start, 0)
        expectEqual(StripLayout.scrolledOffset(for: strip, by: 1, screen: screen, options: options), start + 1)
        expectEqual(StripLayout.scrolledOffset(for: strip, by: -1, screen: screen, options: options), start)
    }
}

final class FocusReadTests {
    func testNewestNotificationSupersedesQueuedAndInFlightReads() {
        var gate = FocusReadGate()
        let old = gate.request(command: 1)
        let newest = gate.request(command: 1)
        expectFalse(gate.accepts(old, command: 1))
        expect(gate.accepts(newest, command: 1))
    }
    func testKeyboardCommandInvalidatesEarlierRead() {
        var gate = FocusReadGate()
        let read = gate.request(command: 1)
        expectFalse(gate.accepts(read, command: 2))
        let afterCommand = gate.request(command: 2)
        expect(gate.accepts(afterCommand, command: 2))
        expectFalse(gate.accepts(afterCommand, command: 3))
    }
}

final class TestFrameClock: FrameClocking {
    var tick: (() -> Void)?
    @discardableResult func start(screen: NSScreen?, tick: @escaping () -> Void) -> Bool { self.tick = tick; return true }
    func stop() { tick = nil }
}

final class ScrollingTests {
    func testGestureKeepsMomentumAfterReleasingModifiers() {
        var g = ScrollGesture()
        expect(g.consume(x: 20, y: 1, precise: true, modifiers: true, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 1))
        expect(g.consume(x: 8, y: 1, precise: true, modifiers: false, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: false, now: 1.5))
        expect(g.consume(x: 0, y: 0, precise: true, modifiers: false, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: true, now: 1.6))
        expectFalse(g.consume(x: 12, y: 1, precise: true, modifiers: false, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 1.7))
    }
    func testKeyboardSelectionSwallowsRemainingMomentumUntilTheNextGesture() {
        var g = ScrollGesture()
        g.suppress()
        expectFalse(g.isSuppressed, "Nothing to suppress without an owned gesture")
        expect(g.consume(x: 20, y: 1, precise: true, modifiers: true, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 1))
        g.suppress()
        expect(g.consume(x: 8, y: 0, precise: true, modifiers: false, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: false, now: 1.1), "Momentum still must not leak into the app")
        expect(g.isSuppressed)
        expect(g.consume(x: 0, y: 0, precise: true, modifiers: false, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: true, now: 1.2))
        expect(g.consume(x: 15, y: 0, precise: true, modifiers: true, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 2))
        expectFalse(g.isSuppressed, "A new gesture browses again")
    }
    func testOrdinaryVerticalAndMouseWheelScrollingPassThrough() {
        for (x, y, precise, mods) in [(10.0, 0.0, true, false), (1, 20, true, true), (10, 0, false, true)] {
            var g = ScrollGesture()
            expectFalse(g.consume(x: x, y: y, precise: precise, modifiers: mods, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 1))
        }
    }
    func testCannotCaptureMiddleOfAnOrdinaryGestureOrOrphanMomentum() {
        var g = ScrollGesture()
        expectFalse(g.consume(x: 0, y: 10, precise: true, modifiers: false, eligible: true, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 1))
        expectFalse(g.consume(x: 20, y: 0, precise: true, modifiers: true, eligible: true, begins: false, momentum: false, cancelled: false, finishesMomentum: false, now: 1.1))
        g.reset()
        expectFalse(g.consume(x: 20, y: 0, precise: true, modifiers: true, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: false, now: 2))
    }
    func testCancellationAndIneligibleDisplayReleaseGesture() {
        var g = ScrollGesture()
        expect(g.consume(x: 20, y: 0, precise: true, modifiers: true, eligible: true, begins: true, momentum: false, cancelled: true, finishesMomentum: false, now: 1))
        expectFalse(g.consume(x: 10, y: 0, precise: true, modifiers: false, eligible: true, begins: false, momentum: true, cancelled: false, finishesMomentum: false, now: 1.1))
        expectFalse(g.consume(x: 20, y: 0, precise: true, modifiers: true, eligible: false, begins: true, momentum: false, cancelled: false, finishesMomentum: false, now: 2))
    }
    func testScrollBoundsPreserveFocusAndWidths() {
        var strip = Strip()
        for _ in 0..<8 { strip.insert(WindowID(), foreground: false) }
        strip.focusedWindow = strip.columns[0].windows[0]
        let focus = strip.focusedWindow, columns = strip.columns
        let geometry = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
        let options = LayoutOptions()
        strip.scrollOffset = StripLayout.scrolledOffset(for: strip, by: 100_000, screen: geometry, options: options)
        expectGreater(strip.scrollOffset, 0)
        let last = StripLayout.columnRects(for: strip, screen: geometry, options: options).last!
        expectEqual(last.maxX, StripLayout.contentRect(screen: geometry, options: options).maxX, accuracy: 0.001)
        strip.scrollOffset = StripLayout.scrolledOffset(for: strip, by: -100_000, screen: geometry, options: options)
        expectEqual(strip.scrollOffset, 0)
        expectEqual(strip.focusedWindow, focus)
        expectEqual(strip.columns, columns)
        expectEqual(StripLayout.scrolledOffset(for: strip, by: .nan, screen: geometry, options: options), 0)
    }
    @MainActor func testDisplayTicksDoNotSkipHighRefreshFramesAndRetargetDoesNotRestartFullDuration() {
        let clock = TestFrameClock()
        var now = 0.0
        let animator = Animator(clock: clock, now: { now }, systemReduceMotion: { false })
        let id = WindowID(), origin = CGRect(x: 0, y: 30, width: 300, height: 600)
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
        var writes = 0, completed = 0
        animator.animate(to: [id: origin.offsetBy(dx: 400, dy: 0)], from: [id: origin], screen: nil, geometry: screen, reduceMotion: false, write: { _ in writes += 1 }, completion: { completed += 1 })
        // The system preference is injected, so every pacing assertion runs.
        if animator.isAnimating {
            let count = writes
            for i in 1...4 { now = Double(i) / 120; clock.tick?() }
            expectEqual(writes, count + 4)
            now = 0.04
            animator.animate(to: [id: origin.offsetBy(dx: 800, dy: 0)], from: [:], screen: nil, geometry: screen, reduceMotion: false, write: { _ in writes += 1 }, completion: { completed += 1 })
            now = Animator.slide + 0.001; clock.tick?()
            expectFalse(animator.isAnimating)
            expectEqual(completed, 1)
            expectEqual(animator.current[id], origin.offsetBy(dx: 800, dy: 0))
        }
    }
    func testSlowAppDoesNotBlockOtherAppAndPendingFramesCoalesce() {
        let a = WindowID(), b = WindowID()
        let started = expectation(description: "slow app started"), fast = expectation(description: "other app wrote"), latest = expectation(description: "latest pending frame wrote")
        let release = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var values: [Double] = []
        let queue = FrameWriteQueue { job in
            if job.id == a {
                lock.lock(); values.append(job.frame.minX); lock.unlock()
                if job.frame.minX == 0 { started.fulfill(); _ = release.wait(timeout: .now() + 2) }
                if job.frame.minX == 100 { latest.fulfill() }
            } else { fast.fulfill() }
        }
        func job(_ id: WindowID, _ x: Double) -> FrameWrite { FrameWrite(id: id, frame: CGRect(x: x, y: 0, width: 300, height: 500), generation: 0) }
        queue.enqueue([(1, job(a, 0))])
        wait(for: [started], timeout: 1)
        for i in 1...100 { queue.enqueue([(1, job(a, Double(i)))]) }
        queue.enqueue([(2, job(b, 5))])
        wait(for: [fast], timeout: 1)
        release.signal()
        wait(for: [latest], timeout: 1)
        lock.lock(); let observed = values; lock.unlock()
        expectEqual(observed, [0, 100], "Intermediate queued frames must not replay")
    }
    func testReconciliationWaitsForInFlightAndNewestQueuedWrite() {
        let started = expectation(description: "first started"), settled = expectation(description: "all writes settled")
        let release = DispatchSemaphore(value: 0)
        let lock = NSLock()
        var values: [Double] = []
        let queue = FrameWriteQueue { job in
            if job.frame.minX == 0 { started.fulfill(); _ = release.wait(timeout: .now() + 2) }
            lock.lock(); values.append(job.frame.minX); lock.unlock()
        }
        let id = WindowID(), rect = CGRect(x: 0, y: 0, width: 300, height: 500)
        queue.enqueue([(1, FrameWrite(id: id, frame: rect, generation: 0))])
        wait(for: [started], timeout: 1)
        queue.enqueue([(1, FrameWrite(id: id, frame: rect.offsetBy(dx: 50, dy: 0), generation: 0))])
        queue.whenIdle {
            lock.lock(); let written = values; lock.unlock()
            expectEqual(written, [0, 50])
            settled.fulfill()
        }
        release.signal()
        wait(for: [settled], timeout: 1)
    }
    @MainActor func testUnavailableDisplayClockCompletesAnimation() {
        final class FailedClock: FrameClocking {
            func start(screen: NSScreen?, tick: @escaping () -> Void) -> Bool { false }
            func stop() {}
        }
        let animator = Animator(clock: FailedClock(), now: { 0 }, systemReduceMotion: { false })
        let id = WindowID(), rect = CGRect(x: 10, y: 30, width: 300, height: 500)
        let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
        var completed = false
        animator.animate(to: [id: rect], from: [id: rect.offsetBy(dx: 100, dy: 0)], screen: nil, geometry: screen, reduceMotion: false, write: { _ in }, completion: { completed = true })
        expect(completed)
        expectFalse(animator.isAnimating)
        expectEqual(animator.current[id], rect)
    }
    func testCancellingQueueDropsWaitingFrames() {
        let first = expectation(description: "first frame started"), done = expectation(description: "first frame finished")
        let release = DispatchSemaphore(value: 0), lock = NSLock()
        var writes = 0
        let queue = FrameWriteQueue { _ in
            lock.lock(); writes += 1; lock.unlock()
            first.fulfill(); _ = release.wait(timeout: .now() + 2); done.fulfill()
        }
        let id = WindowID(), rect = CGRect(x: 0, y: 0, width: 300, height: 500)
        queue.enqueue([(1, FrameWrite(id: id, frame: rect, generation: 0))])
        wait(for: [first], timeout: 1)
        queue.enqueue([(1, FrameWrite(id: id, frame: rect.offsetBy(dx: 10, dy: 0), generation: 0))])
        queue.cancelPending(); release.signal()
        wait(for: [done], timeout: 1)
        lock.lock(); let count = writes; lock.unlock()
        expectEqual(count, 1)
    }
}

final class FakeWindows: WindowServer {
    var onChange: (() -> Void)?
    var onStall: (() -> Void)?
    var onFocusChange: ((WindowID) -> Void)?
    var onDesktopChange: (() -> Void)?
    var onWindowRemoved: ((WindowID) -> Void)?
    var onWindowInteraction: ((WindowID, CGRect, WindowInteraction, Bool) -> Void)?
    var pointerPosition: CGPoint?
    var scanPolicies: [AppPolicy] = []
    var scans: [([WindowSnapshot], WindowID?) -> Void] = []
    /// What the next finished scan says each display shows; nil is a Mac without the private list.
    var spaces: [SpaceDisplay]?
    var writes: [[WindowID: CGRect]] = []
    var cancellations = 0
    var focused: [WindowID] = []
    var raised: [WindowID] = []
    var restored: [WindowID: CGRect] = [:]
    func start() {}
    func stop() {}
    func scan(policy: AppPolicy, completion: @escaping ([WindowSnapshot], WindowID?, [SpaceDisplay]?) -> Void) {
        scanPolicies.append(policy)
        scans.append { [weak self] windows, focused in completion(windows, focused, self?.spaces) }
    }
    func apply(frames: [WindowID: CGRect]) { writes.append(frames) }
    func cancelPendingWrites() { cancellations += 1 }
    func settle(completion: @escaping () -> Void) { completion() }
    func focus(_ id: WindowID, activate: Bool) { if activate { focused.append(id) } }
    func raise(_ ids: [WindowID], preservingFocus focused: WindowID?) { raised += ids.filter { $0 != focused }; if let focused { raised.append(focused) } }
    func restore(frames: [WindowID: CGRect], completion: @escaping () -> Void) { restored = frames; completion() }
}
final class FakeAnimator: WindowAnimator {
    var current: [WindowID: CGRect] = [:]
    var isAnimating = false
    var holdsAnimation = false
    var animations: [[WindowID: CGRect]] = []
    var starts: [[WindowID: CGRect]] = []
    func cancel() { current.removeAll(); isAnimating = false }
    func animate(to frames: [WindowID: CGRect], from initial: [WindowID: CGRect], screen: NSScreen?, geometry: ScreenGeometry, reduceMotion: Bool, write: @escaping ([WindowID: CGRect]) -> Void, completion: @escaping () -> Void) {
        animations.append(frames); starts.append(initial)
        if holdsAnimation { isAnimating = true } else { current = frames; write(frames); completion() }
    }
}
final class ControllerTests {
    @MainActor func testStartupOrderAndRapidFocusAreStable() async {
        let defaults = freshDefaults()
        let server = FakeWindows()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        let windows = snapshots()
        controller.resume(); await yieldToMain()
        expectFalse(server.scans.isEmpty)
        server.scans.removeFirst()(windows, windows[0].id)
        expectEqual(controller.windowChoices.map(\.id), windows.map(\.id))
        controller.perform(.strip(.right)); controller.perform(.strip(.right))
        expectEqual(server.focused, [windows[1].id, windows[2].id])
        server.onFocusChange?(windows[0].id)
        expectEqual(controller.windowChoices.first(where: \.selected)?.id, windows[2].id)
        controller.pause()
        expectEqual(server.restored, Dictionary(uniqueKeysWithValues: windows.map { ($0.id, $0.frame) }))
    }
    @MainActor func testExcludingAnAppRestoresItAndStopsManagingIt() async {
        let defaults = freshDefaults()
        let settings = TapeSettings(defaults: defaults), server = FakeWindows(), windows = snapshots()
        let controller = TapeController(settings: settings, server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain()
        expectFalse(server.scans.isEmpty)
        server.scans.removeFirst()(windows, windows[0].id)
        settings.appPolicy.setManaged(false, bundleID: "app.1")
        await yieldToMain()
        expectFalse(controller.windowChoices.map(\.id).contains(windows[1].id))
        expect(server.writes.contains { $0[windows[1].id] == windows[1].frame })
        controller.pause()
        expectNil(server.restored[windows[1].id], "Pause must leave the deselected app alone")
    }
    @MainActor func testOldScanCannotUndoAKeyboardAction() async {
        let defaults = freshDefaults()
        let server = FakeWindows(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        await yieldToMain()
        guard !server.scans.isEmpty else { return fail("Expected reconciliation scan") }
        let old = server.scans.removeFirst()
        controller.perform(.strip(.right))
        old(windows, windows[0].id)
        expectEqual(controller.windowChoices.first(where: \.selected)?.id, windows[1].id)
        controller.pause()
    }
    @MainActor func testOnlySelectedAppsReachTheWindowScan() async {
        let defaults = freshDefaults()
        let settings = TapeSettings(defaults: defaults)
        settings.appPolicy.manageAll = false
        settings.appPolicy.setManaged(true, bundleID: "app.1")
        let server = FakeWindows(), windows = snapshots()
        let controller = TapeController(settings: settings, server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain()
        expectEqual(server.scanPolicies.last, settings.appPolicy)
        server.scans.removeFirst()(windows, windows[1].id)
        expectEqual(controller.windowChoices.map(\.id), [windows[1].id])
        controller.pause()
        expectEqual(server.restored, [windows[1].id: windows[1].frame])
    }
    @MainActor func testManualMoveIsCorrectedEvenWhenTargetsAreUnchanged() async {
        let defaults = freshDefaults()
        let server = FakeWindows(), animator = FakeAnimator(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        await yieldToMain()
        expectFalse(server.scans.isEmpty)
        let target = animator.current
        let displaced = windows.map { window -> WindowSnapshot in
            var frame = target[window.id]!
            frame.origin.y += 40
            return WindowSnapshot(id: window.id, frame: frame, processID: window.processID, isTileable: true, bundleIdentifier: window.bundleIdentifier)
        }
        let count = animator.animations.count
        server.scans.removeFirst()(displaced, windows[0].id)
        expectEqual(animator.animations.count, count + 1)
        expectEqual(animator.current, target)
        controller.pause()
    }
    @MainActor func testRejectedFramesDoNotStartAnEndlessCorrectionLoop() async {
        let defaults = freshDefaults()
        let server = FakeWindows(), animator = FakeAnimator(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        await yieldToMain()
        let count = animator.animations.count
        // The app reports exactly the same frame after declining the first write.
        server.scans.removeFirst()(windows, windows[0].id)
        expectEqual(animator.animations.count, count)
        await yieldToMain()
        expect(server.scans.isEmpty)
        controller.pause()
    }
    @MainActor func testReversalUsesCurrentAnimationPosition() async {
        let defaults = freshDefaults()
        let server = FakeWindows(), animator = FakeAnimator(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        await yieldToMain()
        let settled = windows.map { window in
            WindowSnapshot(id: window.id, frame: animator.current[window.id]!, processID: window.processID, isTileable: true, bundleIdentifier: window.bundleIdentifier)
        }
        server.scans.removeFirst()(settled, windows[0].id)
        animator.holdsAnimation = true
        controller.setWidth(0.75)
        let wide = animator.animations.last!
        animator.current = wide
        let count = animator.animations.count
        controller.setWidth(0.5)
        expectEqual(animator.animations.count, count + 1, "Returning to the scanned width must interrupt motion")
        expectEqual(animator.starts.last, wide)
        // Even if the new target happens to equal the current step, stop the old motion.
        animator.current = wide
        let reversedCount = animator.animations.count
        controller.setWidth(0.75)
        expectEqual(animator.animations.count, reversedCount + 1)
        controller.pause()
    }
    @MainActor func testPreviousRunScanCannotReleaseCurrentScan() async {
        let defaults = freshDefaults()
        let server = FakeWindows(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: FakeAnimator(), permissionCheck: { true }, registerShortcuts: false, geometry: geometry, log: { _ in })
        controller.resume(); await yieldToMain()
        let previousRun = server.scans.removeFirst()
        controller.pause(); controller.resume(); await yieldToMain()
        expectEqual(server.scans.count, 1)
        previousRun(windows, windows[0].id)
        server.onChange?(); await yieldToMain()
        expectEqual(server.scans.count, 1, "A stale callback must not allow overlapping scans")
        server.scans.removeFirst()(windows, windows[0].id)
        expectEqual(controller.managedCount, 3)
        controller.pause()
    }
    @MainActor func testScrollingCoalescesAtDisplayRefreshWithoutActivatingApps() async {
        let defaults = freshDefaults()
        let server = FakeWindows(), animator = FakeAnimator(), clock = TestFrameClock(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, scrollClock: clock, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        let selected = controller.windowChoices.first(where: \.selected)?.id
        let writes = server.writes.count, animations = animator.animations.count
        for _ in 0..<10 { controller.scroll(by: 10) }
        expectEqual(server.writes.count, writes, "Input should accumulate until display refresh")
        clock.tick?()
        expectEqual(server.writes.count, writes + 1)
        expectEqual(animator.animations.count, animations, "No easing animation for each scroll event")
        expect(server.focused.isEmpty, "Browsing must never activate an app")
        expectEqual(controller.windowChoices.first(where: \.selected)?.id, selected)
        let before = server.writes.last!
        controller.scroll(by: 50); clock.tick?()
        expectLess(server.writes.last![windows[0].id]!.minX, before[windows[0].id]!.minX)
        let browsed = server.writes.last!
        controller.perform(.strip(.right))
        controller.perform(.strip(.right)) // The third column needs a viewport move.
        expectEqual(animator.starts.last, browsed, "Keyboard navigation starts from the browsed positions")
        expectEqual(server.focused, [windows[1].id, windows[2].id])
        expectNil(clock.tick)
        controller.scroll(by: 20) // Pause must discard this unflushed step.
        let writesBeforePause = server.writes.count
        controller.pause()
        expectEqual(server.writes.count, writesBeforePause)
        let pausedWrites = server.writes.count
        controller.scroll(by: 20); clock.tick?()
        expectEqual(server.writes.count, pausedWrites)
        expectNil(clock.tick)
    }
    @MainActor func testAppMinimumWidthIsLearnedAfterTrackpadBrowsing() async {
        let defaults = freshDefaults()
        let server = FakeWindows(), animator = FakeAnimator(), clock = TestFrameClock(), windows = snapshots()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: geometry, scrollClock: clock, log: { _ in })
        controller.resume(); await yieldToMain(); server.scans.removeFirst()(windows, windows[0].id)
        controller.setWidth(1.0 / 3)
        controller.scroll(by: 20); clock.tick?()
        expect(animator.current.isEmpty)
        await yieldToMain(); await yieldToMain(); await yieldToMain()
        guard !server.scans.isEmpty else { return fail("Expected post-scroll reconciliation") }
        let requested = server.writes.last!
        let actual = windows.map { window -> WindowSnapshot in
            var frame = requested[window.id]!
            if window.id == windows[0].id { frame.size.width = 900 }
            return WindowSnapshot(id: window.id, frame: frame, processID: window.processID, isTileable: true, bundleIdentifier: window.bundleIdentifier)
        }
        server.scans.removeLast()(actual, windows[0].id)
        expectEqual(animator.current[windows[0].id]?.width, 900)
        controller.pause()
    }
    private var geometry: ScreenGeometry { ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900)) }
    private func snapshots() -> [WindowSnapshot] {
        (0..<3).map { WindowSnapshot(id: WindowID(), frame: CGRect(x: 30 + $0 * 450, y: 50, width: 400, height: 700), processID: 0, isTileable: true, bundleIdentifier: "app.\($0)") }
    }
    @MainActor private func yieldToMain() async { try? await Task.sleep(nanoseconds: 100_000_000) }
}

final class DisplayTests {
    private var a: TapeDisplay {
        TapeDisplay(
            id: "a", name: "Built-in",
            geometry: ScreenGeometry(
                frame: CGRect(x: 0, y: 0, width: 1600, height: 1000),
                visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900)))
    }
    private var b: TapeDisplay {
        TapeDisplay(
            id: "b", name: "External",
            geometry: ScreenGeometry(
                frame: CGRect(x: 1600, y: 0, width: 1600, height: 1000),
                visibleFrame: CGRect(x: 1600, y: 30, width: 1600, height: 900)))
    }
    private func windows(on display: TapeDisplay, count: Int = 3) -> [WindowSnapshot] {
        (0..<count).map {
            WindowSnapshot(
                id: WindowID(),
                frame: CGRect(
                    x: display.geometry.frame.minX + 30 + Double($0) * 450, y: 50, width: 400, height: 700),
                processID: 0, isTileable: true, bundleIdentifier: "fixture")
        }
    }
    @MainActor private func pauseForScan() async { try? await Task.sleep(nanoseconds: 300_000_000) }
    private func observed(_ windows: [WindowSnapshot], server: FakeWindows) -> [WindowSnapshot] {
        var frames: [WindowID: CGRect] = [:]
        for write in server.writes { frames.merge(write) { _, last in last } }
        return windows.map {
            WindowSnapshot(
                id: $0.id, frame: frames[$0.id] ?? $0.frame, processID: $0.processID,
                isTileable: $0.isTileable, bundleIdentifier: $0.bundleIdentifier)
        }
    }
    private func completeLatest(_ server: FakeWindows, windows: [WindowSnapshot], focus: WindowID?) {
        guard let completion = server.scans.last else { return fail("Expected a scan") }
        server.scans.removeAll()
        completion(windows, focus)
    }

    func testOwnershipUsesAreaAndKeepsStableBoundaryTies() {
        let boundary = CGRect(x: 1400, y: 50, width: 400, height: 600)
        expectEqual(DisplayLayout.owner(of: boundary, in: [a, b], previous: "b"), "b")
        expectEqual(
            DisplayLayout.owner(of: boundary.offsetBy(dx: 1, dy: 0), in: [a, b], previous: "a"), "b")
        expectEqual(
            DisplayLayout.owner(of: boundary.offsetBy(dx: -1, dy: 0), in: [a, b], previous: "b"), "a")
        expectEqual(DisplayLayout.at(CGPoint(x: 1800, y: 100), in: [a, b]), "b")
    }
    func testNegativeAndStackedDisplaysAndDisconnectedFallback() {
        let left = TapeDisplay(
            id: "left", name: "Left",
            geometry: ScreenGeometry(
                frame: CGRect(x: -1600, y: 0, width: 1600, height: 1000),
                visibleFrame: CGRect(x: -1600, y: 30, width: 1600, height: 900)))
        let top = TapeDisplay(
            id: "top", name: "Top",
            geometry: ScreenGeometry(
                frame: CGRect(x: 0, y: -1000, width: 1600, height: 1000),
                visibleFrame: CGRect(x: 0, y: -970, width: 1600, height: 900)))
        expectEqual(
            DisplayLayout.owner(of: CGRect(x: -1400, y: 100, width: 500, height: 600), in: [a, left, top]),
            "left")
        expectEqual(
            DisplayLayout.owner(of: CGRect(x: 100, y: -900, width: 500, height: 600), in: [a, left, top]),
            "top")
        expectEqual(
            DisplayLayout.owner(of: CGRect(x: 1900, y: 100, width: 500, height: 600), in: [a]), "a")
        let geometry = DisplayLayout.geometry(for: a, in: [a, left, top])
        expectEqual(geometry.neighbors.count, 2)
        expectNil(DisplayLayout.owner(of: .zero, in: []))
    }
    func testNextDisplaySkipsDisabledAndRequiresAnotherDestination() {
        let c = TapeDisplay(id: "c", name: "Third", geometry: b.geometry)
        expectEqual(DisplayLayout.next(after: "a", in: [a, b, c], excluding: ["b"]), "c")
        expectEqual(DisplayLayout.next(after: "c", in: [a, b, c], excluding: ["b"]), "a")
        expectNil(DisplayLayout.next(after: "a", in: [a, b], excluding: ["b"]))
    }
    func testRemovingTailWindowsCannotLeaveTheViewportPastTheStrip() {
        var strip = Strip()
        for _ in 0..<10 { strip.insert(WindowID(), foreground: false) }
        strip.focusedWindow = strip.columns[0].windows[0]
        strip.scrollOffset = StripLayout.scrolledOffset(
            for: strip, by: 100_000, screen: a.geometry, options: LayoutOptions())
        while strip.columns.count > 2 { strip.remove(strip.columns.last!.windows[0]) }
        let offset = StripLayout.constrainedOffset(for: strip, screen: a.geometry, options: LayoutOptions())
        strip.scrollOffset = offset
        expect(
            StripLayout.columnRects(for: strip, screen: a.geometry, options: LayoutOptions()).contains {
                a.geometry.visibleFrame.intersection($0).width > 300
            })
    }
    @MainActor func testMirroringCreatesOneDrawableStrip() {
        let defaults = freshDefaults()
        let mirror = TapeDisplay(id: "mirror", name: "Mirror", geometry: a.geometry)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: FakeWindows(), animator: FakeAnimator(),
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, mirror],
            animatorFactory: { FakeAnimator() }, clockFactory: { TestFrameClock() })
        expectEqual(controller.displayChoices.map(\.id), ["a"])
        expectFalse(controller.canSendToDisplay)
    }
    @MainActor func testTwoDisplaysHaveIndependentWritesAndBrowsingDoesNotMoveFocus() async {
        let defaults = freshDefaults()
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let ca = TestFrameClock()
        let cb = TestFrameClock()
        let wa = windows(on: a)
        let wb = windows(on: b)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, scrollClock: ca, log: { _ in },
            displays: [a, b], animatorFactory: { ab }, clockFactory: { cb })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        expectEqual(controller.managedCount, 6)
        expectEqual(controller.displayChoices.map(\.windowCount), [3, 3])
        expectEqual(Set(aa.current.keys), Set(wa.map(\.id)))
        expectEqual(Set(ab.current.keys), Set(wb.map(\.id)))
        expect(aa.current.values.allSatisfy { a.geometry.frame.contains($0) })
        expect(
            ab.current.values.allSatisfy {
                b.geometry.frame.intersects($0) && !a.geometry.frame.intersects($0)
            })
        let beforeA = aa.current
        controller.scroll(by: 150, at: CGPoint(x: 1800, y: 100))
        cb.tick?()
        expectEqual(Set(server.writes.last!.keys), Set(wb.map(\.id)))
        expectEqual(aa.current, beforeA)
        expect(server.focused.isEmpty)
        expectEqual(controller.windowChoices.first(where: \.selected)?.id, wa[0].id)
        controller.perform(.strip(.right))
        expectEqual(
            server.focused, [wa[1].id], "Keyboard focus stays on its display while another display is browsed"
        )
        controller.pause()
        expectEqual(server.restored, Dictionary(uniqueKeysWithValues: (wa + wb).map { ($0.id, $0.frame) }))
    }
    @MainActor func testTransferKeepsWidthAndPauseRestoresOriginalDisplay() async {
        let defaults = freshDefaults()
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a, count: 2)
        let wb = windows(on: b, count: 1)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        controller.setWidth(2.0 / 3)
        let width = aa.current[wa[0].id]!.width
        controller.perform(.nextDisplay)
        expectEqual(controller.displayChoices.map(\.windowCount), [1, 2])
        expectEqual(ab.current[wa[0].id]!.width, width)
        expect(b.geometry.frame.contains(ab.current[wa[0].id]!))
        expectEqual(controller.windowChoices.first(where: \.selected)?.id, wa[0].id)
        controller.pause()
        expectEqual(server.restored[wa[0].id], wa[0].frame)
    }
    @MainActor func testDisableRestoreReenableAndPauseLeaveExcludedDisplayAlone() async {
        let defaults = freshDefaults()
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a)
        let wb = windows(on: b)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        controller.setDisplayEnabled("b", false)
        await pauseForScan()
        expectEqual(controller.managedCount, 3)
        expect(server.writes.contains { $0[wb[0].id] == wb[0].frame })
        let writes = server.writes.count
        controller.scroll(by: 100, at: CGPoint(x: 1800, y: 100))
        expectEqual(server.writes.count, writes)
        controller.pause()
        expect(wb.allSatisfy { server.restored[$0.id] == nil })
        controller.setDisplayEnabled("b", true)
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: observed(wa + wb, server: server), focus: wa[0].id)
        expectEqual(controller.displayChoices.map(\.windowCount), [3, 3])
        expectEqual(TapeSettings(defaults: defaults).disabledDisplays, [])
        controller.pause()
    }
    @MainActor func testUnplugPreservesWindowsWidthsAndReachableRestoration() async {
        let defaults = freshDefaults()
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a)
        let wb = windows(on: b)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        controller.chooseWindow(wb[0].id)
        controller.setWidth(2.0 / 3)
        let oldWidth = ab.current[wb[0].id]!.width
        let cancellationCount = server.cancellations
        controller.updateDisplays([a])
        await pauseForScan()
        expectGreater(
            server.cancellations, cancellationCount, "Obsolete queued geometry must be discarded on unplug")
        completeLatest(server, windows: observed(wa + wb, server: server), focus: wb[0].id)
        expectEqual(controller.managedCount, 6)
        expectEqual(aa.current[wb[0].id]!.width, oldWidth)
        expect(aa.current.values.allSatisfy { a.geometry.frame.intersection($0).width >= 5.99 })
        controller.pause()
        expectEqual(server.restored.count, 6)
        expect(server.restored.values.allSatisfy { a.geometry.visibleFrame.contains($0) })
    }
    @MainActor func testRearrangingDisplaysRestoresLocalWindowPositions() async {
        let defaults = freshDefaults()
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a, count: 1)
        let wb = windows(on: b, count: 1)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        let moved = TapeDisplay(
            id: "b", name: "External",
            geometry: ScreenGeometry(
                frame: CGRect(x: -1600, y: 0, width: 1600, height: 1000),
                visibleFrame: CGRect(x: -1600, y: 30, width: 1600, height: 900)))
        controller.updateDisplays([a, moved])
        await pauseForScan()
        let shifted = WindowSnapshot(
            id: wb[0].id, frame: wb[0].frame.offsetBy(dx: -3200, dy: 0), processID: 0, isTileable: true,
            bundleIdentifier: "fixture")
        completeLatest(server, windows: wa + [shifted], focus: wa[0].id)
        controller.pause()
        expectEqual(
            server.restored[wb[0].id], shifted.frame,
            "Restore the original local position on the same physical display")
        expectEqual(server.restored[wa[0].id], wa[0].frame)
    }
    @MainActor func testManualMoveBetweenDisplaysKeepsTheWindowPreset() async {
        let defaults = freshDefaults()
        let server = FakeWindows()
        let aa = FakeAnimator()
        let ab = FakeAnimator()
        let wa = windows(on: a)
        let wb = windows(on: b)
        let controller = TapeController(
            settings: TapeSettings(defaults: defaults), server: server, animator: aa,
            permissionCheck: { true }, registerShortcuts: false, log: { _ in }, displays: [a, b],
            animatorFactory: { ab }, clockFactory: { TestFrameClock() })
        controller.resume()
        await pauseForScan()
        completeLatest(server, windows: wa + wb, focus: wa[0].id)
        controller.setWidth(0.75)
        let width = aa.current[wa[0].id]!.width
        await pauseForScan()
        let next = observed(wa + wb, server: server).map { window -> WindowSnapshot in
            if window.id != wa[0].id { return window }
            return WindowSnapshot(
                id: window.id, frame: CGRect(x: 1800, y: 50, width: width, height: 700), processID: 0,
                isTileable: true, bundleIdentifier: "fixture")
        }
        completeLatest(server, windows: next, focus: wa[0].id)
        expectEqual(controller.displayChoices.map(\.windowCount), [2, 4])
        expectEqual(ab.current[wa[0].id]!.width, width)
        controller.pause()
    }
}

final class WindowInteractionTests {
    private let screen = ScreenGeometry(frame: CGRect(x: 0, y: 0, width: 1600, height: 1000), visibleFrame: CGRect(x: 0, y: 30, width: 1600, height: 900))
    private func windows(_ count: Int = 3) -> [WindowSnapshot] {
        (0..<count).map { WindowSnapshot(id: WindowID(), frame: CGRect(x: 40 + 400 * $0, y: 60, width: 380, height: 650), processID: 0, isTileable: true, bundleIdentifier: "fixture", title: "Document \($0)") }
    }
    @MainActor private func fixture() -> (TapeController, TapeSettings, FakeWindows, FakeAnimator) {
        let defaults = freshDefaults()
        let settings = TapeSettings(defaults: defaults), server = FakeWindows(), animator = FakeAnimator()
        let controller = TapeController(settings: settings, server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: screen, log: { _ in })
        return (controller, settings, server, animator)
    }
    @MainActor private func waitForScan() async { try? await Task.sleep(nanoseconds: 120_000_000) }
    @MainActor private func observed(_ windows: [WindowSnapshot], _ frames: [WindowID: CGRect]) -> [WindowSnapshot] {
        windows.map { WindowSnapshot(id: $0.id, frame: frames[$0.id] ?? $0.frame, processID: $0.processID, isTileable: true, bundleIdentifier: $0.bundleIdentifier, title: $0.title) }
    }

    @MainActor func testNativeTabAndFocusChangesKeepLoneWindowFullOrExplicitWidth() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows(1), id = list[0].id
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, id)
        expectEqual(animator.current[id]?.width, 1584)
        await waitForScan()
        server.scans.removeFirst()(observed(list, animator.current), id)
        expectEqual(animator.current[id]?.width, 1584)
        controller.setWidth(2.0 / 3)
        let explicit = animator.current[id]
        await waitForScan()
        server.scans.removeFirst()(observed(list, animator.current), id)
        expectEqual(animator.current[id], explicit)
    }
    @MainActor func testCloseRetargetsMotionImmediatelyAndDropsClosedWindow() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        animator.holdsAnimation = true
        controller.perform(.strip(.right))
        let moving = animator.current
        let count = animator.animations.count
        server.onWindowRemoved?(list[1].id)
        expectEqual(controller.managedCount, 2)
        expectEqual(animator.animations.count, count + 1)
        expectNil(animator.animations.last?[list[1].id])
        expectEqual(animator.starts.last?[list[0].id], moving[list[0].id])
        controller.pause()
        expectNil(server.restored[list[1].id])
    }
    @MainActor func testDragReordersOnlyOnReleaseAndScanDoesNotFightIt() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        var dragged = animator.current[list[2].id]!
        dragged.origin.x = 8
        let writes = server.writes.count
        server.onWindowInteraction?(list[2].id, dragged, .move, false)
        server.onChange?(); await waitForScan()
        expectEqual(server.writes.count, writes)
        expectEqual(controller.windowChoices.map(\.id), list.map(\.id))
        server.onWindowInteraction?(list[2].id, dragged, .move, true)
        expectEqual(controller.windowChoices.map(\.id), [list[2].id, list[0].id, list[1].id])
        expect(server.focused.isEmpty, "Dragging does not activate a different app")
    }
    @MainActor func testSharedResizeLeavesSourceUnderPointerAndSizesCompanions() async {
        let (controller, settings, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        settings.sharedWidths = true
        var dragged = animator.current[list[0].id]!
        dragged.size.width = 600
        server.onWindowInteraction?(list[0].id, dragged, .resize, false)
        expectNil(server.writes.last?[list[0].id])
        expect(server.writes.last!.values.allSatisfy { $0.width == 600 })
        server.onWindowInteraction?(list[0].id, dragged, .resize, true)
        expect(animator.current.values.allSatisfy { $0.width == 600 })
        controller.setAllWidths(1.0 / 3)
        expect(animator.current.values.allSatisfy { abs($0.width - 528) < 0.01 })
    }
    @MainActor func testWindowLockRestoresOthersAndLeavesFutureWindowsAlone() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        controller.setManageAllWindows(false)
        expectEqual(controller.windowChoices.map(\.id), [list[0].id])
        expect(server.writes.contains { $0[list[1].id] == list[1].frame && $0[list[2].id] == list[2].frame })
        await waitForScan()
        let future = windows(1)[0]
        server.scans.removeLast()(observed(list, animator.current) + [future], list[0].id)
        expectEqual(controller.managedCount, 1)
        controller.setWindowManaged(list[1].id, true)
        expectEqual(controller.managedCount, 2)
        controller.setWindowManaged(list[1].id, false)
        let baseline = server.writes.last
        controller.setAllWidths(1)
        expectNil(server.writes.last?[list[1].id])
        expectNotNil(baseline)
        controller.pause()
        expectEqual(Set(server.restored.keys), [list[0].id])
    }
    @MainActor func testStackTabsSelectionReorderAndTemporaryDisappearance() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[1].id)
        controller.perform(.strip(.joinLeft))
        expectEqual(animator.current[list[0].id]?.width, animator.current[list[1].id]?.width)
        expectLess(animator.current[list[0].id]!.maxY, animator.current[list[1].id]!.minY)
        controller.perform(.strip(.toggleMode))
        expectEqual(animator.current[list[0].id], animator.current[list[1].id])
        expectEqual(controller.tabGroups.first?.windows.map(\.id), [list[0].id, list[1].id])
        controller.reorderTab(list[1].id, before: list[0].id)
        controller.chooseWindow(list[0].id)
        expectEqual(controller.windowChoices.first(where: \.selected)?.id, list[0].id)
        expectEqual(server.raised.last, list[0].id)
        await waitForScan()
        let frames = animator.current
        server.scans.removeLast()(observed([list[0], list[2]], frames), list[0].id)
        await waitForScan()
        server.scans.removeLast()(observed(list, frames), list[0].id)
        expectEqual(controller.tabGroups.first?.windows.map(\.id), [list[1].id, list[0].id])
        server.onWindowRemoved?(list[0].id)
        expectEqual(controller.managedCount, 2)
        expectNil(controller.tabGroups.first, "A single remaining tab becomes a plain window")
    }
    @MainActor func testPauseHidesTabStripsUntilResume() async {
        let (controller, _, server, _) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[1].id)
        controller.perform(.strip(.joinLeft))
        controller.perform(.strip(.toggleMode))
        expectFalse(controller.tabGroups.isEmpty)
        controller.pause()
        expect(controller.tabGroups.isEmpty, "Paused, a tab strip's clicks do nothing, so it goes")
        controller.resume(); await waitForScan(); server.scans.removeLast()(list, list[0].id)
        expectFalse(controller.tabGroups.isEmpty, "Resuming brings it back")
    }
    @MainActor func testATiledWindowStaysWhenTapeMakesItSmall() async {
        let (controller, _, server, _) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        expectEqual(controller.managedCount, 3)
        let small = { (window: WindowSnapshot) in
            WindowSnapshot(id: window.id, frame: CGRect(x: window.frame.minX, y: 60, width: 200, height: 120), processID: 0,
                           isTileable: false, isTileableAtAnySize: true, bundleIdentifier: window.bundleIdentifier, title: window.title)
        }
        let palette = small(windows(1)[0])
        server.onChange?(); await waitForScan()
        server.scans.removeLast()([list[0], list[1], small(list[2]), palette], list[0].id)
        expectEqual(controller.managedCount, 3, "Already tiled, it stays; a new small window still floats")
        expect(controller.managedWindowChoices.contains { $0.id == list[2].id })
        expectFalse(controller.managedWindowChoices.contains { $0.id == palette.id })
    }
    func testStackActionsPreserveMembershipOrderWidthsAndHeightBounds() {
        let a = WindowID(), b = WindowID(), c = WindowID()
        var strip = Strip()
        for id in [a, b, c] { strip.insert(id, foreground: true) }
        strip.perform(.join(-1)); strip.perform(.join(-1))
        expectEqual(strip.columns.count, 2)
        expectEqual(Set(strip.columns.flatMap(\.windows)), [a, b, c])
        strip.select(b); strip.perform(.join(-1))
        expectEqual(strip.columns.count, 1)
        strip.perform(.adjustHeight(2))
        let frames = StripLayout.frames(for: strip, screen: screen, options: LayoutOptions(gap: 2000))
        expect(frames.values.allSatisfy { $0.height > 0 && screen.visibleFrame.contains($0) })
        strip.perform(.equalHeights)
        expect(strip.columns[0].heightWeights.isEmpty)
        strip.perform(.detach)
        expectEqual(Set(strip.columns.flatMap(\.windows)), [a, b, c])
        expectEqual(strip.focusedWindow, b)
    }

    @MainActor func testStackThatExceedsAppMinimumHeightsSeparatesInsteadOfOverlapping() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[1].id)
        controller.perform(.strip(.joinLeft))
        await waitForScan()
        var actual = animator.current
        actual[list[0].id]?.size.height = 650
        actual[list[1].id]?.size.height = 650
        server.scans.removeLast()(observed(list, actual), list[1].id)
        expectEqual(controller.windowChoices.count, 3)
        expectEqual(animator.current[list[0].id]?.height, 884)
        expectEqual(animator.current[list[1].id]?.height, 884)
        expectNotEqual(animator.current[list[0].id]?.minX, animator.current[list[1].id]?.minX)
        expectEqual(controller.windowChoices.first(where: \.selected)?.id, list[1].id)
    }

    @MainActor func testEdgeDragScrollsCompanionsWithoutWritingTheDraggedWindow() async {
        let defaults = freshDefaults()
        let server = FakeWindows(), animator = FakeAnimator(), clock = TestFrameClock()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: screen, scrollClock: clock, log: { _ in })
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[2].id)
        // Column 0 is parked off-screen and only moves once the scroll passes its sliver,
        // which depends on timer slack; the visible companion moves on any tick.
        let before = animator.current[list[1].id]!.minX
        var frame = animator.current[list[2].id]!
        frame.origin.x -= 100
        server.pointerPosition = CGPoint(x: 8, y: 100)
        server.onWindowInteraction?(list[2].id, frame, .move, false)
        try? await Task.sleep(nanoseconds: 20_000_000)
        clock.tick?()
        expectNil(server.writes.last?[list[2].id])
        expectGreater(server.writes.last![list[1].id]!.minX, before)
        server.onWindowInteraction?(list[2].id, frame, .move, true)
        expectNil(clock.tick)
    }

    @MainActor func testClosingTheDraggedWindowStopsItsEdgeBrowsingClock() async {
        let defaults = freshDefaults()
        let server = FakeWindows(), animator = FakeAnimator(), clock = TestFrameClock()
        let controller = TapeController(settings: TapeSettings(defaults: defaults), server: server, animator: animator, permissionCheck: { true }, registerShortcuts: false, geometry: screen, scrollClock: clock, log: { _ in })
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[2].id)
        var frame = animator.current[list[2].id]!
        frame.origin.x -= 100
        server.onWindowInteraction?(list[2].id, frame, .move, false)
        expectNotNil(clock.tick)
        server.onWindowRemoved?(list[2].id)
        expectNil(clock.tick, "A display link left running fires at the refresh rate indefinitely")
    }

    @MainActor func testQuitRestoresWindowMissingFromLatestScanAfterOffscreenBrowsing() async {
        let (controller, _, server, animator) = fixture()
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        controller.chooseWindow(list[2].id)
        await waitForScan()
        server.scans.removeLast()(observed([list[1], list[2]], animator.current), list[2].id)
        expectEqual(controller.managedCount, 2, "The omitted window can be hidden or unavailable")
        var finished = false
        controller.shutdown { finished = true }
        expect(finished)
        expectEqual(server.restored[list[0].id], list[0].frame)
        expect(server.restored.values.allSatisfy { screen.visibleFrame.contains($0) })
    }

    @MainActor func testHiddenWindowReturnsToItsSlotRatherThanBesideTheFocusedColumn() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows(5), order = list.map(\.id)
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        expectEqual(controller.windowChoices.map(\.id), order)
        // Hide or minimize the fourth window, then bring it back.
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list.filter { $0.id != list[3].id }, animator.current), list[0].id)
        expectEqual(controller.windowChoices.map(\.id), [order[0], order[1], order[2], order[4]])
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        expectEqual(controller.windowChoices.map(\.id), order)
        // An app with two windows hides and unhides; neither the slots nor their order change.
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed([list[0], list[2], list[4]], animator.current), list[0].id)
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        expectEqual(controller.windowChoices.map(\.id), order)
    }

    @MainActor func testSwitchingDesktopsAndBackKeepsTheStripOrder() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows(6), order = list.map(\.id)
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[2].id)
        // Parked windows keep a six-point sliver, so a narrower column parks further right.
        controller.chooseWindow(list[0].id); controller.setWidth(1.0 / 3)
        controller.chooseWindow(list[1].id); controller.setWidth(2.0 / 3)
        controller.perform(.strip(.last))
        let parked = animator.current
        expectGreater(Set(parked.values.map(\.minX)).count, 1)
        // Another desktop has none of these windows; returning reports their parked frames,
        // which no longer sort left to right.
        server.onDesktopChange?(); await waitForScan()
        server.scans.removeLast()([], nil)
        expectEqual(controller.managedCount, 0)
        server.onDesktopChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, parked), list[5].id)
        expectEqual(controller.windowChoices.map(\.id), order)
    }

    @MainActor func testSeveralNewWindowsKeepTheirLeftToRightOrderAfterTheFocusedColumn() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows(5)
        controller.resume(); await waitForScan(); server.scans.removeFirst()(Array(list.prefix(2)), list[0].id)
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        expectEqual(controller.windowChoices.map(\.id), [list[0].id, list[2].id, list[3].id, list[4].id, list[1].id])
    }

    @MainActor func testAWindowListedTwiceJoinsOnce() async {
        let (controller, _, server, _) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list + [list[1]], list[0].id)
        expectEqual(controller.windowChoices.map(\.id), list.map(\.id))
    }

    @MainActor func testUnchangedScansAndDragFramesDoNotRepublishStatus() async {
        let (controller, _, server, animator) = fixture()
        defer { controller.pause() }
        let list = windows()
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        var changes = 0
        let subscription = controller.objectWillChange.sink { changes += 1 }
        defer { subscription.cancel() }
        server.onChange?(); await waitForScan()
        server.scans.removeLast()(observed(list, animator.current), list[0].id)
        expectEqual(changes, 0, "Settings re-renders on every published assignment")
        var frame = animator.current[list[1].id]!
        for step in 1...5 {
            frame.size.width += 1
            server.onWindowInteraction?(list[1].id, frame, .resize, step == 5)
        }
        expectEqual(changes, 0)
    }

    @MainActor func testPauseRestoresHiddenWindowsButNotExplicitlyReleasedOrClosedWindows() async {
        let (controller, _, server, animator) = fixture()
        let list = windows(4)
        controller.resume(); await waitForScan(); server.scans.removeFirst()(list, list[0].id)
        controller.setWindowManaged(list[1].id, false)
        server.onWindowRemoved?(list[2].id)
        await waitForScan()
        server.scans.removeLast()(observed([list[1], list[3]], animator.current), list[3].id)
        controller.pause()
        expectEqual(server.restored[list[0].id], list[0].frame)
        expectNil(server.restored[list[1].id])
        expectNil(server.restored[list[2].id])
        expectEqual(server.restored[list[3].id], StripLayout.restored(list[3].frame, on: screen))
    }

    func testRestorationWaitsBehindInFlightParkedWriteAndIsTheLastFrame() {
        let started = expectation(description: "parked write in flight"), settled = expectation(description: "restored")
        let release = DispatchSemaphore(value: 0), lock = NSLock()
        var frames: [CGRect] = []
        let id = WindowID(), parked = CGRect(x: -500, y: 50, width: 506, height: 700), restored = CGRect(x: 40, y: 60, width: 380, height: 650)
        let queue = FrameWriteQueue { job in
            if !job.restoring { started.fulfill(); _ = release.wait(timeout: .now() + 2) }
            lock.lock(); frames.append(job.frame); lock.unlock()
        }
        queue.enqueue([(1, FrameWrite(id: id, frame: parked, generation: 0))])
        wait(for: [started], timeout: 1)
        queue.cancelPending()
        queue.enqueue([(1, FrameWrite(id: id, frame: restored, generation: 1, restoring: true))])
        queue.whenIdle { settled.fulfill() }
        release.signal()
        wait(for: [settled], timeout: 1)
        lock.lock(); let written = frames; lock.unlock()
        expectEqual(written, [parked, restored])
    }
}

@main struct TapeChecks {
    @MainActor static func main() async throws {
        let layoutTests = LayoutTests()
        layoutTests.testEmptyStripHasNoFrames()
        layoutTests.testAutomaticLoneWindowFillsScreenAndTabNotificationsCannotHalveIt()
        layoutTests.testFramesRespectMenuBarDockAndEdgeGaps()
        layoutTests.testFullWidthExcludesBothEdgeGaps()
        layoutTests.testAppMinimumWidthRetainsPresetAndPushesNextColumn()
        layoutTests.testLogicalColumnsNeverOverlap()
        layoutTests.testZeroGapsAreSupported()
        layoutTests.testViewportOffsetDoesNotChangeColumnWidth()
        layoutTests.testFocusOnlyScrollsAsFarAsNeeded()
        layoutTests.testFocusLeftRevealsFirstColumn()
        layoutTests.testAlwaysCenterCanAddLeadingSpace()
        layoutTests.testOverflowCenterOnlyAppliesToOverflowingStrip()
        layoutTests.testExplicitCenterWorksWithoutOverflow()
        layoutTests.testWidthsCannotExceedViewportOrCollapse()
        layoutTests.testGapsCannotInvertContentRect()
        layoutTests.testLeftParkingKeepsSixPointsVisible()
        layoutTests.testRightParkingKeepsSixPointsVisible()
        layoutTests.testSharedRightEdgeNeverEntersNeighbor()
        layoutTests.testSharedLeftEdgeNeverEntersNeighbor()
        layoutTests.testStackedDisplayParkingStaysVerticallyContained()
        layoutTests.testSecondaryCoordinateSystemSupportsNegativeOrigin()
        layoutTests.testRestoreClampsAnOldFrameToCurrentVisibleDisplay()
        layoutTests.testParkingAcrossRandomFramesKeepsWindowsReachableAndOutOfNeighbors()
        let stripTests = StripTests()
        stripTests.testBackgroundInsertionPreservesFocusWidthsAndScroll()
        stripTests.testNewWindowOpensRightOfFocusedColumn()
        stripTests.testDuplicateWindowsAreIgnored()
        stripTests.testMovePreservesFocusedWindowAndWidths()
        stripTests.testFocusClampsAndMissingSlotDoesNothing()
        stripTests.testWidthPresetCycle()
        stripTests.testRemoveFocusedWindowSelectsNearestRemainingColumn()
        stripTests.testFloatingClassification()
        let interactionTests = InteractionTests()
        interactionTests.testCompactKeyboardEndShortcutsKeepExistingBindings()
        interactionTests.testResizeHappensOnceWhileTheWindowSlides()
        interactionTests.testStaleFocusDoesNotUndoRapidKeyboardNavigation()
        interactionTests.testFocusIntentExpiresOrReleasesAClosedWindow()
        try interactionTests.testAppChoicesWorkInBothModesAndPersist()
        interactionTests.testExplicitWidthPreservesOtherColumns()
        let discoveryTests = DiscoveryTests()
        discoveryTests.testMenuBarAppsWithNormalWindowsAreDiscoverable()
        discoveryTests.testNormalCustomWindowsRemainEligibleWhileDialogsStayFloating()
        discoveryTests.testIndependentFrameReadsAllowSmallDriftWithoutMatchingOtherWindows()
        discoveryTests.testCenteredEdgeDoesNotJumpOnFirstScrollPixel()
        let focusReadTests = FocusReadTests()
        focusReadTests.testNewestNotificationSupersedesQueuedAndInFlightReads()
        focusReadTests.testKeyboardCommandInvalidatesEarlierRead()
        let scrollingTests = ScrollingTests()
        scrollingTests.testGestureKeepsMomentumAfterReleasingModifiers()
        scrollingTests.testKeyboardSelectionSwallowsRemainingMomentumUntilTheNextGesture()
        scrollingTests.testOrdinaryVerticalAndMouseWheelScrollingPassThrough()
        scrollingTests.testCannotCaptureMiddleOfAnOrdinaryGestureOrOrphanMomentum()
        scrollingTests.testCancellationAndIneligibleDisplayReleaseGesture()
        scrollingTests.testScrollBoundsPreserveFocusAndWidths()
        scrollingTests.testDisplayTicksDoNotSkipHighRefreshFramesAndRetargetDoesNotRestartFullDuration()
        scrollingTests.testSlowAppDoesNotBlockOtherAppAndPendingFramesCoalesce()
        scrollingTests.testReconciliationWaitsForInFlightAndNewestQueuedWrite()
        scrollingTests.testUnavailableDisplayClockCompletesAnimation()
        scrollingTests.testCancellingQueueDropsWaitingFrames()
        let controllerTests = ControllerTests()
        await controllerTests.testStartupOrderAndRapidFocusAreStable()
        await controllerTests.testExcludingAnAppRestoresItAndStopsManagingIt()
        await controllerTests.testOldScanCannotUndoAKeyboardAction()
        await controllerTests.testOnlySelectedAppsReachTheWindowScan()
        await controllerTests.testManualMoveIsCorrectedEvenWhenTargetsAreUnchanged()
        await controllerTests.testRejectedFramesDoNotStartAnEndlessCorrectionLoop()
        await controllerTests.testReversalUsesCurrentAnimationPosition()
        await controllerTests.testPreviousRunScanCannotReleaseCurrentScan()
        await controllerTests.testScrollingCoalescesAtDisplayRefreshWithoutActivatingApps()
        await controllerTests.testAppMinimumWidthIsLearnedAfterTrackpadBrowsing()
        let displayTests = DisplayTests()
        displayTests.testOwnershipUsesAreaAndKeepsStableBoundaryTies()
        displayTests.testNegativeAndStackedDisplaysAndDisconnectedFallback()
        displayTests.testNextDisplaySkipsDisabledAndRequiresAnotherDestination()
        displayTests.testRemovingTailWindowsCannotLeaveTheViewportPastTheStrip()
        displayTests.testMirroringCreatesOneDrawableStrip()
        await displayTests.testTwoDisplaysHaveIndependentWritesAndBrowsingDoesNotMoveFocus()
        await displayTests.testTransferKeepsWidthAndPauseRestoresOriginalDisplay()
        await displayTests.testDisableRestoreReenableAndPauseLeaveExcludedDisplayAlone()
        await displayTests.testUnplugPreservesWindowsWidthsAndReachableRestoration()
        await displayTests.testRearrangingDisplaysRestoresLocalWindowPositions()
        await displayTests.testManualMoveBetweenDisplaysKeepsTheWindowPreset()
        let windowInteractionTests = WindowInteractionTests()
        await windowInteractionTests.testNativeTabAndFocusChangesKeepLoneWindowFullOrExplicitWidth()
        await windowInteractionTests.testCloseRetargetsMotionImmediatelyAndDropsClosedWindow()
        await windowInteractionTests.testDragReordersOnlyOnReleaseAndScanDoesNotFightIt()
        await windowInteractionTests.testSharedResizeLeavesSourceUnderPointerAndSizesCompanions()
        await windowInteractionTests.testWindowLockRestoresOthersAndLeavesFutureWindowsAlone()
        await windowInteractionTests.testStackTabsSelectionReorderAndTemporaryDisappearance()
        await windowInteractionTests.testPauseHidesTabStripsUntilResume()
        await windowInteractionTests.testATiledWindowStaysWhenTapeMakesItSmall()
        windowInteractionTests.testStackActionsPreserveMembershipOrderWidthsAndHeightBounds()
        await windowInteractionTests.testStackThatExceedsAppMinimumHeightsSeparatesInsteadOfOverlapping()
        await windowInteractionTests.testEdgeDragScrollsCompanionsWithoutWritingTheDraggedWindow()
        await windowInteractionTests.testClosingTheDraggedWindowStopsItsEdgeBrowsingClock()
        await windowInteractionTests.testQuitRestoresWindowMissingFromLatestScanAfterOffscreenBrowsing()
        await windowInteractionTests.testHiddenWindowReturnsToItsSlotRatherThanBesideTheFocusedColumn()
        await windowInteractionTests.testSwitchingDesktopsAndBackKeepsTheStripOrder()
        await windowInteractionTests.testSeveralNewWindowsKeepTheirLeftToRightOrderAfterTheFocusedColumn()
        await windowInteractionTests.testAWindowListedTwiceJoinsOnce()
        await windowInteractionTests.testUnchangedScansAndDragFramesDoNotRepublishStatus()
        await windowInteractionTests.testPauseRestoresHiddenWindowsButNotExplicitlyReleasedOrClosedWindows()
        windowInteractionTests.testRestorationWaitsBehindInFlightParkedWriteAndIsTheLastFrame()
        importingTapeSettings()
        await switchingOffFreesTheController()
        let desktopTests = DesktopTests()
        desktopTests.testWhatCountsAsOff()
        await desktopTests.testArrivingOnAnOffDesktopLeavesItAlone()
        await desktopTests.testTurningOffTheDesktopYouAreOnPutsItsWindowsBack()
        await desktopTests.testTurningOffAnotherDesktopWaitsForTheNextVisit()
        await desktopTests.testPausingRestoresADesktopTurnedOffFromElsewhere()
        await desktopTests.testEachDisplayFollowsItsOwnDesktop()
        await desktopTests.testWithoutThePrivateListTapeRunsEverywhere()
        // Written out now, so the script's clean-up isn't followed by a late write.
        freshDefaults().synchronize()
        print("Tape checks passed: on or off per desktop, importing the Tape app's settings once, switching off frees the controller, strip geometry and parking, window traits, gestures and momentum, focus and scan races, app rules, independent displays, transfers, exclusion, unplugging, restoration")
    }
}
