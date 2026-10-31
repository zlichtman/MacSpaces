import Foundation

/// One installed Homebrew package, as the Terminal page's Homebrew tab lists it.
struct HomebrewPackage: Identifiable, Equatable, Sendable {
    enum Kind: String, Sendable { case formula, cask }
    let kind: Kind
    /// What Homebrew calls it in commands (a tap's packages by their full name).
    let name: String
    /// What the tab shows: a cask's app name, otherwise the name.
    let title: String
    let installed: String
    /// The version Homebrew's lists have now.
    let latest: String
    let outdated: Bool
    let pinned: Bool
    /// A cask whose app updates itself (Homebrew leaves it alone unless asked).
    let autoUpdates: Bool
    /// A cask's installed app: its app artifact's target, else /Applications/<title>.app.
    var appPath: String? = nil
    var id: String { "\(kind.rawValue):\(name)" }
    /// Has an Upgrade button: outdated and not pinned.
    var canUpgrade: Bool { outdated && !pinned }
}

/// Reading Homebrew and building its commands, pure so the checks cover it. The tab
/// reads `brew info --json=v2 --installed` with auto-update off, so listing never goes
/// online; only the Update and Upgrade buttons do.
enum HomebrewCatalog {
    /// Where `brew` lives on Apple silicon and on Intel Macs.
    static let candidates = ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
    static let listArguments = ["info", "--json=v2", "--installed"]
    /// Upgrades use the lists the last Update fetched, so they match what the tab showed.
    static let environment = ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1",
                              "HOMEBREW_NO_COLOR": "1", "HOMEBREW_NO_EMOJI": "1"]

    /// The installed packages in `brew info --json=v2 --installed`, by title; nil when
    /// it isn't that JSON.
    static func parse(_ data: Data) -> [HomebrewPackage]? {
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let formulae = root["formulae"] as? [[String: Any]]
        let casks = root["casks"] as? [[String: Any]]
        guard formulae != nil || casks != nil else { return nil }
        var packages: [HomebrewPackage] = []
        for item in formulae ?? [] {
            guard let name = item["full_name"] as? String ?? item["name"] as? String else { continue }
            let kegs = (item["installed"] as? [[String: Any]] ?? []).compactMap { $0["version"] as? String }
            guard let installed = kegs.last else { continue }
            let versions = item["versions"] as? [String: Any]
            var latest = versions?["stable"] as? String ?? installed
            if let revision = item["revision"] as? Int, revision > 0 { latest += "_\(revision)" }
            packages.append(HomebrewPackage(kind: .formula, name: name, title: item["name"] as? String ?? name,
                                            installed: installed, latest: latest,
                                            outdated: item["outdated"] as? Bool ?? false,
                                            pinned: item["pinned"] as? Bool ?? false, autoUpdates: false))
        }
        for item in casks ?? [] {
            guard let name = item["full_token"] as? String ?? item["token"] as? String,
                  let installed = item["installed"] as? String else { continue }
            let title = (item["name"] as? [String])?.first ?? item["token"] as? String ?? name
            packages.append(HomebrewPackage(kind: .cask, name: name, title: title, installed: installed,
                                            latest: item["version"] as? String ?? installed,
                                            outdated: item["outdated"] as? Bool ?? false,
                                            pinned: item["pinned"] as? Bool ?? false,
                                            autoUpdates: item["auto_updates"] as? Bool ?? false,
                                            appPath: appPath(item["artifacts"]) ?? "/Applications/\(title).app"))
        }
        return packages.sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    /// The first app artifact's installed path: `{"app": ["X.app"], "target": "/Applications/X.app"}`,
    /// or a relative name or target under /Applications.
    static func appPath(_ artifacts: Any?) -> String? {
        for artifact in artifacts as? [[String: Any]] ?? [] {
            guard let app = artifact["app"] as? [Any] else { continue }
            let renamed = app.compactMap { ($0 as? [String: Any])?["target"] as? String }.first
            guard let path = artifact["target"] as? String ?? renamed ?? app.first as? String else { continue }
            let expanded = (path as NSString).expandingTildeInPath
            return expanded.hasPrefix("/") ? expanded : "/Applications/" + expanded
        }
        return nil
    }

    /// Self-updating casks judged by the app on disk, not Homebrew's record of what it last
    /// installed (which goes stale once the app updates itself, so Homebrew offers an update
    /// that's already there). Where the app's version reads, it shows as installed, and the
    /// cask stays outdated only if that app is older than the cask's version. Homebrew's
    /// record still has to call it outdated, or its upgrade would do nothing. Formulae, other
    /// casks and apps that can't be found or compared are left as Homebrew says.
    static func reconciled(_ packages: [HomebrewPackage], appVersion: (String) -> String?) -> [HomebrewPackage] {
        packages.map { package in
            guard package.kind == .cask, package.autoUpdates, let path = package.appPath,
                  let real = appVersion(path), let older = isOlder(real, than: package.latest) else { return package }
            return HomebrewPackage(kind: package.kind, name: package.name, title: package.title, installed: real,
                                   latest: package.latest, outdated: package.outdated && older,
                                   pinned: package.pinned, autoUpdates: true, appPath: path)
        }
    }

    /// An app bundle's `CFBundleShortVersionString`, read from its Info.plist (call off the main thread).
    static func appVersion(at path: String) -> String? {
        let plist = URL(fileURLWithPath: path).appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: plist),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let version = (info["CFBundleShortVersionString"] as? String)?.trimmingCharacters(in: .whitespaces),
              !version.isEmpty else { return nil }
        return version
    }

    /// Whether `version` is older than `latest`, comparing dotted numbers (a cask's ",build" part
    /// ignored, missing parts as 0); nil when either has no leading number to compare.
    static func isOlder(_ version: String, than latest: String) -> Bool? {
        func numbers(_ text: String) -> [Int] {
            let main = text.split(separator: ",").first.map(String.init) ?? ""
            var result: [Int] = []
            for part in main.split(separator: ".", omittingEmptySubsequences: false) {
                guard let number = Int(part.prefix { $0.isASCII && $0.isNumber }) else { break }
                result.append(number)
            }
            return result
        }
        let have = numbers(version), want = numbers(latest)
        guard !have.isEmpty, !want.isEmpty else { return nil }
        for index in 0..<max(have.count, want.count) {
            let a = index < have.count ? have[index] : 0, b = index < want.count ? want[index] : 0
            if a != b { return a < b }
        }
        return false
    }

    /// What the buttons run.
    enum Command: Equatable, Sendable {
        /// `brew update`: fetch Homebrew's package lists.
        case update
        /// `brew upgrade`: everything outdated (pinned ones stay).
        case upgradeAll
        /// `brew upgrade --formula|--cask <name>`.
        case upgrade(HomebrewPackage)

        var title: String {
            switch self {
            case .update: return "Updating Homebrew's lists"
            case .upgradeAll: return "Upgrading everything outdated"
            case .upgrade(let package): return "Upgrading \(package.title)"
            }
        }
    }

    /// The arguments after `brew`, or nil for a name that isn't a plain package name.
    static func arguments(_ command: Command) -> [String]? {
        switch command {
        case .update: return ["update"]
        case .upgradeAll: return ["upgrade"]
        case .upgrade(let package):
            guard isPlainName(package.name) else { return nil }
            return ["upgrade", package.kind == .cask ? "--cask" : "--formula", package.name]
        }
    }

    /// The same command typed into the Terminal page's shell, for one that asks for a password.
    static func shellLine(_ command: Command, brew: String) -> String? {
        guard let arguments = arguments(command), isPlainName(brew) else { return nil }
        return ([brew] + arguments).joined(separator: " ")
    }

    /// Letters, digits and the punctuation Homebrew names and paths use; nothing a shell reads.
    static func isPlainName(_ name: String) -> Bool {
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789@+._-/")
        return !name.isEmpty && !name.hasPrefix("-") && name.allSatisfy { allowed.contains($0) }
    }

    /// A run that stopped because something (usually a cask's installer) wanted sudo.
    static func needsPassword(_ log: String) -> Bool {
        let lower = log.lowercased()
        return lower.contains("sudo: a terminal is required") || lower.contains("sudo: a password is required")
            || lower.contains("no askpass program")
    }

    /// "186 formulae · 58 casks".
    static func counts(_ packages: [HomebrewPackage]) -> String {
        let formulae = packages.filter { $0.kind == .formula }.count, casks = packages.count - formulae
        return "\(formulae) \(formulae == 1 ? "formula" : "formulae") · \(casks) \(casks == 1 ? "cask" : "casks")"
    }

    /// Keeps the last `limit` lines of a running command's output.
    static func trimmed(_ log: String, limit: Int = 400) -> String {
        let lines = log.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count > limit else { return log }
        return lines.suffix(limit).joined(separator: "\n")
    }

    /// The last line worth showing in the running strip ("==> Pouring gh…").
    static func lastLine(_ log: String) -> String? {
        log.split(separator: "\n").last { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            .map { String($0).trimmingCharacters(in: .whitespaces) }
    }
}
