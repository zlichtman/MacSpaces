/// Whether MacSpaces turned Focus on for a focus session, and so owes the Off
/// shortcut. Cleanup follows what MacSpaces actually did, not the current
/// preference: turning "Silence during focus" off mid-session, pausing, resetting
/// or finishing still runs Off when MacSpaces had run On.
struct FocusSilencing: Equatable {
    enum Action: Equatable { case on, off }

    /// MacSpaces ran the On shortcut and hasn't run Off since.
    private(set) var turnedOn = false

    /// A work session started (`active`) or stopped.
    mutating func session(active: Bool, silencing: Bool, shortcutsReady: Bool) -> Action? {
        if active {
            guard silencing, shortcutsReady, !turnedOn else { return nil }
            turnedOn = true
            return .on
        }
        return release()
    }

    /// The preference was turned off: undo what MacSpaces turned on.
    mutating func silencingDisabled() -> Action? { release() }

    private mutating func release() -> Action? {
        guard turnedOn else { return nil }
        turnedOn = false
        return .off
    }
}
