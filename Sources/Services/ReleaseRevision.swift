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
