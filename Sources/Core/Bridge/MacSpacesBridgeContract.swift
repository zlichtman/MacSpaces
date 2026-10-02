import Foundation
import CryptoKit
import Darwin

/// Public, versioned wire contract. Contains no Tsukumo implementation or model configuration.
///
/// Version 2 adds, all optional on the wire so version 1 peers keep working:
/// - `create` (a new quick task in an explicit destination the server advertised),
/// - capabilities in discovery replies (destinations, operations, attachment limits),
/// - bounded file attachments staged in the bridge folder, verified by size and SHA-256,
/// - progress fields on conversations, and an explicit `uncertain` outcome.
/// A client sends `discover` as version 1, which every server answers, and uses version 2
/// only when the reply's capabilities say the server speaks it. Servers answer in the
/// request's version.
enum MacSpacesBridge {
    static let version = 2
    static let supportedVersions = 1...2
    static let maxBytes = 128 * 1024
    static let maxPromptBytes = 64 * 1024
    static let serverRequirement = "anchor apple generic and identifier \"com.zlichtman.kemosabe.mac\" and certificate leaf[subject.OU] = \"28LJG7MXT3\""
    static let clientRequirement = "anchor apple generic and identifier \"dev.opensource.MacSpaces\" and certificate leaf[subject.OU] = \"28LJG7MXT3\""
    static var folderURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support/MacSpacesBridge", isDirectory: true)
    }
    static var endpointURL: URL { folderURL.appendingPathComponent("endpoint") }
    /// Files the client stages for one request, in `Outbox/<request UUID>/`. Only the client writes
    /// here; the server reads only the files a request names, for that request's UUID.
    static var outboxURL: URL { folderURL.appendingPathComponent("Outbox", isDirectory: true) }
    enum Operation: String, Codable { case discover, submit, status, cancel, open, create }
    struct Request: Codable {
        var version = MacSpacesBridge.version
        var id = UUID()
        var operation: Operation
        var conversation: UUID?
        var prompt: String?
        /// Version 2, `create` only: a destination ID from the server's capabilities.
        var destination: String?
        /// Version 2, `submit` and `create`: files the person picked, staged for this request.
        var attachments: [Attachment]?
        func validate() throws {
            guard MacSpacesBridge.supportedVersions.contains(version) else { throw Failure("Update both apps to use the same bridge version.") }
            if version < 2, operation == .create || destination != nil || attachments != nil {
                throw Failure("Update both apps to create tasks or attach files.")
            }
            switch operation {
            case .discover: break
            case .create:
                guard let destination, !destination.isEmpty, destination.utf8.count <= 200 else { throw Failure("Choose where the new task goes.") }
            default:
                if conversation == nil { throw Failure("Choose a conversation first.") }
            }
            if operation == .submit || operation == .create {
                guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      prompt.utf8.count <= MacSpacesBridge.maxPromptBytes else { throw Failure("Enter a prompt of up to 64 KiB.") }
                try Attachment.validate(attachments ?? [])
            } else if attachments != nil { throw Failure("Only a task can carry files.") }
        }
    }
    struct Conversation: Codable, Identifiable, Equatable {
        var id: UUID
        var title: String
        var status: String
        var canSubmit: Bool
        var canCancel: Bool
        /// Version 2 (optional): "coding" or "personal".
        var kind: String?
        /// Version 2 (optional): true while Tsukumo waits for the person's approval or answer.
        /// Approval itself happens only in Tsukumo.
        var needsApproval: Bool?
        /// Version 2 (optional): a short, content-free phrase for what's happening ("Running a command").
        var activity: String?
        /// Version 2 (optional): when the conversation last changed.
        var updated: Date?
        /// Version 2 (optional): whether it accepts attachments.
        var acceptsAttachments: Bool?
    }
    /// Where a new quick task can go: a Tsukumo coding project, or a personal KemoSabe chat.
    struct Destination: Codable, Identifiable, Equatable {
        var id: String
        var title: String
        var kind: String
        var acceptsAttachments: Bool
    }
    struct Capabilities: Codable, Equatable {
        /// The highest version the server speaks.
        var version: Int
        /// Operation names, so a later operation never breaks an earlier decoder.
        var operations: [String]
        var destinations: [Destination]
        var maxAttachments: Int
        var maxAttachmentBytes: Int
        func supports(_ operation: Operation) -> Bool { operations.contains(operation.rawValue) }
    }
    struct Response: Codable {
        var version = MacSpacesBridge.version
        var conversations: [Conversation] = []
        var status: String?
        var error: String?
        /// Version 2 (optional): the send may or may not have happened. The client keeps the same
        /// request (same UUID) until the person checks again or deliberately starts a new task.
        var uncertain: Bool?
        /// Version 2 (optional), in discovery replies. Absent from a version 1 server.
        var capabilities: Capabilities?
    }
    struct Failure: LocalizedError {
        var message: String
        /// True when the request may have reached the other app (a write or read failed after connecting).
        var uncertain = false
        init(_ message: String, uncertain: Bool = false) { self.message = message; self.uncertain = uncertain }
        var errorDescription: String? { message }
    }
    /// A file the person picked, copied into the request's outbox folder before sending.
    struct Attachment: Codable, Equatable {
        var name: String
        var size: Int
        var sha256: String
        static let maxCount = 4
        static let maxBytes = 8 * 1024 * 1024
        static let maxTotalBytes = 16 * 1024 * 1024
        static func validate(_ attachments: [Attachment]) throws {
            guard attachments.count <= maxCount else { throw Failure("Attach up to \(maxCount) files.") }
            guard attachments.reduce(0, { $0 + $1.size }) <= maxTotalBytes else { throw Failure("Attachments are limited to 16 MB in total.") }
            var names = Set<String>()
            for file in attachments {
                guard validName(file.name), names.insert(file.name).inserted else { throw Failure("An attachment has an unusable file name.") }
                guard file.size > 0, file.size <= maxBytes else { throw Failure("Each attachment must be under 8 MB.") }
                guard file.sha256.count == 64, file.sha256.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else { throw Failure("An attachment couldn't be verified.") }
            }
        }
        /// A plain file name: no folders, no hidden or special names, no control characters.
        static func validName(_ name: String) -> Bool {
            !name.isEmpty && name.utf8.count <= 200 && !name.hasPrefix(".") && !name.contains("/") && !name.contains(":")
                && !name.unicodeScalars.contains { $0.properties.generalCategory == .control }
        }
        static func folder(for request: UUID, outbox: URL = MacSpacesBridge.outboxURL) -> URL {
            outbox.appendingPathComponent(request.uuidString, isDirectory: true)
        }
        static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
        /// Client side: copies each picked file into the request's outbox folder and describes it.
        static func stage(_ files: [URL], for request: UUID, outbox: URL = MacSpacesBridge.outboxURL) throws -> [Attachment] {
            guard files.count <= maxCount else { throw Failure("Attach up to \(maxCount) files.") }
            let folder = folder(for: request, outbox: outbox)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var staged: [Attachment] = []
            for file in files {
                let values = try file.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
                guard values.isRegularFile == true, let size = values.fileSize, size > 0, size <= maxBytes else { throw Failure("\(file.lastPathComponent) isn't a file under 8 MB.") }
                var name = file.lastPathComponent
                if !validName(name) { name = "Attachment-\(staged.count + 1)" + (file.pathExtension.isEmpty ? "" : "." + file.pathExtension) }
                while staged.contains(where: { $0.name == name }) { name = "\(staged.count + 1)-" + name }
                let data = try Data(contentsOf: file, options: .mappedIfSafe)
                try data.write(to: folder.appendingPathComponent(name), options: .withoutOverwriting)
                staged.append(.init(name: name, size: data.count, sha256: digest(data)))
            }
            try validate(staged)
            return staged
        }
        /// Server side: reads exactly this staged file for this request, refusing links, other
        /// owners, and any size or content change since the request was written.
        func read(for request: UUID, outbox: URL = MacSpacesBridge.outboxURL) throws -> Data {
            guard Attachment.validName(name) else { throw Failure("An attachment has an unusable file name.") }
            let url = Attachment.folder(for: request, outbox: outbox).appendingPathComponent(name)
            var info = stat()
            guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG, info.st_uid == geteuid(), Int(info.st_size) == size else {
                throw Failure("\(name) is no longer available. Attach it again.")
            }
            let data = try Data(contentsOf: url)
            guard data.count == size, Attachment.digest(data) == sha256 else { throw Failure("\(name) changed after it was attached. Attach it again.") }
            return data
        }
    }
}
