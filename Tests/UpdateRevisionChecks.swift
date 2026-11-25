import Foundation

@main
struct UpdateRevisionChecks {
    static func main() {
        let body = "Current release notes.\n\n<!-- macspaces-build:6 -->\n"
        let revision = ReleaseRevision.build(in: body)!
        precondition(ReleaseRevision.version(fromTag: "v1.1") == "1.1")
        precondition(ReleaseRevision.version(fromTag: "v1.0.0") == "1.0.0")
        precondition(ReleaseRevision.version(fromTag: "2.0") == "2.0")
        for invalid in ["", "v", "v1.", "v.1", "v1.1.1.1", "v1.1-beta", "latest", "v1..1", "v12345.0"] {
            precondition(ReleaseRevision.version(fromTag: invalid) == nil, invalid)
        }
        precondition(ReleaseRevision.isNewer(revision, than: 5), "Same public version must still update")
        precondition(!ReleaseRevision.isNewer(revision, than: 6), "Don't reinstall the current build")
        precondition(!ReleaseRevision.isNewer(revision, than: 7), "Don't downgrade a newer build")
        precondition(ReleaseRevision.isNewer(7, than: revision), "The next replacement must update")
        for invalid in [nil, "", "<!-- macspaces-build:0 -->", "<!-- macspaces-build:-1 -->",
                        "<!-- macspaces-build:6", "<!-- macspaces-build:6.0 -->",
                        "<!-- macspaces-build:99999999999999999999999999999 -->",
                        "<!-- macspaces-build:6 -->\n<!-- macspaces-build:7 -->"] {
            precondition(ReleaseRevision.build(in: invalid) == nil)
        }

        // Pre-release channel: newest build within the installed major only.
        func release(_ tag: String, _ build: Int?, draft: Bool = false, prerelease: Bool = true) -> ReleaseRevision.Candidate {
            .init(tag: tag, body: build.map { "Notes\n<!-- macspaces-build:\($0) -->" }, draft: draft, prerelease: prerelease)
        }
        let feed = [release("v2.34", 34), release("v1.14", 14, prerelease: false), release("v2.36", 36, draft: true),
                    release("v3.40", 40), release("v2.35", 35), release("v2.33", 33), release("v2.99", nil)]
        precondition(ReleaseRevision.major(of: "2.35") == 2 && ReleaseRevision.major(of: "1.0.0") == 1)
        precondition(ReleaseRevision.newest(in: feed, major: 2) == .init(index: 4, version: "2.35", build: 35),
                     "Newest 2.x wins; drafts, other majors and unmarked releases are skipped")
        precondition(ReleaseRevision.newest(in: feed, major: 1)?.build == 14)
        precondition(ReleaseRevision.newest(in: [release("v2.40", 40, prerelease: false)], major: 2)?.build == 40,
                     "A 2.x that becomes stable still reaches 2.x installs")
        precondition(ReleaseRevision.newest(in: [], major: 2) == nil)
        precondition(ReleaseRevision.newest(in: [release("v3.1", 50)], major: 2) == nil)
        // What the updater trusts: https from GitHub's release hosts, and a real signing team.
        precondition(ReleaseRevision.isTrustedDownload(URL(string: "https://github.com/zlichtman/MacSpaces/releases/download/v3.2/MacSpaces.dmg")!))
        precondition(ReleaseRevision.isTrustedDownload(URL(string: "HTTPS://Release-Assets.GitHubUserContent.com/x")!))
        precondition(!ReleaseRevision.isTrustedDownload(URL(string: "http://github.com/x.dmg")!), "plain http is refused")
        precondition(!ReleaseRevision.isTrustedDownload(URL(string: "https://github.com.evil.example/x.dmg")!), "look-alike hosts are refused")
        precondition(!ReleaseRevision.isTrustedDownload(URL(string: "https://evil.example/github.com/x.dmg")!))
        precondition(!ReleaseRevision.isTrustedDownload(URL(string: "file:///Users/x/MacSpaces.dmg")!))
        let signed = "Executable=/Applications/MacSpaces.app/Contents/MacOS/MacSpaces\nAuthority=Developer ID Application: Zach Lichtman (28LJG7MXT3)\nTeamIdentifier=28LJG7MXT3\nSealed Resources version=2"
        precondition(ReleaseRevision.signingTeam(fromCodesignOutput: signed) == "28LJG7MXT3")
        precondition(ReleaseRevision.signingTeam(fromCodesignOutput: "Signature=adhoc\nTeamIdentifier=not set") == nil, "ad-hoc builds have no team")
        precondition(ReleaseRevision.signingTeam(fromCodesignOutput: "TeamIdentifier=\n") == nil)
        precondition(ReleaseRevision.signingTeam(fromCodesignOutput: "code object is not signed at all") == nil)
        swap()
        print("Update checks passed: versions, replacement, current, older and malformed releases, pre-release channel, trusted download hosts, signing teams and the swap script")
    }

    /// Runs the swap script the app ships, for real, in a temporary folder: only the paths and
    /// the opener (a stand-in for /usr/bin/open that records how it was called) differ. The
    /// folder's name has a space and an apostrophe, so the quoting is exercised. MacSpaces has
    /// quit by the time this script runs, so each failure must end with the old copy reopened.
    static func swap() {
        let files = FileManager.default
        let base = files.temporaryDirectory.appendingPathComponent("MacSpaces swap check's \(UUID().uuidString)", isDirectory: true)
        try! files.createDirectory(at: base, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: base) }
        let opener = base.appendingPathComponent("opener.sh")
        let opened = base.appendingPathComponent("opened")
        try! "#!/bin/sh\nprintf '%s\\n' \"$@\" > \"$(dirname \"$0\")/opened\"\n".write(to: opener, atomically: true, encoding: .utf8)
        try! files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: opener.path)
        // A process that has already exited, as MacSpaces has when the script gets past its wait.
        let gone = Process()
        gone.executableURL = URL(fileURLWithPath: "/usr/bin/true")
        try! gone.run()
        gone.waitUntilExit()

        struct Case { let folder, app, root, staged: URL }
        func stage(_ name: String, installed: Bool = true, staged hasStaged: Bool = true) -> Case {
            let folder = base.appendingPathComponent("\(name)/Applications", isDirectory: true)
            let root = base.appendingPathComponent("\(name)/Staging", isDirectory: true)
            let made = Case(folder: folder, app: folder.appendingPathComponent("MacSpaces.app", isDirectory: true), root: root,
                            staged: root.appendingPathComponent("MacSpaces.app", isDirectory: true))
            for (bundle, version) in (installed ? [(made.app, "old")] : []) + (hasStaged ? [(made.staged, "new")] : []) {
                try! files.createDirectory(at: bundle, withIntermediateDirectories: true)
                try! version.write(to: bundle.appendingPathComponent("version"), atomically: true, encoding: .utf8)
            }
            for made in [folder, root] { try! files.createDirectory(at: made, withIntermediateDirectories: true) }
            try? files.removeItem(at: opened)
            return made
        }
        /// The script's exit status, with a time limit so a mistake can't hang a check run.
        func run(_ made: Case) -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", ReleaseRevision.swapScript(pid: gone.processIdentifier, destination: made.app.path, staged: made.staged.path,
                                                                  stagingRoot: made.root.path, build: 7, opener: opener.path)]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            let done = DispatchSemaphore(value: 0)
            process.terminationHandler = { _ in done.signal() }
            try! process.run()
            if done.wait(timeout: .now() + 20) == .timedOut {
                process.terminate()
                preconditionFailure("The swap script didn't finish")
            }
            return process.terminationStatus
        }
        func version(_ made: Case) -> String? { try? String(contentsOf: made.app.appendingPathComponent("version"), encoding: .utf8) }
        func calls() -> [String] { ((try? String(contentsOf: opened, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init) }
        func leftovers(_ made: Case) -> [String] {
            ((try? files.contentsOfDirectory(atPath: made.folder.path)) ?? []).filter { $0 != "MacSpaces.app" }
        }
        let reopenedOld = { (made: Case) in [made.app.path, "--args", "-updates.failedBuild", "7"] }

        // It works: the new copy is in place, nothing is left beside it, and it opens with no note.
        let fine = stage("fine")
        precondition(run(fine) == 0 && version(fine) == "new", "the staged copy replaces the installed one")
        precondition(leftovers(fine).isEmpty && !files.fileExists(atPath: fine.root.path), "no backup, incoming copy or staging folder is left")
        precondition(calls() == [fine.app.path], "a good install opens the new copy with no failure note")

        // The staged copy is missing, so the copy fails before anything moved.
        let missing = stage("missing", staged: false)
        precondition(run(missing) == 1 && version(missing) == "old", "a failed copy leaves the installed app alone")
        precondition(leftovers(missing).isEmpty && !files.fileExists(atPath: missing.root.path))
        precondition(calls() == reopenedOld(missing), "after a failed copy the installed app reopens, told which build failed")

        // The installed app is gone, so the copy lands beside it and the first move fails: the one
        // failure that has an incoming copy to clear away.
        let moved = stage("moved", installed: false)
        precondition(run(moved) == 1 && version(moved) == nil)
        precondition(leftovers(moved).isEmpty && !files.fileExists(atPath: moved.root.path), "a failed move clears the incoming copy and the staging folder")
        precondition(calls() == reopenedOld(moved), "a failed move still ends with the opener, told which build failed")

        // An account without admin rights: the folder can't be written to. (Root still could.)
        if getuid() != 0 {
            let locked = stage("locked")
            try! files.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.folder.path)
            defer { try? files.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.folder.path) }
            precondition(run(locked) == 1 && version(locked) == "old", "a folder that can't be written to leaves the installed app alone")
            precondition(leftovers(locked).isEmpty && !files.fileExists(atPath: locked.root.path))
            precondition(calls() == reopenedOld(locked), "the installed app reopens when its folder can't be written to")
        }
    }
}
