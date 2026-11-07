/// The Nook steps away while one of the apps chosen in Settings
/// (`NookSettings.hiddenInApps`) is frontmost, including the app that is already
/// frontmost when MacSpaces starts or rebuilds its windows.
enum HiddenApps {
    static func hides(frontmost bundleID: String?, hiddenIn apps: [String]) -> Bool {
        guard let bundleID, !bundleID.isEmpty else { return false }
        return apps.contains(bundleID)
    }
}
