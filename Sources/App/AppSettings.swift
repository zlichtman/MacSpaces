import Foundation
import Combine
import ServiceManagement

/// App-level settings: which modules run and the login item.
/// Module-specific options live in `NotchSettings` and `DockStore`.
@MainActor
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var notchEnabled: Bool {
        didSet { defaults.set(notchEnabled, forKey: "notchEnabled") }
    }

    @Published var dockEnabled: Bool {
        didSet { defaults.set(dockEnabled, forKey: "dockEnabled") }
    }

    @Published var launchAtLogin: Bool {
        didSet { updateLaunchAtLogin() }
    }

    private let defaults = UserDefaults.standard
    /// Suppresses `didSet` re-entry while rolling back a failed change.
    private var isRevertingLaunchAtLogin = false

    private init() {
        defaults.register(defaults: [
            "notchEnabled": true,
            "dockEnabled": true,
        ])

        notchEnabled = defaults.bool(forKey: "notchEnabled")
        dockEnabled = defaults.bool(forKey: "dockEnabled")
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func updateLaunchAtLogin() {
        guard !isRevertingLaunchAtLogin else { return }
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Launch-at-login change failed: \(error)")
            // Roll back so the published value reflects the actual state.
            isRevertingLaunchAtLogin = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            isRevertingLaunchAtLogin = false
        }
    }
}
