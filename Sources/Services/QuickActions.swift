import AppKit
import Darwin

/// One-tap system actions used by the Quick Actions widget.
enum QuickActions {
    static func toggleDarkMode() {
        runAppleScript("""
        tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
        """)
    }

    static func lockScreen() {
        // Same as Control+Command+Q and needs no permission. It's private (the old
        // CGSession tool left macOS in Big Sur), so the screen saver covers its absence.
        typealias LockScreen = @convention(c) () -> Int32
        guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
              let symbol = dlsym(handle, "SACLockScreenImmediate") else {
            openScreenSaver()
            return
        }
        _ = unsafeBitCast(symbol, to: LockScreen.self)()
    }

    static func captureScreenSelection() {
        // Interactive selection straight to the clipboard.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        task.arguments = ["-i", "-c"]
        try? task.run()
    }

    /// Confirmed first: this permanently deletes files with no undo, and the
    /// button sits one tile away from the other, harmless quick actions.
    @MainActor
    static func emptyTrash() {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Empty the Trash?"
        alert.informativeText = "Items in the Trash will be deleted immediately. You can't undo this action."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        runAppleScript("tell application \"Finder\" to empty trash")
    }

    /// Turns the displays off without sleeping the Mac or locking it.
    static func sleepDisplays() {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        task.arguments = ["displaysleepnow"]
        try? task.run()
    }

    static func openScreenSaver() {
        // Locking via screensaver respects the user's password-delay setting.
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private static func runAppleScript(_ source: String) {
        AppleScriptRunner.run(source)
    }
}
