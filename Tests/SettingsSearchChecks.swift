import Foundation

@main struct SettingsSearchChecks {
    static func main() {
        precondition(SettingsSearch.matches(" \n -- ").isEmpty)
        precondition(SettingsSearch.matches("RÉDUCE MOTION").first?.card == "Motion")
        precondition(SettingsSearch.matches("hover delay").first?.destination == .general)
        precondition(SettingsSearch.matches("pin close").first?.card == "Dock")
        precondition(SettingsSearch.matches("pin close").first?.destination == .apps, "Dock settings live on the Apps page")
        precondition(SettingsSearch.matches("coding agents").first?.card == "Beside the notch")
        precondition(SettingsSearch.matches("agent bubble").first?.card == "Beside the notch", "The agent pop-out is findable")
        precondition(SettingsSearch.matches("screenshots").first?.destination == .files)
        precondition(SettingsSearch.matches("clipboard regex").contains { $0.card == "History" && $0.destination == .clipboard })
        precondition(SettingsSearch.matches("camera access").first?.card == "Camera")
        precondition(SettingsSearch.matches("launch-at-login").first?.card == "Startup")
        precondition(SettingsSearch.matches("wisp").map(\.card).prefix(2) == ["Wisp", "Dock"], "Wisp's own card, then the dock that turns it on")
        precondition(SettingsSearch.matches("claude api key").first?.card == "Wisp", "Wisp's model and API key are findable")
        precondition(SettingsSearch.matches("unavailable setting xyzzy").isEmpty)
        precondition(SettingsSearch.matches("lyrics").first?.card == "Lyrics" && SettingsSearch.matches("lyrics").first?.destination == .appearance)
        precondition(Set(SettingsSearch.entries.map(\.id)).count == SettingsSearch.entries.count)
        precondition(Set(SettingsSearch.entries.map(\.destination)) == Set(SettingsDestination.allCases))
        print("Settings search checks passed: multi-word queries, punctuation, accents, ranking, permission routes and all eight destinations")
    }
}
