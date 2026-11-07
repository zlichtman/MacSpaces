import Foundation

/// One numbered desktop on a display. Full-screen spaces aren't desktops and have no number.
struct SpaceDesktop: Equatable, Sendable {
    let uuid: String
    /// From 1, in Mission Control's order on its display.
    let number: Int
}

struct SpaceDisplay: Equatable, Sendable {
    /// The display's UUID, or "Main" when all displays share one set of Spaces.
    let identifier: String
    let desktops: [SpaceDesktop]
    /// The desktop showing; nil while a full-screen space shows.
    let current: SpaceDesktop?
    /// Every space's uuid in Mission Control's order, full-screen ones too: moving a space
    /// left or right passes through those.
    var order: [String] = []
    /// The uuid of the space showing, full screen or not.
    var showing: String?
}

/// A display arriving on another desktop.
struct SpaceChange: Equatable, Sendable {
    let display: String
    let desktop: SpaceDesktop
}

/// A key and its modifiers as macOS stores a Mission Control shortcut. The modifiers are
/// `CGEventFlags` bits.
struct SpaceShortcut: Equatable, Sendable {
    let key: UInt16
    let flags: UInt64
}

/// The Mission Control shortcuts that are switched on.
struct SpaceShortcuts: Equatable, Sendable {
    var left: SpaceShortcut?
    var right: SpaceShortcut?
    /// "Switch to Desktop N", by N.
    var desktops: [Int: SpaceShortcut] = [:]
}

/// How to get to a desktop.
enum SpaceJump: Equatable, Sendable {
    /// Already there, or it's gone.
    case nothing
    case press(SpaceShortcut, times: Int)
    case noShortcut
}

/// Pure logic behind `SpacesMonitor`: it reads the window server's dictionaries; this makes
/// sense of them, so the shape is checked without one (`Tests/SpacesChecks.swift`).
enum SpaceLayout {
    /// A desktop's `type` in the window server's list; every other type (4 is full screen)
    /// is left out of the numbering.
    static let desktopType = 0
    static let nameLimit = 20

    /// The ordered desktops per display from `CGSCopyManagedDisplaySpaces`'s answer. Private
    /// data, so anything not shaped as expected gives nil and the feature hides itself.
    static func parse(_ raw: Any?) -> [SpaceDisplay]? {
        guard let entries = raw as? [[String: Any]], !entries.isEmpty else { return nil }
        var displays: [SpaceDisplay] = []
        for entry in entries {
            guard let identifier = entry["Display Identifier"] as? String, !identifier.isEmpty,
                  let spaces = entry["Spaces"] as? [[String: Any]],
                  let showing = entry["Current Space"] as? [String: Any],
                  let currentUUID = showing["uuid"] as? String else { return nil }
            var desktops: [SpaceDesktop] = []
            for space in spaces {
                guard let type = space["type"] as? Int, let uuid = space["uuid"] as? String, !uuid.isEmpty else { return nil }
                if type == desktopType { desktops.append(SpaceDesktop(uuid: uuid, number: desktops.count + 1)) }
            }
            guard !desktops.isEmpty else { return nil }
            displays.append(SpaceDisplay(identifier: identifier, desktops: desktops,
                                         current: desktops.first { $0.uuid == currentUUID },
                                         order: spaces.compactMap { $0["uuid"] as? String }, showing: currentUUID))
        }
        return displays
    }

    /// The entry for a display. A shared set of Spaces ("Main") covers every display; with no
    /// exact match the first entry stands in, so a display not yet listed still shows something.
    static func display(in displays: [SpaceDisplay], matching identifier: String?) -> SpaceDisplay? {
        guard let identifier else { return displays.first }
        return displays.first { $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame } ?? displays.first
    }

    /// Whether the space showing on a display is one of `disabled` (Tape's desktops that are off).
    /// Stricter than `display(in:matching:)`: with no list, or no entry for this display, nothing
    /// is off, so a Mac without the private list keeps working everywhere. "Main" is one shared
    /// set of Spaces and the only entry, so it covers every display.
    static func isShowingDisabled(on identifier: String, in displays: [SpaceDisplay]?, disabled: Set<String>) -> Bool {
        guard let displays, !disabled.isEmpty else { return false }
        let entry = displays.first { $0.identifier.caseInsensitiveCompare(identifier) == .orderedSame }
            ?? (displays.count == 1 && displays[0].identifier == "Main" ? displays[0] : nil)
        return entry?.showing.map(disabled.contains) ?? false
    }

    /// Displays now showing a different desktop. A display new to the list, or one now on
    /// a full-screen space, isn't a change to show; desktops renumbered in place aren't either.
    static func changes(from old: [SpaceDisplay], to new: [SpaceDisplay]) -> [SpaceChange] {
        new.compactMap { display in
            guard let previous = old.first(where: { $0.identifier == display.identifier }),
                  let current = display.current, current.uuid != previous.current?.uuid else { return nil }
            return SpaceChange(display: display.identifier, desktop: current)
        }
    }

    // MARK: - Moving

    /// macOS's ids in `com.apple.symbolichotkeys`.
    private static let moveLeftID = 79, moveRightID = 81, firstDesktopID = 118, desktopIDs = 16
    /// macOS's own ⌃← and ⌃→, which it doesn't write down until they're changed.
    private static let arrowFlags: UInt64 = 0x840000
    private static let leftDefault = SpaceShortcut(key: 123, flags: arrowFlags)
    private static let rightDefault = SpaceShortcut(key: 124, flags: arrowFlags)

    /// Reads `AppleSymbolicHotKeys`. An entry that's missing, or on with no keys, means macOS's
    /// default: on with ⌃← and ⌃→ for moving, off for each desktop.
    static func shortcuts(from raw: Any?) -> SpaceShortcuts {
        let entries = raw as? [String: Any] ?? [:]
        func shortcut(_ id: Int, fallback: SpaceShortcut?) -> SpaceShortcut? {
            guard let entry = entries[String(id)] as? [String: Any] else { return fallback }
            guard (entry["enabled"] as? NSNumber)?.boolValue == true else { return nil }
            guard let value = entry["value"] as? [String: Any],
                  let parameters = value["parameters"] as? [NSNumber], parameters.count == 3 else { return fallback }
            guard let key = UInt16(exactly: parameters[1].intValue), key != .max else { return nil }
            return SpaceShortcut(key: key, flags: parameters[2].uint64Value)
        }
        var result = SpaceShortcuts(left: shortcut(moveLeftID, fallback: leftDefault),
                                    right: shortcut(moveRightID, fallback: rightDefault))
        for number in 1...desktopIDs {
            result.desktops[number] = shortcut(firstDesktopID + number - 1, fallback: nil)
        }
        return result
    }

    /// The desktop's own shortcut when there's one, else steps left or right. "Switch to Desktop
    /// N" numbers desktops across all displays, so with several only the steps can be trusted;
    /// those move the display the pointer is on, which is the one whose dot was clicked.
    static func jump(on display: SpaceDisplay, to desktop: SpaceDesktop, displayCount: Int,
                     shortcuts: SpaceShortcuts) -> SpaceJump {
        guard display.showing != desktop.uuid,
              let target = display.order.firstIndex(of: desktop.uuid),
              let start = display.order.firstIndex(where: { $0 == display.showing }) else { return .nothing }
        if displayCount == 1, let direct = shortcuts.desktops[desktop.number] { return .press(direct, times: 1) }
        guard let step = target > start ? shortcuts.right : shortcuts.left else { return .noShortcut }
        return .press(step, times: abs(target - start))
    }

    // MARK: - Words

    /// "2 · Writing", or just "2" with no name.
    static func label(number: Int, name: String?) -> String {
        guard let name, !name.isEmpty else { return "\(number)" }
        return "\(number) · \(name)"
    }

    /// What's kept of a typed name: one line, trimmed, at most `nameLimit` characters.
    static func cleaned(name: String) -> String {
        let line = name.components(separatedBy: .newlines).joined(separator: " ")
        return String(line.trimmingCharacters(in: .whitespaces).prefix(nameLimit))
            .trimmingCharacters(in: .whitespaces)
    }
}
