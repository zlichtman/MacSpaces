import Foundation

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general, widgets, clipboard, appearance, permissions, activities

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .widgets: return "Widgets"
        case .clipboard: return "Clipboard"
        case .appearance: return "Appearance"
        case .permissions: return "Permissions"
        case .activities: return "Activities"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .widgets: return "square.grid.2x2"
        case .clipboard: return "doc.on.clipboard"
        case .appearance: return "paintpalette"
        case .permissions: return "hand.raised"
        case .activities: return "waveform.path.ecg"
        }
    }
}

struct SettingsSearchEntry: Identifiable {
    let destination: SettingsDestination
    let card: String
    let keywords: String
    var id: String { destination.rawValue + "." + card }
}

enum SettingsSearch {
    static let entries: [SettingsSearchEntry] = [
        .init(destination: .general, card: "Startup", keywords: "enable nook launch at login startup autostart"),
        .init(destination: .general, card: "Displays", keywords: "display monitor screen built in external selection"),
        .init(destination: .general, card: "Open & close", keywords: "hover delay click scroll gestures drag files open tray"),
        .init(destination: .general, card: "Keyboard", keywords: "keyboard hotkey shortcut find action direct page shortcuts"),
        .init(destination: .general, card: "Downloads & folders", keywords: "completed downloads folders watch automatic staging tray"),
        .init(destination: .general, card: "Screenshots", keywords: "add new screenshots screen captures tray"),
        .init(destination: .general, card: "Hide in apps", keywords: "hidden apps hide games frontmost"),
        .init(destination: .general, card: "File Converter", keywords: "shift drag wheel format convert file tools compress metadata finder reveal results"),
        .init(destination: .general, card: "Motion", keywords: "reduce motion animation accessibility trackpad haptics"),
        .init(destination: .general, card: "Reset Nook", keywords: "reset all settings restore defaults widget profiles appearance"),
        .init(destination: .general, card: "Updates", keywords: "version software update download automatically check install"),
        .init(destination: .widgets, card: "Profiles", keywords: "home widget profiles rename icon switch delete"),
        .init(destination: .widgets, card: "Home layout", keywords: "widgets add remove arrange size reorder calculator music clock calendar messages battery weather notes terminal shortcuts timers reminders focus pomodoro dictation keep awake style dot regular places cities 24 hour seconds work break duration"),
        .init(destination: .widgets, card: "Dock", keywords: "app pages dock show hide reorder pin close settings only button controls"),
        .init(destination: .clipboard, card: "History shortcut", keywords: "clipboard history shortcut popup position pointer centre center preview app icons"),
        .init(destination: .clipboard, card: "History", keywords: "clipboard history keep limit sort pins snippets search exact fuzzy regex mixed delete clear quitting"),
        .init(destination: .clipboard, card: "Switching from Maccy", keywords: "import maccy history migration pins"),
        .init(destination: .clipboard, card: "Recording", keywords: "pause recording clipboard text links images files privacy passwords token"),
        .init(destination: .clipboard, card: "Ignore", keywords: "clipboard ignore apps regex patterns pasteboard types only record filter"),
        .init(destination: .appearance, card: "Theme", keywords: "themes appearance light dark system effects animate colors colours custom background accent everforest rainbow synthwave monsoon terminal core bloom forest earth water sky tech"),
        .init(destination: .appearance, card: "Lyrics", keywords: "lyrics lyric styles classic poster choreography stickers karaoke typewriter music"),
        .init(destination: .activities, card: "Live activities", keywords: "now playing music running timer upcoming video meeting power low battery alerts paste queue count screenshot microphone mute focus"),
        .init(destination: .activities, card: "Notifications", keywords: "notifications messages new show text full disk access banner"),
        .init(destination: .activities, card: "Coding agents", keywords: "coding agents claude codex hooks thinking waiting working needs you done"),
        .init(destination: .permissions, card: "Automation", keywords: "permissions privacy access automation"),
        .init(destination: .permissions, card: "Accessibility", keywords: "permissions privacy access accessibility"),
        .init(destination: .permissions, card: "Calendars", keywords: "permissions privacy access calendars"),
        .init(destination: .permissions, card: "Reminders", keywords: "permissions privacy access reminders"),
        .init(destination: .permissions, card: "Camera", keywords: "permissions privacy access camera"),
        .init(destination: .permissions, card: "Location", keywords: "permissions privacy access location"),
        .init(destination: .permissions, card: "Bluetooth", keywords: "permissions privacy access bluetooth"),
        .init(destination: .permissions, card: "Full Disk Access", keywords: "permissions privacy access full disk access"),
        .init(destination: .permissions, card: "Contacts", keywords: "permissions privacy access contacts"),
    ]

    private static func normalized(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .split { !$0.isLetter && !$0.isNumber }.joined(separator: " ")
    }

    static func matches(_ query: String) -> [SettingsSearchEntry] {
        let words = normalized(query).split(separator: " ")
        guard !words.isEmpty else { return [] }
        return entries.filter { entry in
            let text = normalized(entry.destination.title + " " + entry.card + " " + entry.keywords)
            return words.allSatisfy { text.contains($0) }
        }.sorted {
            let a = normalized($0.card).hasPrefix(normalized(query)), b = normalized($1.card).hasPrefix(normalized(query))
            if a != b { return a }
            if $0.destination != $1.destination { return SettingsDestination.allCases.firstIndex(of: $0.destination)! < SettingsDestination.allCases.firstIndex(of: $1.destination)! }
            return $0.card.localizedStandardCompare($1.card) == .orderedAscending
        }
    }
}
