import Foundation

@main struct SettingsSearchChecks {
    static func main() {
        precondition(SettingsSearch.matches(" \n -- ").isEmpty)
        precondition(SettingsSearch.matches("ÁSCII ART").first?.card == "Music Player")
        precondition(SettingsSearch.matches("hover delay").first?.destination == .general)
        precondition(SettingsSearch.matches("pin close").first?.card == "Dock")
        precondition(SettingsSearch.matches("pin close").first?.destination == .dock, "Dock settings live on the Dock page")
        precondition(SettingsSearch.matches("coding agents").first?.card == "Coding agents")
        precondition(SettingsSearch.matches("agent bubble").first?.card == "Coding agents", "The agent pop-out is findable")
        precondition(SettingsSearch.matches("screenshots").first?.destination == .folio)
        precondition(SettingsSearch.matches("clipboard regex").contains { $0.card == "History" && $0.destination == .folio })
        precondition(SettingsSearch.matches("camera access").first?.card == "Camera")
        precondition(SettingsSearch.matches("launch-at-login").first?.card == "Startup")
        precondition(SettingsSearch.matches("wisp").map(\.card).prefix(2) == ["Wisp", "Dock"], "Wisp's own card, then the dock that turns it on")
        precondition(SettingsSearch.matches("claude api key").first?.card == "Wisp", "Wisp's model and API key are findable")
        precondition(SettingsSearch.matches("unavailable setting xyzzy").isEmpty)
        precondition(SettingsSearch.matches("lyrics").first?.card == "Music Player" && SettingsSearch.matches("lyrics").first?.destination == .heartable)
        precondition(SettingsSearch.matches("album covers").first?.card == "Music Player", "The local-files covers are in the Music Player card")
        precondition(SettingsSearch.matches("reduce motion").isEmpty && SettingsSearch.matches("haptics").isEmpty, "Motion settings are gone")
        precondition(SettingsDestination.allCases.filter { $0.section == "Tools" } == [.heartable, .tape, .tsukumo, .folio], "Tools is only the apps")
        precondition(SettingsSearch.matches("spotify").first?.destination == .heartable && SettingsSearch.matches("swipe").first?.card == "Swipe")
        precondition(SettingsSearch.matches("kemosabe").first?.card == "Agent", "KemoSabe's swap is findable")
        precondition(SettingsSearch.matches("clone voice recordings").first?.card == "Voice", "Voices from recordings are findable")
        precondition(SettingsSearch.matches("closed notch").first?.destination == .activities)
        precondition(Set(SettingsSearch.entries.map(\.id)).count == SettingsSearch.entries.count)
        precondition(Set(SettingsSearch.entries.map(\.destination)) == Set(SettingsDestination.allCases))
        precondition(SettingsSearch.matches("tape").first?.card == "Status" && SettingsSearch.matches("tape").first?.destination == .tape, "Tape's switch comes first")
        precondition(SettingsSearch.matches("window gap").first?.card == "Layout" && SettingsSearch.matches("window gap").first?.destination == .tape)
        precondition(SettingsSearch.matches("tape keyboard").first?.card == "Keyboard" && SettingsSearch.matches("tape keyboard").first?.destination == .tape)
        precondition(SettingsSearch.matches("tape desktop").first?.card == "Desktops")
        precondition(SettingsSearch.matches("managed apps").first?.destination == .tape)
        precondition(SettingsSearch.matches("trackpad").first?.destination == .tape)
        precondition(SettingsSearch.matches("stage manager").first?.card == "Mac Setup and log")
        for card in ["Status", "Desktops", "Displays", "Layout", "Managed Apps", "Managed Windows", "Keyboard", "Trackpad", "Mac Setup and log"] {
            precondition(SettingsSearch.entries.contains { $0.destination == .tape && $0.card == card }, "Every Tape card is indexed: " + card)
        }
        print("Settings search checks passed: multi-word queries, punctuation, accents, ranking, permission routes, Tape's cards and all ten destinations")
    }
}
