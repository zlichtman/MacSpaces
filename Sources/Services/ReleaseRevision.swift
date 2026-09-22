import Foundation

/// The public release stays at 1.0.0. Only the internal build advances.
enum ReleaseRevision {
    static let version = "1.0.0"

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
