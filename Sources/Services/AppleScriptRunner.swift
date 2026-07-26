import Foundation

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
    }

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

    /// Runs `source` on the shared queue and returns its result, for callers
    /// already off the main thread that need the value inline.
    static func runSynchronously(_ source: String) -> Result {
        queue.sync {
            var error: NSDictionary?
            let descriptor = NSAppleScript(source: source)?
                .executeAndReturnError(&error)
            return Result(descriptor: descriptor, failed: descriptor == nil || error != nil)
        }
    }
}
