import Foundation

@main enum MessageChecks {
    @MainActor static func main() async {
        let a = MessageConversation(id: "chat-a", title: "Same name", participantIDs: ["one"], participantLabels: ["test-one"])
        let b = MessageConversation(id: "chat-b", title: "Same name", participantIDs: ["two"], participantLabels: ["test-two"])
        var state = MessageReplyState()
        precondition(state.select(a)); state.draft = "test"
        precondition(!state.select(b), "A draft must not silently move to another recipient")
        precondition(!state.begin(current: b))
        let changedMembers = MessageConversation(id: a.id, title: a.title, participantIDs: ["one", "new"], participantLabels: ["test-one", "new"])
        precondition(!state.begin(current: changedMembers))
        precondition(state.begin(current: a)); precondition(!state.begin(current: a))
        var restored = try! JSONDecoder().decode(MessageReplyState.self, from: JSONEncoder().encode(state))
        restored.recoverAfterRelaunch(); precondition(restored.phase == .uncertain && restored.draft == "test")
        state.finish(accepted: false)
        precondition(state.phase == .uncertain && state.draft == "test")
        precondition(!state.begin(current: a), "Uncertain delivery cannot be retried")
        state.newDraft(); state.draft = "new explicit reply"
        precondition(state.begin(current: a)); state.finish(accepted: true)
        precondition(state.draft.isEmpty && state.phase == .submitted)
        for source in [MessagesScripts.discovery, MessagesScripts.reply] {
            var error: NSDictionary?
            precondition(NSAppleScript(source: source)?.compileAndReturnError(&error) == true, "Messages script does not compile: \(String(describing: error))")
        }
        let payload = "\"\\\n tell application \"Finder\" to quit"
        let result: AppleScriptRunner.Result = await withCheckedContinuation { continuation in
            AppleScriptRunner.runHandler("on echoValue(value)\nreturn value\nend echoValue", name: "echoValue", arguments: [.text(payload)]) { continuation.resume(returning: $0) }
        }
        precondition(!result.failed && result.descriptor?.stringValue == payload, "Text must remain data, not AppleScript source")
        print("Messages checks passed: recipient identity, changed participants, repeated clicks, uncertain sends, draft retention, script compilation and safe argument transport. No messages sent.")
    }
}
