import SwiftUI

@main
struct MacSpacesApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        MenuBarExtra("MacSpaces", systemImage: "macbook.gen2") {
            MenuBarMenu()
        }
    }
}

/// Only what can't be reached from the Nook itself (owner, 2.100): Dictation and
/// Meeting Controls are Nook pages, reachable from the dock, ⌃⌥D and Find Action.
private struct MenuBarMenu: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var keys = NookHotKeys.shared
    @ObservedObject private var presence = NookPresence.shared

    var body: some View {
        // Opened from here the Nook stays pinned, so this item also closes it.
        if presence.isOpen {
            Button("Close Nook") { NotchManager.active?.closeAll() }
        } else {
            Button("Open Nook") { NookCommands.open(.nook) }
        }
        findAction
        Toggle("Enable Nook", isOn: $settings.notchEnabled)
        Menu("File Converter") {
            Toggle("Convert by Shift-Dragging", isOn: $settings.fileConverterEnabled)
            Button("Open File Tools") { FileToolsWindow.shared.show() }
        }
        Button("File Baskets") { BasketWindowController.shared.show() }

        Divider()

        Button("Settings") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",")
        Button("How to Use MacSpaces") { WelcomeWindow.shared.show() }

        Divider()

        Button("Check for Updates") {
            SettingsWindowController.shared.show(.general)
            UpdateService.shared.check()
        }

        Divider()

        Button("Quit MacSpaces") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    /// Shows the Find Action hot key beside it, when one is set.
    @ViewBuilder private var findAction: some View {
        switch keys.shortcut {
        case .controlOptionSpace:
            Button("Find Action") { ActionSearchWindow.shared.show() }.keyboardShortcut(.space, modifiers: [.control, .option])
        case .controlOptionCommandSpace:
            Button("Find Action") { ActionSearchWindow.shared.show() }.keyboardShortcut(.space, modifiers: [.control, .option, .command])
        case .off:
            Button("Find Action") { ActionSearchWindow.shared.show() }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let showSettingsNotification = Notification.Name(
        "dev.opensource.MacSpaces.showSettings"
    )

    private var moduleCoordinator: ModuleCoordinator?
    private var isDuplicateInstance = false
    private var showSettingsObserver: NSObjectProtocol?

    func applicationWillFinishLaunching(_ notification: Notification) {
#if DEBUG
        if ProcessInfo.processInfo.environment["MACSPACES_VISUAL_QA"] == "1" {
            return
        }
#endif
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else { return }
        let currentPID = ProcessInfo.processInfo.processIdentifier
        let otherInstance = NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter {
                $0.processIdentifier < currentPID && !$0.isTerminated
            }
            .min { $0.processIdentifier < $1.processIdentifier }

        guard let otherInstance else { return }
        isDuplicateInstance = true
        DistributedNotificationCenter.default().postNotificationName(
            Self.showSettingsNotification,
            object: nil,
            deliverImmediately: true
        )
        otherInstance.activate(options: [.activateAllWindows])
        NSApp.terminate(nil)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !isDuplicateInstance else { return }
        NSApp.setActivationPolicy(.accessory)

#if DEBUG
        if AppearanceQAHarness.captureIfRequested() { return }
        if FeatureQAHarness.captureIfRequested() { return }
        if WebsiteDemoCapture.captureIfRequested() { return }
        if VisualQAHarness.captureIfRequested() {
            return
        }
#endif

        // Before anything below saves a setting, so a copy that has run before is told apart.
        WelcomeWindow.noteInstall()
        moduleCoordinator = ModuleCoordinator()
        moduleCoordinator?.start()
        TimerFocus.migrateOldSession()
        WispCharacter.migrateGlass()
        _ = TimerFocus.shared
        UpdateService.shared.start()
        BasketWindowController.shared.restoreOpenBaskets()
        ConverterWheel.shared.setEnabled(AppSettings.shared.fileConverterEnabled)
        ClipboardPopup.shared.registerShortcut()
        NookHotKeys.shared.register()
        CompletedDownloads.shared.restore()
        NSApp.servicesProvider = MacSpacesFileServices.shared
        AgentPopout.shared.start()
        SpotifyLibrary.shared.startWeekly()
        // After NookHotKeys, whose shortcuts win over Tape's.
        TapeFeature.shared.startAtLaunch()
        WelcomeWindow.shared.showIfNew()

        showSettingsObserver = DistributedNotificationCenter.default().addObserver(
            forName: Self.showSettingsNotification,
            object: nil,
            queue: .main
        ) { _ in
            Task { @MainActor in
                SettingsWindowController.shared.show()
            }
        }

        let launchEvent = NSAppleEventManager.shared().currentAppleEvent
        let launchedAtLogin = launchEvent?.attributeDescriptor(
            forKeyword: AEKeyword(keyAELaunchedAsLogInItem)
        ) != nil
        if !launchedAtLogin {
            DispatchQueue.main.async {
                SettingsWindowController.shared.show()
            }
        }
    }

    func applicationShouldHandleReopen(
        _ sender: NSApplication,
        hasVisibleWindows flag: Bool
    ) -> Bool {
        SettingsWindowController.shared.show()
        return true
    }

    func applicationOpenUntitledFile(_ sender: NSApplication) -> Bool {
        DispatchQueue.main.async {
            SettingsWindowController.shared.show()
        }
        return true
    }

    /// With Tape on, windows go back to where they were before quitting (at most 9 s).
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !isDuplicateInstance, TapeFeature.shared.needsStopBeforeQuit else { return .terminateNow }
        TapeFeature.shared.stopForQuit { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let showSettingsObserver {
            DistributedNotificationCenter.default().removeObserver(showSettingsObserver)
        }
        // A duplicate instance read nothing of its own, so it has nothing to write.
        guard !isDuplicateInstance else { return }
        NookSettings.shared.flushPersistence()
        ConverterJobs.shared.cancelAll()
        FileConverter.abandonUnfinishedJobs()
        // "Agents keep running" doesn't outlive MacSpaces (through the helper; no prompt).
        LidClosedAwake.shared.turnOffForQuit()
        TimerFocus.releaseFocusForQuit()
    }
}
