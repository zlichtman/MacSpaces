import Foundation

/// What the on-device agent (Wisp or KemoSabe) may tell Claude, Codex or another service
/// (Settings › Tsukumo, the agent's card). It shares by judgement: what macOS lets it read
/// (Calendar, Reminders), unless the owner's written rules say otherwise (`GatewayJudge`, and the
/// plain rules the old menus became, `GatewayPlainRule`). Every answer that leaves shows in the
/// chat, and Ask me before sharing holds each one for Share or Don't share. Apple's model, on this
/// Mac, is never limited by these: they decide only what crosses to another service.
enum GatewayShare {
    /// The owner's rules in plain words, applied to every answer.
    static var rules: String {
        get { GatewayJudge.cleaned(UserDefaults.standard.string(forKey: WidgetOptions.Keys.gatewayRules) ?? "") }
        set { UserDefaults.standard.set(newValue, forKey: WidgetOptions.Keys.gatewayRules) }
    }

    /// The plain rules among them, decided in code.
    static var plainRules: Set<GatewayPlainRule> { GatewayPlainRule.found(in: rules) }

    /// Ask me before sharing: each answer that passes the rules waits in the chat for Share or
    /// Don't share (`GatewayApproval`). Off, answers go as soon as they pass.
    static var askFirst: Bool {
        get { UserDefaults.standard.bool(forKey: WidgetOptions.Keys.gatewayAskFirst) }
        set { UserDefaults.standard.set(newValue, forKey: WidgetOptions.Keys.gatewayAskFirst) }
    }

    /// Up to 4.01 the Gateway had menus: Calendar (Nothing, When you're free, Your events; unset
    /// followed 3.96's `kemosabe.shareFreeTimes`), Reminders (Nothing, What's due) and Answer other
    /// questions. Once, at launch, an existing install's choices become the plain rules that share
    /// exactly the same (`GatewayPlainRule.migrated`), ahead of its own rules; a new install (no
    /// dock stored yet) starts with none. The old keys are left as they were, so an older MacSpaces
    /// still reads them.
    static func migrateMenus(_ defaults: UserDefaults = .standard, newInstall: Bool) {
        guard !defaults.bool(forKey: WidgetOptions.Keys.gatewayMenusMigrated) else { return }
        defaults.set(true, forKey: WidgetOptions.Keys.gatewayMenusMigrated)
        guard !newInstall else { return }
        let calendar = defaults.string(forKey: WidgetOptions.Keys.gatewayCalendar)
            ?? (defaults.bool(forKey: WidgetOptions.Keys.kemoSabeShareFreeTimes) ? "free" : "nothing")
        let reminders = defaults.string(forKey: WidgetOptions.Keys.gatewayReminders) ?? "nothing"
        let migrated = GatewayPlainRule.migrated(calendar: calendar, reminders: reminders,
                                                 appleAnswers: defaults.bool(forKey: WidgetOptions.Keys.gatewayAppleAnswers))
        guard !migrated.isEmpty else { return }
        defaults.set(GatewayPlainRule.merged(migrated, into: defaults.string(forKey: WidgetOptions.Keys.gatewayRules) ?? ""),
                     forKey: WidgetOptions.Keys.gatewayRules)
    }

    /// The lines a cloud model's instructions use to say what it may ask the agent.
    static func instructionLines(agent: String) -> String {
        let plain = plainRules
        var lines: [String] = []
        if GatewayPlainRule.allows(.free(.init(window: DateInterval(), label: "")), under: plain) { lines.append("ASK: free tonight") }
        if GatewayPlainRule.allows(.events(.init(window: DateInterval(), label: "")), under: plain) { lines.append("ASK: events tomorrow") }
        if GatewayPlainRule.allows(.reminders, under: plain) { lines.append("ASK: reminders due") }
        let facts = GatewayPlainRule.facts(under: plain)
        if GatewayPlainRule.allows(.other(""), under: plain), facts.busy || facts.events || facts.reminders {
            lines.append("ASK: is the user busy with anything on Friday evening?")
        }
        guard !lines.isEmpty else {
            return "You can't see the user's calendar, reminders, messages or notes, and the user hasn't chosen to share any of it, so never guess their schedule."
        }
        return """
            You can't see the user's calendar, reminders, messages or notes. \(agent) reads them on this Mac and \
            tells you only what the user's rules allow. To ask it, reply with nothing but lines like:
            \(lines.joined(separator: "\n"))
            Its answers come back in a message starting "\(agent):". It may not share an answer; then don't ask \
            it again. Ask before saying whether the user can make a time, and never guess their schedule.\
            \(askFirst ? " The user approves each answer and may decline one." : "")
            """
    }
}
