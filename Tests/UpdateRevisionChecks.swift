import Foundation

@main
struct UpdateRevisionChecks {
    static func main() {
        let body = "Current release notes.\n\n<!-- macspaces-build:6 -->\n"
        let revision = ReleaseRevision.build(in: body)!
        precondition(ReleaseRevision.version == "1.0.0")
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
        print("Update checks passed: replacement, current, older and malformed releases")
    }
}
