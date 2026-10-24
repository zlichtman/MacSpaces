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
        // Drafts stay with the chat they were typed for (audit 2.75 #1).
        var drafts = ChatDrafts()
        drafts.set("for A", for: "chat-a")
        precondition(drafts.text(for: "chat-b").isEmpty, "Selecting another chat must not carry A's draft")
        drafts.set("for B", for: "chat-b")
        precondition(drafts.text(for: "chat-a") == "for A" && drafts.text(for: "chat-b") == "for B")
        drafts.set("for A, more", for: "chat-a")
        drafts.clear("chat-a", ifStill: "for A")
        precondition(drafts.text(for: "chat-a") == "for A, more", "Text typed during a send is kept")
        drafts.clear("chat-b", ifStill: "for B")
        precondition(drafts.text(for: "chat-b").isEmpty && drafts.text(for: nil).isEmpty)

        // The inbox outlives one display's page and rejects late reads (#7, #8).
        var session = InboxSession()
        let left = UUID(), right = UUID()
        precondition(session.attach(left) && !session.attach(right), "Only the first page starts the inbox")
        let older = session.beginRead()!, newer = session.beginRead()!
        precondition(!session.detach(left) && session.isActive, "Closing one display's page must not stop the other")
        precondition(session.accept(newer) && !session.accept(older), "An older read must not replace a newer one")
        let late = session.beginRead()!
        precondition(session.detach(right) && !session.isActive, "The last page stops the inbox")
        precondition(!session.accept(late) && !session.isCurrent(late), "A read finishing after close is rejected")
        precondition(session.beginRead() == nil)
        _ = session.attach(left)
        precondition(!session.accept(late), "A read from an earlier session is rejected after reopening")
        precondition(session.accept(session.beginRead()!))

        // Notifications take you to what they're about, never moving a Nook in use.
        let free = NotificationRoute.Context()
        precondition(NotificationRoute.incoming(.message(chat: "chat-a"), persistent: false, in: free) == .open(.messages(chat: "chat-a")),
                     "A new message opens its conversation, docked or not")
        precondition(NotificationRoute.incoming(.agent(session: "s1"), persistent: true, in: free) == .open(.agents(session: "s1")))
        var busy = free; busy.nookInUse = true
        precondition(NotificationRoute.incoming(.message(chat: "chat-a"), persistent: false, in: busy) == .card, "A Nook in use is never taken")
        precondition(NotificationRoute.incoming(.agent(session: "s1"), persistent: true, in: busy) == .card)
        var cards = free; cards.delivery = .card
        precondition(NotificationRoute.incoming(.message(chat: "chat-a"), persistent: false, in: cards) == .card)
        var noNook = free; noNook.nookAvailable = false
        precondition(NotificationRoute.incoming(.agent(session: "s1"), persistent: true, in: noNook) == .card)
        precondition(NotificationRoute.incoming(.app(bundleID: "com.apple.iCal"), persistent: false, in: free) == .card,
                     "Other apps' notifications never open the Nook by themselves")
        for hidden in [true, false] {
            var away = free; if hidden { away.hiddenForApp = true } else { away.locked = true }
            precondition(NotificationRoute.incoming(.message(chat: "chat-a"), persistent: false, in: away) == .drop, "Nothing shows while locked or hidden")
            precondition(NotificationRoute.incoming(.app(bundleID: "com.example"), persistent: false, in: away) == .drop)
            precondition(NotificationRoute.incoming(.agent(session: "s1"), persistent: true, in: away) == .hold, "A waiting agent comes back later")
        }
        // Clicking a card goes to the same place; other apps open their page or the app.
        precondition(NotificationRoute.destination(for: .message(chat: "chat-b")) == .messages(chat: "chat-b"))
        precondition(NotificationRoute.destination(for: .agent(session: "s2")) == .agents(session: "s2"))
        precondition(NotificationRoute.destination(for: .app(bundleID: "com.apple.MobileSMS")) == .messages(chat: ""))
        precondition(NotificationRoute.destination(for: .app(bundleID: "com.apple.iCal")) == .page("calendar"))
        precondition(NotificationRoute.destination(for: .app(bundleID: "com.example.chat")) == .app(bundleID: "com.example.chat"))
        precondition(NotificationRoute.Delivery(rawValue: "openPage") == .openPage && NotificationRoute.Delivery(rawValue: "card") == .card,
                     "The saved delivery choice keeps its raw values")

        print("Messages checks passed: notification routing (open page vs card, Nook in use, locked/hidden, card destinations), recipient identity, changed participants, repeated clicks, uncertain sends, draft retention, per-chat drafts, inbox consumers and stale reads, script compilation and safe argument transport. No messages sent.")
    }
}
