import Foundation

final class TapeLog {
    static let shared = TapeLog()
    private let queue = DispatchQueue(label: "dev.opensource.MacSpaces.tape.log")
    let url: URL
    private init() {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("MacSpaces/Tape", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        url = folder.appendingPathComponent("Tape.log")
    }
    func write(_ message: String) {
        queue.async { [self] in
            let manager = FileManager.default
            if let attributes = try? manager.attributesOfItem(atPath: url.path),
               (attributes[.size] as? NSNumber)?.intValue ?? 0 > 256_000 {
                let previous = url.appendingPathExtension("previous")
                try? manager.removeItem(at: previous)
                try? manager.moveItem(at: url, to: previous)
            }
            if !manager.fileExists(atPath: url.path) {
                manager.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600])
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data("\(Date().ISO8601Format()) \(message)\n".utf8))
        }
    }
}
