import Foundation
import Carbon

/// Single serial executor for every `NSAppleScript` in the app.
///
/// `NSAppleScript` is not thread-safe, so concurrent executions from different
/// queues can corrupt the shared Apple Event machinery. It is also not
/// main-thread-only: running it on the main thread simply blocks the UI for as
/// long as the target app takes to answer, which for a cold Mail launch or a
/// first-time automation prompt is seconds.
enum AppleScriptRunner {
    private static let queue = DispatchQueue(label: "dev.opensource.MacSpaces.applescript")

    struct Result {
        let descriptor: NSAppleEventDescriptor?
        let failed: Bool
        /// The middle of the script's own execution, after any wait for the queue.
        var midpoint = Date()
    }

    /// Polling scripts compiled once and reused (queue-confined). Compiling cost
    /// more than running them: the now-playing poll recompiled every 0.8 s.
    nonisolated(unsafe) private static var compiled: [String: NSAppleScript] = [:]

    /// Runs `source` off the main thread and delivers the result on the main
    /// actor. Callers that only care about the side effect can ignore it.
    static func run(
        _ source: String,
        completion: (@Sendable @MainActor (Result) -> Void)? = nil
    ) {
        queue.async {
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: source)?
                .executeAndReturnError(&error)
            let result = Result(descriptor: descriptor, failed: descriptor == nil || error != nil)
            guard let completion else { return }
            Task { @MainActor in completion(result) }
        }
    }

    enum Argument: Sendable { case text(String), strings([String]) }
    static func runHandler(_ source: String, name: String, arguments: [Argument],
                           completion: @escaping @Sendable @MainActor (Result) -> Void) {
        queue.async {
            var error: NSDictionary?
            let script = NSAppleScript(source: source)
            let event = NSAppleEventDescriptor(eventClass: AEEventClass(kASAppleScriptSuite), eventID: AEEventID(kASSubroutineEvent),
                targetDescriptor: nil, returnID: AEReturnID(kAutoGenerateReturnID), transactionID: AETransactionID(kAnyTransactionID))
            event.setParam(NSAppleEventDescriptor(string: name), forKeyword: AEKeyword(keyASSubroutineName))
            let parameters = NSAppleEventDescriptor.list()
            for (index, argument) in arguments.enumerated() {
                let descriptor: NSAppleEventDescriptor
                switch argument {
                case .text(let text): descriptor = NSAppleEventDescriptor(string: text)
                case .strings(let strings):
                    descriptor = .list()
                    for (i, text) in strings.enumerated() { descriptor.insert(NSAppleEventDescriptor(string: text), at: i + 1) }
                }
                parameters.insert(descriptor, at: index + 1)
            }
            event.setParam(parameters, forKeyword: AEKeyword(keyDirectObject))
            let value = script?.executeAppleEvent(event, error: &error)
            let result = Result(descriptor: value, failed: value == nil || error != nil)
            Task { @MainActor in completion(result) }
        }
    }

    /// Runs `source` on the shared queue and returns its result, for callers
    /// already off the main thread that need the value inline. `reuse` keeps the
    /// compiled script for the next call; only fixed polling sources pass it.
    static func runSynchronously(_ source: String, reuse: Bool = false) -> Result {
        queue.sync {
            var error: NSDictionary?
            let script: NSAppleScript?
            if reuse, let cached = compiled[source] {
                script = cached
            } else {
                script = NSAppleScript(source: source)
                if reuse, let script, script.compileAndReturnError(nil), compiled.count < 16 { compiled[source] = script }
            }
            let started = Date()
            let descriptor = script?.executeAndReturnError(&error)
            let midpoint = started.addingTimeInterval(Date().timeIntervalSince(started) / 2)
            return Result(descriptor: descriptor, failed: descriptor == nil || error != nil, midpoint: midpoint)
        }
    }
}
