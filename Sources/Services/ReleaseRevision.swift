import Foundation

/// Releases carry a public version in their tag (v1.1) and an internal build
/// marker in their notes. The build decides whether an update is newer, so a
/// replacement installer for the same version still reaches existing installs.
enum ReleaseRevision {
    /// "v1.1" or "1.1.0" become "1.1" / "1.1.0"; anything else is rejected.
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
}
