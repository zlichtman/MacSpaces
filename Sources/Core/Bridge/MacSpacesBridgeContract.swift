import Foundation

/// Public, versioned wire contract. Contains no Tsukumo implementation or model configuration.
enum MacSpacesBridge {
    static let version = 1
    static let maxBytes = 128 * 1024
    static let serverRequirement = "anchor apple generic and identifier \"com.zlichtman.kemosabe.mac\" and certificate leaf[subject.OU] = \"28LJG7MXT3\""
    static let clientRequirement = "anchor apple generic and identifier \"dev.opensource.MacSpaces\" and certificate leaf[subject.OU] = \"28LJG7MXT3\""
    static var endpointURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/MacSpacesBridge/endpoint")
    }
    enum Operation: String, Codable { case discover, submit, status, cancel, open }
    struct Request: Codable {
        var version = MacSpacesBridge.version
        var id = UUID()
        var operation: Operation
        var conversation: UUID?
        var prompt: String?
        func validate() throws {
            guard version == MacSpacesBridge.version else { throw Failure("Update both apps to use the same bridge version.") }
            if operation != .discover && conversation == nil { throw Failure("Choose a conversation first.") }
            if operation == .submit {
                guard let prompt, !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                      prompt.utf8.count <= 64 * 1024 else { throw Failure("Enter a prompt of up to 64 KiB.") }
            }
        }
    }
    struct Conversation: Codable, Identifiable, Equatable {
        var id: UUID
        var title: String
        var status: String
        var canSubmit: Bool
        var canCancel: Bool
    }
    struct Response: Codable {
        var version = MacSpacesBridge.version
        var conversations: [Conversation] = []
        var status: String?
        var error: String?
    }
    struct Failure: LocalizedError {
        var message: String
        init(_ message: String) { self.message = message }
        var errorDescription: String? { message }
    }
}
