import Foundation

/// A reply from a model behind Wisp that isn't Apple's: what to say, and the plain requests
/// it asked Wisp to carry out. The model asks with lines of their own, such as
/// `DO: remind me to call Sam tomorrow`, and Wisp runs each through `WispCommand`.
struct WispReply: Equatable {
    let text: String
    let actions: [String]

    static func parse(_ raw: String) -> WispReply {
        var said: [String] = [], actions: [String] = []
        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "`*-•"))
                .trimmingCharacters(in: .whitespaces)
            if trimmed.uppercased().hasPrefix("DO:") {
                let request = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                if !request.isEmpty { actions.append(request) }
            } else if !trimmed.isEmpty {
                said.append(line.trimmingCharacters(in: .whitespaces))
            }
        }
        return WispReply(text: said.joined(separator: " "), actions: actions)
    }
}
