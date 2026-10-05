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
        print("Update checks passed: versions, replacement, current, older and malformed releases, pre-release channel")
    }
}
