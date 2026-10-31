import Foundation

/// The Homebrew tab's reading and commands: `brew info --json=v2 --installed` becomes
/// rows with the right versions and flags, and a button builds only plain commands.
@main
enum HomebrewChecks {
    static func main() {
        let json = #"""
        {"formulae":[
          {"name":"node","full_name":"node","versions":{"stable":"24.11.1"},"revision":0,
           "installed":[{"version":"24.9.0"}],"outdated":true,"pinned":false},
          {"name":"ffmpeg","full_name":"ffmpeg","versions":{"stable":"8.0.1"},"revision":2,
           "installed":[{"version":"8.0_1"}],"outdated":true,"pinned":true},
          {"name":"gh","full_name":"gh","versions":{"stable":"2.83.0"},
           "installed":[{"version":"2.81.0"},{"version":"2.83.0"}],"outdated":false,"pinned":false},
          {"name":"tool","full_name":"someone/tap/tool","versions":{"stable":"1.0"},
           "installed":[{"version":"1.0"}],"outdated":false,"pinned":false},
          {"name":"ghost","full_name":"ghost","versions":{"stable":"1.0"},"installed":[],"outdated":false}
        ],"casks":[
          {"token":"visual-studio-code","full_token":"visual-studio-code","name":["Visual Studio Code"],
           "version":"1.106.1","installed":"1.105.0","outdated":true,"auto_updates":true},
          {"token":"basictex","full_token":"basictex","name":["BasicTeX"],"version":"2026.0301",
           "installed":"2026.0301","outdated":false,"auto_updates":null},
          {"token":"gone","full_token":"gone","name":["Gone"],"version":"2","installed":null,"outdated":false}
        ]}
        """#
        guard let packages = HomebrewCatalog.parse(Data(json.utf8)) else { fatalError("Parses brew info JSON") }
        precondition(packages.map(\.title) == ["BasicTeX", "ffmpeg", "gh", "node", "tool", "Visual Studio Code"],
                     "Installed ones only, by title, casks by their app name")
        let node = packages.first { $0.name == "node" }!
        precondition(node.kind == .formula && node.installed == "24.9.0" && node.latest == "24.11.1" && node.canUpgrade)
        let ffmpeg = packages.first { $0.name == "ffmpeg" }!
        precondition(ffmpeg.latest == "8.0.1_2" && ffmpeg.pinned && !ffmpeg.canUpgrade, "Revisions show; pinned can't upgrade")
        precondition(packages.first { $0.name == "gh" }!.installed == "2.83.0", "The newest keg counts")
        precondition(packages.first { $0.title == "tool" }!.name == "someone/tap/tool", "Tap packages by full name")
        let code = packages.first { $0.kind == .cask && $0.outdated }!
        precondition(code.name == "visual-studio-code" && code.autoUpdates && code.latest == "1.106.1")
        precondition(packages.filter(\.outdated).count == 3)
        precondition(HomebrewCatalog.counts(packages) == "4 formulae · 2 casks")
        precondition(HomebrewCatalog.counts(Array(packages.prefix(1))) == "0 formulae · 1 cask")
        precondition(HomebrewCatalog.parse(Data("not json".utf8)) == nil && HomebrewCatalog.parse(Data("{}".utf8)) == nil)
        precondition(HomebrewCatalog.parse(Data(#"{"formulae":[],"casks":[]}"#.utf8))?.isEmpty == true)

        // Self-updating casks: judged by the app on disk, not Homebrew's stale record.
        let selfUpdating = #"""
        {"casks":[
          {"token":"macspaces","full_token":"zlichtman/tap/macspaces","name":["MacSpaces"],"version":"3.35",
           "installed":"3.28","outdated":true,"auto_updates":true,
           "artifacts":[{"uninstall":[{"quit":"dev.opensource.MacSpaces"}]},{"app":["MacSpaces.app"],"target":"/Applications/MacSpaces.app"}]},
          {"token":"google-chrome","full_token":"google-chrome","name":["Google Chrome"],"version":"142.0.7444.60",
           "installed":"140.0.1","outdated":true,"auto_updates":true,
           "artifacts":[{"app":["Google Chrome.app"],"target":"/Users/me/Applications/Google Chrome.app"}]},
          {"token":"slack","full_token":"slack","name":["Slack"],"version":"4.47.65,arm64",
           "installed":"4.40.0,arm64","outdated":true,"auto_updates":true,"artifacts":[]},
          {"token":"zoom","full_token":"zoom","name":["Zoom"],"version":"6.6.0.1234",
           "installed":"6.0.0.1","outdated":true,"auto_updates":true,"artifacts":[{"pkg":["zoomusInstallerFull.pkg"]}]},
          {"token":"iterm2","full_token":"iterm2","name":["iTerm2"],"version":"3.6.5",
           "installed":"3.5.0","outdated":true,"auto_updates":null,
           "artifacts":[{"app":["iTerm.app"],"target":"/Applications/iTerm.app"}]}
        ]}
        """#
        guard let casks = HomebrewCatalog.parse(Data(selfUpdating.utf8)) else { fatalError("Parses casks with artifacts") }
        let cask = { (name: String, list: [HomebrewPackage]) in list.first { $0.name == name }! }
        precondition(cask("zlichtman/tap/macspaces", casks).appPath == "/Applications/MacSpaces.app", "The app artifact's target")
        precondition(cask("google-chrome", casks).appPath == "/Users/me/Applications/Google Chrome.app")
        precondition(cask("slack", casks).appPath == "/Applications/Slack.app", "No app artifact: /Applications/<name>.app")
        let onDisk = ["/Applications/MacSpaces.app": "3.35", "/Users/me/Applications/Google Chrome.app": "141.0.7390.122",
                      "/Applications/Slack.app": "4.47.65", "/Applications/iTerm.app": "3.6.5"]
        let real = HomebrewCatalog.reconciled(casks) { onDisk[$0] }
        let spaces = cask("zlichtman/tap/macspaces", real)
        precondition(!spaces.outdated && spaces.installed == "3.35" && spaces.latest == "3.35",
                     "A stale record (3.28) with the app already current isn't outdated, and shows the app's version")
        let chrome = cask("google-chrome", real)
        precondition(chrome.outdated && chrome.canUpgrade && chrome.installed == "141.0.7390.122",
                     "An app that really is older stays outdated, showing its real version")
        precondition(!cask("slack", real).outdated && cask("slack", real).installed == "4.47.65", "A cask's ,build part is ignored")
        let zoom = cask("zoom", real)
        precondition(zoom.outdated && zoom.installed == "6.0.0.1", "An app that can't be found keeps Homebrew's record")
        let iterm = cask("iterm2", real)
        precondition(iterm.outdated && iterm.installed == "3.5.0", "Casks that don't update themselves are judged by Homebrew")
        precondition(HomebrewCatalog.reconciled(packages) { _ in "999" } == packages.map { package in
            package.kind == .cask && package.autoUpdates
                ? HomebrewPackage(kind: .cask, name: package.name, title: package.title, installed: "999", latest: package.latest,
                                  outdated: false, pinned: package.pinned, autoUpdates: true, appPath: package.appPath)
                : package
        }, "Only self-updating casks change; formulae never do")
        precondition(HomebrewCatalog.reconciled(packages) { _ in "nightly" } == packages, "A version that won't compare changes nothing")
        let behind = HomebrewPackage(kind: .cask, name: "x", title: "X", installed: "2.0", latest: "2.0", outdated: false,
                                     pinned: false, autoUpdates: true, appPath: "/Applications/X.app")
        precondition(!HomebrewCatalog.reconciled([behind]) { _ in "1.0" }[0].outdated,
                     "Never outdated when Homebrew's record isn't: its upgrade would do nothing")
        precondition(HomebrewCatalog.isOlder("3.34", than: "3.35") == true && HomebrewCatalog.isOlder("3.35", than: "3.35") == false)
        precondition(HomebrewCatalog.isOlder("1.10", than: "1.9") == false && HomebrewCatalog.isOlder("2.0", than: "2.0.0") == false)
        precondition(HomebrewCatalog.isOlder("3.36", than: "3.35") == false, "Newer than the cask isn't outdated")
        precondition(HomebrewCatalog.isOlder("latest", than: "1.0") == nil && HomebrewCatalog.isOlder("1.0", than: "latest") == nil)

        // The version read from a real bundle's Info.plist; a missing app reads nil.
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("homebrew-checks-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: folder) }
        let bundle = folder.appendingPathComponent("Sample.app")
        try! FileManager.default.createDirectory(at: bundle.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        let info = try! PropertyListSerialization.data(fromPropertyList: ["CFBundleShortVersionString": "3.34", "CFBundleVersion": "135"],
                                                       format: .xml, options: 0)
        try! info.write(to: bundle.appendingPathComponent("Contents/Info.plist"))
        precondition(HomebrewCatalog.appVersion(at: bundle.path) == "3.34", "Reads CFBundleShortVersionString")
        precondition(HomebrewCatalog.appVersion(at: folder.appendingPathComponent("Missing.app").path) == nil)

        // Commands: fixed verbs, the package as one plain argument.
        precondition(HomebrewCatalog.arguments(.update) == ["update"])
        precondition(HomebrewCatalog.arguments(.upgradeAll) == ["upgrade"])
        precondition(HomebrewCatalog.arguments(.upgrade(node)) == ["upgrade", "--formula", "node"])
        precondition(HomebrewCatalog.arguments(.upgrade(code)) == ["upgrade", "--cask", "visual-studio-code"])
        precondition(HomebrewCatalog.arguments(.upgrade(packages.first { $0.title == "tool" }!)) == ["upgrade", "--formula", "someone/tap/tool"])
        for bad in ["a;rm -rf ~", "$(x)", "-x", "a b", "", "x`y`", "a'b", "a\nb"] {
            let package = HomebrewPackage(kind: .formula, name: bad, title: bad, installed: "1", latest: "2",
                                          outdated: true, pinned: false, autoUpdates: false)
            precondition(HomebrewCatalog.arguments(.upgrade(package)) == nil, "Refuses \(bad)")
        }
        precondition(HomebrewCatalog.shellLine(.upgrade(code), brew: "/opt/homebrew/bin/brew") == "/opt/homebrew/bin/brew upgrade --cask visual-studio-code")
        precondition(HomebrewCatalog.environment["HOMEBREW_NO_AUTO_UPDATE"] == "1", "Reading and upgrading never update on their own")
        precondition(HomebrewCatalog.listArguments == ["info", "--json=v2", "--installed"])

        // Output.
        precondition(HomebrewCatalog.needsPassword("==> Running installer\nsudo: a terminal is required to read the password"))
        precondition(!HomebrewCatalog.needsPassword("==> Pouring node--24.11.1.bottle.tar.gz"))
        precondition(HomebrewCatalog.lastLine("==> Upgrading 1 package\n  ==> Pouring gh  \n\n") == "==> Pouring gh")
        precondition(HomebrewCatalog.lastLine("") == nil)
        let long = (1...1000).map(String.init).joined(separator: "\n")
        precondition(HomebrewCatalog.trimmed(long).hasPrefix("601\n") && HomebrewCatalog.trimmed("a\nb") == "a\nb", "Keeps the last 400 lines")
        print("Homebrew checks passed: installed formulae and casks with versions, revisions, pins and self-updating casks judged by the app on disk; plain commands only; password and output handling")
    }
}
