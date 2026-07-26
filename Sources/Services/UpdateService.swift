import AppKit
import Combine
import Foundation
@preconcurrency import UserNotifications

@MainActor
final class UpdateService: ObservableObject {
    static let shared = UpdateService()

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(String)
        case downloading(String)
        case installing(String)
        case failed(String)

        var label: String {
            switch self {
            case .idle: return "Check for Updates"
            case .checking: return "Checking…"
            case .upToDate: return "MacSpaces is up to date"
            case let .available(version): return "Version \(version) is available"
            case let .downloading(version): return "Downloading \(version)…"
            case let .installing(version): return "Installing \(version)…"
            case let .failed(message): return message
            }
        }
    }

    private struct Release: Decodable {
        struct Asset: Decodable {
            let name: String
            let browserDownloadURL: URL

            private enum CodingKeys: String, CodingKey {
                case name
                case browserDownloadURL = "browser_download_url"
            }
        }

        let tagName: String
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease, assets
        }
    }

    @Published private(set) var status: Status = .idle

    /// Checking is independent of installing: turning off automatic installs
    /// used to also stop background checks, so the user was never told a new
    /// version existed.
    @Published var automaticallyCheckForUpdates: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticallyCheckForUpdates,
                forKey: Self.automaticCheckKey
            )
        }
    }

    @Published var automaticallyInstallUpdates: Bool {
        didSet {
            UserDefaults.standard.set(
                automaticallyInstallUpdates,
                forKey: Self.automaticKey
            )
        }
    }

    private static let automaticKey = "updates.automaticallyInstall"
    private static let automaticCheckKey = "updates.automaticallyCheck"
    private static let lastCheckKey = "updates.lastCheck"
    private static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]
    private let endpoint = URL(
        string: "https://api.github.com/repos/zlichtman/MacSpaces/releases/latest"
    )!

    /// Bounded so a stalled connection cannot leave the UI stuck on
    /// "Checking…" or "Downloading…" forever.
    private let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 600
        return URLSession(configuration: configuration)
    }()

    private var task: URLSessionTask?
    private var availableDownloadURL: URL?
    private var availableVersion: String?

    private init() {
        // Installing defaults off: it terminates and relaunches the app, which
        // is not something to do to someone mid-task without asking.
        UserDefaults.standard.register(defaults: [
            Self.automaticKey: false,
            Self.automaticCheckKey: true,
        ])
        automaticallyInstallUpdates = UserDefaults.standard.bool(forKey: Self.automaticKey)
        automaticallyCheckForUpdates = UserDefaults.standard.bool(forKey: Self.automaticCheckKey)
    }

    func start() {
        guard automaticallyCheckForUpdates else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        guard last == nil || Date().timeIntervalSince(last!) > 6 * 60 * 60 else {
            return
        }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            check(manual: false)
        }
    }

    func check(manual: Bool = true) {
        guard task == nil else { return }
        status = .checking
        var request = URLRequest(url: endpoint)
        request.setValue(
            "application/vnd.github+json",
            forHTTPHeaderField: "Accept"
        )
        request.setValue(
            "MacSpaces/\(currentVersion)",
            forHTTPHeaderField: "User-Agent"
        )
        task = session.dataTask(with: request) { [weak self] data, _, error in
            Task { @MainActor [weak self] in
                guard let self else { return }
                self.task = nil
                UserDefaults.standard.set(Date(), forKey: Self.lastCheckKey)
                guard error == nil,
                      let data,
                      let release = try? JSONDecoder().decode(Release.self, from: data),
                      !release.draft,
                      !release.prerelease else {
                    self.status = manual
                        ? .failed("Couldn’t check for updates")
                        : .idle
                    return
                }

                let version = release.tagName
                    .trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
                guard self.isNewer(version, than: self.currentVersion) else {
                    self.availableDownloadURL = nil
                    self.availableVersion = nil
                    self.status = manual ? .upToDate : .idle
                    return
                }
                guard let asset = release.assets.first(where: {
                    $0.name.lowercased() == "macspaces.dmg"
                }) else {
                    self.status = .failed("Update is missing MacSpaces.dmg")
                    return
                }
                // The download location comes from a JSON payload, so it is
                // pinned to HTTPS on GitHub's own asset hosts rather than
                // followed wherever it happens to point.
                guard Self.isTrustedDownload(asset.browserDownloadURL) else {
                    self.status = .failed("Update came from an unexpected location")
                    return
                }

                self.availableDownloadURL = asset.browserDownloadURL
                self.availableVersion = version
                self.status = .available(version)
                self.notifyAvailable(version)
                if self.automaticallyInstallUpdates {
                    self.downloadAndInstall(asset.browserDownloadURL, version: version)
                }
            }
        }
        task?.resume()
    }

    var actionLabel: String {
        if case .available = status {
            return "Install"
        }
        return "Check Now"
    }

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    func performPrimaryAction() {
        if case .available = status,
           let availableDownloadURL,
           let availableVersion {
            downloadAndInstall(availableDownloadURL, version: availableVersion)
        } else {
            check()
        }
    }

    private func downloadAndInstall(_ url: URL, version: String) {
        availableDownloadURL = nil
        availableVersion = nil
        status = .downloading(version)
        task = session.downloadTask(with: url) { [weak self] temporaryURL, _, error in
            guard error == nil, let temporaryURL else {
                Task { @MainActor [weak self] in
                    self?.task = nil
                    self?.status = .failed("Update download failed")
                }
                return
            }

            do {
                let retained = FileManager.default.temporaryDirectory
                    .appendingPathComponent("MacSpaces-\(UUID().uuidString).dmg")
                try FileManager.default.moveItem(at: temporaryURL, to: retained)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.task = nil
                    self.install(retained, version: version, source: url)
                }
            } catch {
                Task { @MainActor [weak self] in
                    self?.task = nil
                    self?.status = .failed("Couldn’t prepare the update")
                }
            }
        }
        task?.resume()
    }

    private func install(_ diskImage: URL, version: String, source: URL) {
        status = .installing(version)
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let installedApp = Bundle.main.bundleURL

        Task {
            // Mounting, verifying and copying a few hundred megabytes takes
            // seconds. Run it off the main actor so the UI stays responsive.
            let staged = await Task.detached(priority: .userInitiated) {
                try? Self.stageVerifiedApp(
                    from: diskImage,
                    expectedBundleIdentifier: bundleIdentifier,
                    matching: installedApp
                )
            }.value

            guard let staged else {
                status = .failed("Update verification failed")
                try? FileManager.default.removeItem(at: diskImage)
                return
            }

            guard confirmRelaunch(version: version) else {
                // Restore the offer so "Install" works again later rather than
                // silently falling back to another check.
                availableDownloadURL = source
                availableVersion = version
                status = .available(version)
                try? FileManager.default.removeItem(at: staged.root)
                return
            }

            do {
                try scheduleReplacement(with: staged.app, cleaning: staged.root)
                NSApp.terminate(nil)
            } catch {
                status = .failed("Couldn’t install the update")
                try? FileManager.default.removeItem(at: staged.root)
            }
        }
    }

    /// Quitting and relaunching mid-session needs an explicit yes, even when
    /// automatic installs are enabled.
    private func confirmRelaunch(version: String) -> Bool {
        let alert = NSAlert()
        alert.messageText = "Install MacSpaces \(version)?"
        alert.informativeText = "MacSpaces will quit and reopen to finish installing."
        alert.addButton(withTitle: "Install and Relaunch")
        alert.addButton(withTitle: "Later")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private struct StagedUpdate {
        let root: URL
        let app: URL
    }

    nonisolated private static func stageVerifiedApp(
        from diskImage: URL,
        expectedBundleIdentifier: String?,
        matching installedApp: URL
    ) throws -> StagedUpdate {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacSpacesUpdate-\(UUID().uuidString)", isDirectory: true)
        let mount = root.appendingPathComponent("Mount", isDirectory: true)
        let staged = root.appendingPathComponent("MacSpaces.app", isDirectory: true)
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)

        do {
            try run(
                "/usr/bin/hdiutil",
                ["attach", "-nobrowse", "-readonly", "-mountpoint", mount.path, diskImage.path]
            )
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }

        defer {
            try? run("/usr/bin/hdiutil", ["detach", mount.path])
            try? FileManager.default.removeItem(at: diskImage)
        }

        do {
            let mountedApp = mount.appendingPathComponent("MacSpaces.app", isDirectory: true)
            let info = Bundle(url: mountedApp)
            guard info?.bundleIdentifier == expectedBundleIdentifier else {
                throw UpdateError.invalidBundle
            }
            try run("/usr/bin/codesign", ["--verify", "--deep", "--strict", mountedApp.path])
            let incomingTeam = signingTeam(at: mountedApp)
            guard let incomingTeam,
                  incomingTeam == signingTeam(at: installedApp) else {
                throw UpdateError.invalidSignature
            }
            try FileManager.default.copyItem(at: mountedApp, to: staged)
            return StagedUpdate(root: root, app: staged)
        } catch {
            try? FileManager.default.removeItem(at: root)
            throw error
        }
    }

    private func scheduleReplacement(with stagedApp: URL, cleaning root: URL) throws {
        let destination = Bundle.main.bundleURL
        guard destination.path.hasPrefix("/Applications/") else {
            throw UpdateError.notInstalled
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        destination=\(shellQuote(destination.path))
        staged=\(shellQuote(stagedApp.path))
        staging_root=\(shellQuote(root.path))
        incoming="${destination}.incoming"
        backup="${destination}.previous"
        /bin/rm -rf "$incoming" "$backup"
        /usr/bin/ditto "$staged" "$incoming" || { /bin/rm -rf "$staging_root"; exit 1; }
        /bin/mv "$destination" "$backup" || { /bin/rm -rf "$incoming" "$staging_root"; exit 1; }
        /bin/mv "$incoming" "$destination" || { /bin/mv "$backup" "$destination"; /bin/rm -rf "$staging_root"; exit 1; }
        /bin/rm -rf "$backup" "$staging_root"
        /usr/bin/open "$destination"
        """
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", script]
        try process.run()
    }

    /// Returns nil for unsigned and ad-hoc signed bundles. `codesign` reports
    /// those as `TeamIdentifier=not set`, which would otherwise compare equal
    /// between two ad-hoc builds and pass the identity check.
    nonisolated private static func signingTeam(at app: URL) -> String? {
        guard let output = try? output(
            "/usr/bin/codesign",
            ["-dv", "--verbose=4", app.path]
        ) else { return nil }
        let team = output
            .split(separator: "\n")
            .first(where: { $0.hasPrefix("TeamIdentifier=") })?
            .split(separator: "=", maxSplits: 1)
            .last
            .map { String($0).trimmingCharacters(in: .whitespaces) }
        guard let team, !team.isEmpty, team != "not set" else { return nil }
        return team
    }

    private static func isTrustedDownload(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else { return false }
        return allowedDownloadHosts.contains(host)
    }

    nonisolated private static func run(_ executable: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed
        }
    }

    nonisolated private static func output(_ executable: String, _ arguments: [String]) throws -> String {
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw UpdateError.commandFailed
        }
        return String(data: data, encoding: .utf8) ?? ""
    }

    private func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    private var currentVersion: String {
        Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String ?? "0"
    }

    private func isNewer(_ candidate: String, than installed: String) -> Bool {
        candidate.compare(installed, options: .numeric) == .orderedDescending
    }

    private func notifyAvailable(_ version: String) {
        let content = UNMutableNotificationContent()
        content.title = "MacSpaces \(version)"
        content.body = automaticallyInstallUpdates
            ? "Downloading the update. You'll be asked before it installs."
            : "Open About to install the update."
        let request = UNNotificationRequest(
            identifier: "macspaces-update-\(version)",
            content: content,
            trigger: nil
        )
        let center = UNUserNotificationCenter.current()
        center.getNotificationSettings { settings in
            switch settings.authorizationStatus {
            case .authorized, .provisional, .ephemeral:
                center.add(request)
            case .notDetermined:
                center.requestAuthorization(options: [.alert]) { granted, _ in
                    if granted {
                        center.add(request)
                    }
                }
            case .denied:
                break
            @unknown default:
                break
            }
        }
    }

    private enum UpdateError: Error {
        case invalidBundle
        case invalidSignature
        case notInstalled
        case commandFailed
    }
}
