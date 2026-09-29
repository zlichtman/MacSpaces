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
        print("Update checks passed: versions, replacement, current, older and malformed releases")
    }
}
