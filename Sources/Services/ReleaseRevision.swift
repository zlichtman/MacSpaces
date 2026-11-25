import Foundation

/// Releases carry a public version in their tag (v1.0.0) and an internal build
/// marker in their notes. The build decides whether an update is newer, so a
/// replacement installer for the same version still reaches existing installs.
enum ReleaseRevision {
    /// Downloads come only over https from GitHub's release hosts.
    static let allowedDownloadHosts: Set<String> = [
        "github.com",
        "objects.githubusercontent.com",
        "release-assets.githubusercontent.com",
    ]

    static func isTrustedDownload(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else { return false }
        return allowedDownloadHosts.contains(host)
    }

    /// The team in `codesign -dv --verbose=4` output, or nil when there is none: an ad-hoc
    /// build says "TeamIdentifier=not set", and two of those must never count as the same team.
    static func signingTeam(fromCodesignOutput output: String) -> String? {
        let prefix = "TeamIdentifier="
        // The text after the prefix, which may be empty ("TeamIdentifier=" alone isn't a team).
        let team = output
            .split(separator: "\n")
            .first(where: { $0.hasPrefix(prefix) })
            .map { String($0.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces) }
        guard let team, !team.isEmpty, team != "not set" else { return nil }
        return team
    }

    /// "v1.0.0" or "1.0.0" become "1.0.0"; anything else is rejected.
    static func version(fromTag tag: String) -> String? {
        let version = tag.hasPrefix("v") || tag.hasPrefix("V") ? String(tag.dropFirst()) : tag
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.count <= 4 && $0.allSatisfy { $0.isASCII && $0.isNumber } })
        else { return nil }
        return version
    }

    static func build(in body: String?) -> Int? {
        guard let body else { return nil }
        let markers = body.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.hasPrefix("<!-- macspaces-build:") }
        // Ambiguous or malformed metadata must never offer an arbitrary build.
        guard markers.count == 1, let marker = markers.first,
              marker.hasSuffix(" -->") else { return nil }
        let digits = marker.dropFirst("<!-- macspaces-build:".count).dropLast(" -->".count)
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }),
              let build = Int(digits), build > 0 else { return nil }
        return build
    }

    static func isNewer(_ candidate: Int, than installed: Int) -> Bool {
        candidate > 0 && candidate > installed
    }

    /// The launch argument the swap script passes when it reopens the copy in place after an
    /// install that failed: the build that didn't install. It arrives in the launch's argument
    /// domain and is never stored.
    static let failedBuildArgument = "updates.failedBuild"

    /// The script that swaps the staged update in once MacSpaces (`pid`) has quit, then reopens
    /// it. MacSpaces is gone by then, so every way this can fail ends by reopening the copy in
    /// place, told which build didn't install (`failedBuildArgument`); it used to exit and leave
    /// MacSpaces closed. `opener` is /usr/bin/open; the checks pass a stand-in.
    static func swapScript(pid: Int32, destination: String, staged: String, stagingRoot: String, build: Int,
                           opener: String = "/usr/bin/open") -> String {
        """
        while kill -0 \(pid) 2>/dev/null; do sleep 0.2; done
        destination=\(shellQuote(destination))
        staged=\(shellQuote(staged))
        staging_root=\(shellQuote(stagingRoot))
        opener=\(shellQuote(opener))
        incoming="${destination}.incoming"
        backup="${destination}.previous"
        fail() {
          /bin/rm -rf "$incoming" "$staging_root"
          "$opener" "$destination" --args -\(failedBuildArgument) \(build)
          exit 1
        }
        /bin/rm -rf "$incoming" "$backup"
        /usr/bin/ditto "$staged" "$incoming" || fail
        /bin/mv "$destination" "$backup" || fail
        /bin/mv "$incoming" "$destination" || { /bin/mv "$backup" "$destination"; fail; }
        /bin/rm -rf "$backup" "$staging_root"
        "$opener" "$destination"
        """
    }

    static func shellQuote(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "'\\''"))'"
    }

    /// The major version of a public version ("2.35" is 2).
    static func major(of version: String) -> Int? {
        version.split(separator: ".").first.flatMap { Int($0) }
    }

    struct Candidate: Equatable {
        let tag: String
        let body: String?
        let draft: Bool
        let prerelease: Bool
    }

    struct Choice: Equatable {
        let index: Int
        let version: String
        let build: Int
    }

    /// Pre-release installs (2.x) follow their own major version: the newest
    /// published release with the same major, whether or not it is still
    /// marked pre-release. Other majors never qualify, so 2.x is never offered
    /// 1.x or a future 3.x that may need a newer Mac. Releases with a missing
    /// or ambiguous build marker are skipped.
    static func newest(in releases: [Candidate], major: Int) -> Choice? {
        var best: Choice?
        for (index, release) in releases.enumerated() where !release.draft {
            guard let version = version(fromTag: release.tag),
                  self.major(of: version) == major,
                  let build = build(in: release.body) else { continue }
            if best == nil || build > best!.build {
                best = Choice(index: index, version: version, build: build)
            }
        }
        return best
    }
}
