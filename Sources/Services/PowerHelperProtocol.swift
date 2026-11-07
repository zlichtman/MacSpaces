import Foundation

/// The XPC contract between MacSpaces and its privileged power helper
/// (`Helpers/PowerHelper`), compiled into both. The helper does exactly four things,
/// each running `/usr/bin/pmset -a disablesleep` or `-a lowpowermode` with fixed
/// arguments; nothing the app sends is a path, string or command. Each reply is
/// pmset's exit status.
@objc protocol PowerHelperProtocol {
    /// `pmset -a disablesleep 1`: the Mac keeps running with its lid closed.
    func preventSleep(withReply reply: @escaping (Int32) -> Void)
    /// `pmset -a disablesleep 0`: normal sleep.
    func allowSleep(withReply reply: @escaping (Int32) -> Void)
    /// `pmset -a lowpowermode 1`: Low Power Mode on.
    func enableLowPowerMode(withReply reply: @escaping (Int32) -> Void)
    /// `pmset -a lowpowermode 0`: Low Power Mode off.
    func disableLowPowerMode(withReply reply: @escaping (Int32) -> Void)
}

enum PowerHelperXPC {
    /// The launchd label and Mach service (`Contents/Library/LaunchDaemons/<label>.plist`).
    static let label = "dev.opensource.MacSpaces.PowerHelper"
    static let plistName = label + ".plist"
    static let appBundleIdentifier = "dev.opensource.MacSpaces"
    static let teamIdentifier = "28LJG7MXT3"

    /// What the helper demands of every client: MacSpaces itself, signed by this team.
    static let clientRequirement =
        "anchor apple generic and identifier \"\(appBundleIdentifier)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
    /// What MacSpaces demands of the helper it talks to.
    static let helperRequirement =
        "anchor apple generic and identifier \"\(label)\" and certificate leaf[subject.OU] = \"\(teamIdentifier)\""
}
