#if DEBUG
import AppKit

@MainActor
enum VisualQAHarness {
    static func captureIfRequested() -> Bool { WebsiteDemoCapture.captureIfRequested() }
}
#endif
