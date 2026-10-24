import Foundation

/// Where a notification that comes through the notch takes you. A new message
/// opens the Messages page on its conversation and an agent that needs you opens
/// the Terminal page's Agents tab on that session, unless the Nook is in use or
/// cards were chosen; then a card shows, and clicking it goes to the same place.
/// Other apps' notifications are always cards; clicking one opens the matching
/// page, or the app. Nothing shows while the Mac is locked or a "hide in" app is
/// in front: an agent's card waits for that to end, the rest are dropped.
enum NotificationRoute: Equatable {
    /// Open the Nook there now.
    case open(Destination)
    case card
    /// Keep it until the Mac is unlocked or the hiding app leaves the front.
    case hold
    case drop

    enum Kind: Equatable {
        case message(chat: String)
        case agent(session: String)
        case app(bundleID: String)
    }

    enum Destination: Equatable {
        /// The Messages page on that conversation (empty: the inbox).
        case messages(chat: String)
        /// The Terminal page's Agents tab, showing that session.
        case agents(session: String)
        /// Another Nook page, by its `NotchTab` raw value.
        case page(String)
        /// No page for it: the app itself.
        case app(bundleID: String)
    }

    /// Settings → Activities → Under the notch.
    enum Delivery: String, CaseIterable, Identifiable {
        case openPage, card
        var id: String { rawValue }
        var title: String { self == .openPage ? "Open its page" : "Show a card" }
    }

    struct Context: Equatable {
        var delivery: Delivery = .openPage
        /// A Nook is running that can open a page.
        var nookAvailable = true
        /// Someone is using the open Nook (`NotchViewModel.isInUse`): never move it.
        var nookInUse = false
        var hiddenForApp = false
        var locked = false
    }

    /// What happens when a notification arrives.
    static func incoming(_ kind: Kind, persistent: Bool, in context: Context) -> NotificationRoute {
        if context.locked || context.hiddenForApp { return persistent ? .hold : .drop }
        if case .app = kind { return .card }
        guard context.delivery == .openPage, context.nookAvailable, !context.nookInUse else { return .card }
        return .open(destination(for: kind))
    }

    /// Where clicking its card goes (and where `incoming` opens it).
    static func destination(for kind: Kind) -> Destination {
        switch kind {
        case .message(let chat): return .messages(chat: chat)
        case .agent(let session): return .agents(session: session)
        case .app(let bundleID):
            guard let page = page(forApp: bundleID) else { return .app(bundleID: bundleID) }
            return page == "messages" ? .messages(chat: "") : .page(page)
        }
    }

    /// The Nook page that shows what an app's notification is about.
    static func page(forApp bundleID: String) -> String? {
        switch bundleID.lowercased() {
        case "com.apple.mobilesms": return "messages"
        case "com.apple.ical": return "calendar"
        case "com.apple.reminders": return "reminders"
        case "com.apple.notes": return "notes"
        case "com.apple.weather": return "weather"
        case "com.apple.music": return "music"
        case "com.apple.clock": return "clock"
        default: return nil
        }
    }
}
