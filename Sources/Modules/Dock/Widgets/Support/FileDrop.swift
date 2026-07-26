import Foundation
import UniformTypeIdentifiers

/// Shared drag-and-drop handling for widgets that accept file URLs.
enum FileDrop {
    /// Loads every file URL carried by `providers`, delivering each on the
    /// main actor. Returns whether any provider offered a file URL.
    static func acceptFileURLs(
        from providers: [NSItemProvider],
        receive: @escaping @MainActor (URL) -> Void
    ) -> Bool {
        var accepted = false
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            accepted = true
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                Task { @MainActor in
                    receive(url)
                }
            }
        }
        return accepted
    }
}
