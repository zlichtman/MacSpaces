import AppKit

/// One-tap system actions used by the Quick Actions widget.
enum QuickActions {
    static func toggleDarkMode() {
        runAppleScript("""
        tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
        """)
    }

    static func lockScreen() {
        // Same as Control+Command+Q; SACLockScreenImmediate is private, so use
        // the login window helper which is stable across macOS versions.
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/System/Library/CoreServices/Menu Extras/User.menu/Contents/Resources/CGSession")
        task.arguments = ["-suspend"]
        try? task.run()
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

    static func openScreenSaver() {
        // Locking via screensaver respects the user's password-delay setting.
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        NSWorkspace.shared.openApplication(at: url, configuration: .init())
    }

    private static func runAppleScript(_ source: String) {
        AppleScriptRunner.run(source)
    }
}
