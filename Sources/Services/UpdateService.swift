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
            case .available: return "A MacSpaces update is available"
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
        let body: String?
        let draft: Bool
        let prerelease: Bool
        let assets: [Asset]

        private enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case body, draft, prerelease, assets
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

    @Published var countsInstall: Bool {
        didSet {
            UserDefaults.standard.set(countsInstall, forKey: Self.countKey)
            // Turning it on counts this Mac now rather than at the next hourly check.
            if countsInstall, !oldValue { countIfDue() }
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
    /// Anonymous install count: on sends a random ID and the version to macspaces.dev with the update
    /// checks (at launch and hourly) and after an update. On unless turned off in Settings.
    static let countKey = "updates.countInstall"
    private static let installIDKey = "updates.installID"
    private static let lastCountKey = "updates.lastCount"
    private static let lastCountVersionKey = "updates.lastCountVersion"
    private static let countEndpoint = URL(string: "https://macspaces.dev/api/ping")!
    /// A build this Mac can't run (too-new macOS or missing architecture), so
    /// it isn't downloaded again on every check.
    private static let incompatibleBuildKey = "updates.incompatibleBuild"
    /// Stable (1.x) installs read releases/latest, which never returns a
    /// pre-release. Pre-release (2.x) installs read the release list and take
    /// the newest build with their own major version.
    private var endpoint: URL {
        URL(string: followsPrereleases
            ? "https://api.github.com/repos/zlichtman/MacSpaces/releases?per_page=30"
            : "https://api.github.com/repos/zlichtman/MacSpaces/releases/latest")!
    }

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
    private var availableBuild: Int?
    private var periodicCheck: Timer?
    /// A build whose install failed and why: automatic checks leave it alone until relaunch
    /// instead of downloading it again every hour; Check Now still tries.
    private var failedInstall: (build: Int, message: String)?
    private static let notInstalledMessage = "Move MacSpaces to Applications, then install the update"

    /// Installing replaces the app in /Applications; a copy run from the disk image, Downloads
    /// or a translocated path can't be replaced.
    private static var isInApplications: Bool { Bundle.main.bundleURL.path.hasPrefix("/Applications/") }

    private init() {
        // Updates download on their own by default so everyone stays on the
        // newest build; it installs once the Mac is idle and the Nook is closed, without asking.
        UserDefaults.standard.register(defaults: [
            Self.automaticKey: true,
            Self.automaticCheckKey: true,
            // On unless turned off: a copy that never touched the switch counts too.
            Self.countKey: true,
        ])
        automaticallyInstallUpdates = UserDefaults.standard.bool(forKey: Self.automaticKey)
        automaticallyCheckForUpdates = UserDefaults.standard.bool(forKey: Self.automaticCheckKey)
        countsInstall = UserDefaults.standard.bool(forKey: Self.countKey)
    }

    /// The anonymous ping: a random install ID made once on this Mac and the version, nothing else.
    /// Fire and forget; the answer is ignored and a failure is tried again at the next check.
    private func countIfDue() {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: Self.countKey), Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        // With every update check (hourly, and at launch) and at once after an update: the site keeps
        // install IDs in a set, so repeats never count twice; 50 minutes apart at most so checks that
        // bunch up (launch, wake) send one.
        if let last = defaults.object(forKey: Self.lastCountKey) as? Date, Date().timeIntervalSince(last) < 50 * 60,
           defaults.string(forKey: Self.lastCountVersionKey) == currentVersion { return }
        let id = defaults.string(forKey: Self.installIDKey) ?? {
            let made = UUID().uuidString.lowercased()
            defaults.set(made, forKey: Self.installIDKey)
            return made
        }()
        var request = URLRequest(url: Self.countEndpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: ["id": id, "version": currentVersion])
        defaults.set(Date(), forKey: Self.lastCountKey)
        defaults.set(currentVersion, forKey: Self.lastCountVersionKey)
        URLSession.shared.dataTask(with: request) { _, _, _ in }.resume()
    }

    /// Pre-release builds carry MacSpacesDevelopmentBuild and update from the
    /// release list (newest same-major release) instead of releases/latest.
    var followsPrereleases: Bool {
        Bundle.main.object(forInfoDictionaryKey: "MacSpacesDevelopmentBuild") as? Bool == true
    }

    func start() {
        // Isolated QA and demo builds never update themselves.
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(8))
            checkIfDue()
            // Counted at launch even when the last update check was under an hour ago.
            countIfDue()
        }
        // A menu-bar app runs for days, so checking only at launch would miss
        // releases published while it's open.
        periodicCheck?.invalidate()
        periodicCheck = Timer(timeInterval: 15 * 60, repeats: true) { _ in
            Task { @MainActor in UpdateService.shared.checkIfDue() }
        }
        // Common modes keep it firing while a menu is open or a drag is tracking.
        RunLoop.main.add(periodicCheck!, forMode: .common)
        // Waking from sleep is when a release is most likely to have been missed.
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            Task { @MainActor in UpdateService.shared.checkIfDue(soon: true) }
        }
    }

    /// Hourly (it used to be every six hours, so a release could take most of a day to show);
    /// `soon` (waking from sleep) checks once ten minutes have passed. GitHub
    /// allows 60 unauthenticated checks an hour, far above this.
    func checkIfDue(soon: Bool = false) {
        guard Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces", automaticallyCheckForUpdates else { return }
        // An offered or downloaded update, or one on its way, needs no new check.
        guard !hasPendingUpdate, !isBusy else { return }
        let last = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        let gap: TimeInterval = soon ? 10 * 60 : 60 * 60
        guard last == nil || Date().timeIntervalSince(last!) > gap else { return }
        check(manual: false)
    }

    func check(manual: Bool = true) {
        guard task == nil, !isBusy else { return }
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
                if error == nil { self.countIfDue() }
                guard error == nil, let data,
                      let selected = self.selectRelease(from: data) else {
                    self.status = manual
                        ? .failed("Couldn’t check for updates")
                        : .idle
                    return
                }
                let (release, version, build) = selected
                let skipped = UserDefaults.standard.integer(forKey: Self.incompatibleBuildKey)
                guard ReleaseRevision.isNewer(build, than: max(self.currentBuild, skipped)) else {
                    self.availableDownloadURL = nil
                    self.availableVersion = nil
                    self.availableBuild = nil
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
                // The same failure would repeat, with a download and a notification each hour.
                if !manual, let failed = self.failedInstall, failed.build == build {
                    self.status = .failed(failed.message)
                    return
                }

                self.availableDownloadURL = asset.browserDownloadURL
                self.availableVersion = version
                self.availableBuild = build
                self.status = .available(version)
                self.notifyAvailable(version)
                if self.automaticallyInstallUpdates {
                    self.downloadAndInstall(asset.browserDownloadURL, version: version, build: build)
                }
            }
        }
        task?.resume()
    }

    /// The release to offer and its public version and build. The public
    /// version comes from the tag; the downloaded app must match it and the
    /// build marker before it can install.
    private func selectRelease(from data: Data) -> (Release, String, Int)? {
        let decoder = JSONDecoder()
        if followsPrereleases {
            guard let releases = try? decoder.decode([Release].self, from: data),
                  let major = ReleaseRevision.major(of: currentVersion) else { return nil }
            let candidates = releases.map {
                ReleaseRevision.Candidate(tag: $0.tagName, body: $0.body, draft: $0.draft, prerelease: $0.prerelease)
            }
            guard let choice = ReleaseRevision.newest(in: candidates, major: major) else { return nil }
            return (releases[choice.index], choice.version, choice.build)
        }
        guard let release = try? decoder.decode(Release.self, from: data),
              !release.draft, !release.prerelease,
              let version = ReleaseRevision.version(fromTag: release.tagName),
              let build = ReleaseRevision.build(in: release.body) else { return nil }
        return (release, version, build)
    }

    var actionLabel: String {
        switch status {
        case .available: return "Install"
        default: return "Check Now"
        }
    }

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing:
            return true
        default:
            return false
        }
    }

    /// An update is offered and waiting for Install (automatic installs are off).
    var hasPendingUpdate: Bool {
        if case .available = status { return true }
        return false
    }

    func performPrimaryAction() {
        if case .available = status,
           let availableDownloadURL,
           let availableVersion,
           let availableBuild {
            downloadAndInstall(availableDownloadURL, version: availableVersion, build: availableBuild)
        } else {
            check()
        }
    }

    /// Downloads, verifies and installs at once, relaunching MacSpaces: automatic updates don't
    /// wait or ask (owner).
    private func downloadAndInstall(_ url: URL, version: String, build: Int) {
        availableDownloadURL = nil
        availableVersion = nil
        availableBuild = nil
        // Checked before downloading: the copy can't be replaced, so the download would be wasted.
        guard Self.isInApplications else {
            failInstall(build, Self.notInstalledMessage)
            return
        }
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
                    self.install(retained, version: version, build: build, source: url)
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

    private func install(_ diskImage: URL, version: String, build: Int, source: URL) {
        status = .installing(version)
        let bundleIdentifier = Bundle.main.bundleIdentifier
        let installedApp = Bundle.main.bundleURL

        Task {
            // Mounting, verifying and copying a few hundred megabytes takes
            // seconds. Run it off the main actor so the UI stays responsive.
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try Self.stageVerifiedApp(
                        from: diskImage,
                        expectedBundleIdentifier: bundleIdentifier,
                        expectedVersion: version,
                        expectedBuild: build,
                        matching: installedApp
                    )
                }
            }.value

            guard case let .success(staged) = result else {
                if case let .failure(error) = result, case UpdateError.incompatible? = error as? UpdateError {
                    UserDefaults.standard.set(build, forKey: Self.incompatibleBuildKey)
                    status = .failed("MacSpaces \(version) doesn’t support this Mac")
                } else {
                    failInstall(build, "Update verification failed")
                }
                try? FileManager.default.removeItem(at: diskImage)
                return
            }


            do {
                try scheduleReplacement(with: staged.app, cleaning: staged.root)
                NSApp.terminate(nil)
            } catch UpdateError.notInstalled {
                // Running from the disk image, Downloads or a translocated copy.
                failInstall(build, Self.notInstalledMessage)
                try? FileManager.default.removeItem(at: staged.root)
            } catch {
                failInstall(build, "Couldn’t install the update")
                try? FileManager.default.removeItem(at: staged.root)
            }
        }
    }

    private func failInstall(_ build: Int, _ message: String) {
        failedInstall = (build, message)
        status = .failed(message)
    }

    private struct StagedUpdate: Sendable {
        let root: URL
        let app: URL
    }

    nonisolated private static func stageVerifiedApp(
        from diskImage: URL,
        expectedBundleIdentifier: String?,
        expectedVersion: String,
        expectedBuild: Int,
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
            guard info?.bundleIdentifier == expectedBundleIdentifier,
                  info?.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String == expectedVersion,
                  let buildString = info?.object(forInfoDictionaryKey: "CFBundleVersion") as? String,
                  Int(buildString) == expectedBuild else {
                throw UpdateError.invalidBundle
            }
            guard let info, canRun(info) else { throw UpdateError.incompatible }
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
        guard Self.isInApplications else {
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

    /// Whether this Mac can run the downloaded app: its minimum macOS and an
    /// executable slice for this process's architecture.
    nonisolated private static func canRun(_ app: Bundle) -> Bool {
        if let minimum = app.object(forInfoDictionaryKey: "LSMinimumSystemVersion") as? String {
            let parts = minimum.split(separator: ".").map { Int($0) ?? 0 }
            let required = OperatingSystemVersion(
                majorVersion: parts.first ?? 0,
                minorVersion: parts.count > 1 ? parts[1] : 0,
                patchVersion: parts.count > 2 ? parts[2] : 0
            )
            guard ProcessInfo.processInfo.isOperatingSystemAtLeast(required) else { return false }
        }
        #if arch(x86_64)
        let architecture = NSBundleExecutableArchitectureX86_64
        #else
        let architecture = NSBundleExecutableArchitectureARM64
        #endif
        return app.executableArchitectures?.contains(NSNumber(value: architecture)) == true
    }

    /// Returns nil for unsigned and ad-hoc signed bundles. `codesign` reports
    /// those as `TeamIdentifier=not set`, which would otherwise compare equal
    /// between two ad-hoc builds and pass the identity check.
    nonisolated private static func signingTeam(at app: URL) -> String? {
        guard let output = try? output(
            "/usr/bin/codesign",
            ["-dv", "--verbose=4", app.path]
        ) else { return nil }
        return ReleaseRevision.signingTeam(fromCodesignOutput: output)
    }

    private static func isTrustedDownload(_ url: URL) -> Bool { ReleaseRevision.isTrustedDownload(url) }

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

    private var currentBuild: Int {
        Int(Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "") ?? 0
    }

    /// Posts only when notifications are already allowed: a background check never asks for the
    /// permission, which comes only from an explicit action.
    private func notifyAvailable(_ version: String) {
        let content = UNMutableNotificationContent()
        content.title = "MacSpaces \(version)"
        content.body = !Self.isInApplications
            ? "Move MacSpaces to Applications to install the update."
            : automaticallyInstallUpdates
            ? "Installing the update. MacSpaces reopens on its own."
            : "Open Settings → General to install the update."
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
            default:
                break
            }
        }
    }

    private enum UpdateError: Error {
        case invalidBundle
        case invalidSignature
        case incompatible
        case notInstalled
        case commandFailed
    }
}
