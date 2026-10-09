import Foundation

@main struct SettingsSearchChecks {
    static func main() {
        precondition(SettingsSearch.matches(" \n -- ").isEmpty)
        precondition(SettingsSearch.matches("RÉDUCE MOTION").first?.card == "Motion")
        precondition(SettingsSearch.matches("hover delay").first?.destination == .general)
        precondition(SettingsSearch.matches("pin close").first?.card == "Dock")
        precondition(SettingsSearch.matches("clipboard regex").contains { $0.card == "History" && $0.destination == .clipboard })
        precondition(SettingsSearch.matches("camera access").first?.card == "Camera")
        precondition(SettingsSearch.matches("launch-at-login").first?.card == "Startup")
        precondition(SettingsSearch.matches("unavailable setting xyzzy").isEmpty)
        precondition(SettingsSearch.matches("lyrics").first?.card == "Lyrics")
        precondition(Set(SettingsSearch.entries.map(\.id)).count == SettingsSearch.entries.count)
        precondition(Set(SettingsSearch.entries.map(\.destination)) == Set(SettingsDestination.allCases))
        print("Settings search checks passed: multi-word queries, punctuation, accents, ranking, permission routes and all six destinations")
    }
}
