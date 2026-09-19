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

private struct MenuBarMenu: View {
    @ObservedObject private var settings = AppSettings.shared
    @ObservedObject private var dockStore = DockStore.shared
    @ObservedObject private var nookSettings = NookSettings.shared

    var body: some View {
        Toggle("Notch Hub", isOn: $settings.notchEnabled)
        Toggle("Widget Dock", isOn: $settings.dockEnabled)

        if settings.notchEnabled {
            Picker("Nook Profile", selection: $nookSettings.activeProfileID) {
                ForEach(nookSettings.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
        }

        if settings.dockEnabled {
            Picker("Dock Profile", selection: $dockStore.activeProfileID) {
                ForEach(dockStore.profiles) { profile in
                    Text(profile.name).tag(profile.id)
                }
            }
        }

        Divider()

        Button("Settings…") {
            SettingsWindowController.shared.show()
        }
        .keyboardShortcut(",")

        Button("Check for Updates…") {
            SettingsWindowController.shared.show(.about)
            UpdateService.shared.check()
        }

        Divider()

        Button("Quit MacSpaces") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
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
        if VisualQAHarness.captureIfRequested() {
            return
        }
#endif

        moduleCoordinator = ModuleCoordinator()
        moduleCoordinator?.start()
        UpdateService.shared.start()

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

    func applicationWillTerminate(_ notification: Notification) {
        if let showSettingsObserver {
            DistributedNotificationCenter.default().removeObserver(showSettingsObserver)
        }
        DockStore.shared.flushPersistence()
        NookSettings.shared.flushPersistence()
    }
}
