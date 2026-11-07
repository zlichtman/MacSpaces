import Foundation

enum SettingsDestination: String, CaseIterable, Identifiable {
    // Three sections, as macOS sidebars read: Core for the whole app (General, Appearance,
    // Permissions), then the Notch (Home, its Dock, and Activities beside the closed notch), then
    // Tools, which is only the apps inside MacSpaces, each with its own page.
    case general, appearance, permissions, widgets, dock, activities, heartable, tape, tsukumo, folio

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .appearance: return "Appearance"
        case .permissions: return "Permissions"
        case .widgets: return "Home"
        case .dock: return "Dock"
        case .activities: return "Activities"
        case .heartable: return "Heartable"
        case .tape: return "Tape"
        case .tsukumo: return "Tsukumo"
        case .folio: return "Folio"
        }
    }

    var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .appearance: return "paintpalette"
        case .permissions: return "hand.raised"
        case .widgets: return "square.grid.2x2"
        case .dock: return "dock.rectangle"
        case .activities: return "bell.badge"
        // The sidebar and search results draw the apps' own marks instead (`pageIcon`).
        case .heartable: return "heart.fill"
        case .tape: return "rectangle.split.3x1"
        case .tsukumo: return "sparkle"
        case .folio: return "folder"
        }
    }

    /// The sidebar label shown above the first page of a section.
    var section: String {
        switch self {
        case .general, .appearance, .permissions: return "Core"
        case .widgets, .dock, .activities: return "Notch"
        case .heartable, .tape, .tsukumo, .folio: return "Tools"
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
        .init(destination: .folio, card: "Downloads & folders", keywords: "completed downloads folders watch automatic staging tray"),
        .init(destination: .folio, card: "Screenshots", keywords: "add new screenshots screen captures tray"),
        .init(destination: .general, card: "Hide in apps", keywords: "hidden apps hide games frontmost"),
        .init(destination: .folio, card: "File Converter", keywords: "shift drag wheel format convert file tools compress metadata finder reveal results"),
        .init(destination: .general, card: "Reset Nook", keywords: "reset all settings restore defaults widget profiles appearance"),
        .init(destination: .general, card: "Updates", keywords: "version software update download automatically check install"),
        .init(destination: .widgets, card: "Profiles", keywords: "home widget profiles rename icon switch delete"),
        .init(destination: .widgets, card: "Layout", keywords: "widgets add remove arrange reorder spaces desktops calculator music clock calendar battery weather notes terminal shortcuts timers reminders focus pomodoro keep awake"),
        .init(destination: .widgets, card: "Widgets", keywords: "gallery widget library preview drag add"),
        .init(destination: .dock, card: "Dock", keywords: "app pages dock show hide reorder pin close next to settings only button buttons controls wisp assistant on off"),
        .init(destination: .tsukumo, card: "Agent", keywords: "agent character face mascot kemosabe wisp swap who shows tsukumo companion preview"),
        .init(destination: .tsukumo, card: "Creating audio", keywords: "voice voices audio siren speak clone recording coming"),
        .init(destination: .tsukumo, card: "Wisp", keywords: "wisp assistant model api key claude anthropic openai chatgpt codex gemini mistral ollama openrouter apple intelligence answers"),
        .init(destination: .tsukumo, card: "Gateway", keywords: "gateway kemosabe barrier privacy calendar free busy share when you're free claude openai cloud model what leaves tsukumo"),
        .init(destination: .heartable, card: "Spotify", keywords: "spotify music stats backups backup csv export client id developer app connect playlists liked songs"),
        .init(destination: .folio, card: "History shortcut", keywords: "clipboard history shortcut popup position pointer centre center preview app icons"),
        .init(destination: .folio, card: "History", keywords: "clipboard history keep after quitting persistence limit sort pins snippets search exact fuzzy regex mixed delete clear quitting"),
        .init(destination: .folio, card: "Switching from Maccy", keywords: "import maccy history migration pins"),
        .init(destination: .folio, card: "Recording", keywords: "pause recording clipboard text links images files privacy passwords token"),
        .init(destination: .folio, card: "Ignore", keywords: "clipboard ignore apps regex patterns pasteboard types only record filter"),
        .init(destination: .tape, card: "Status", keywords: "tape status window strip arrange windows tile tiling on off switch turn enable accessibility quit separate app"),
        .init(destination: .tape, card: "Desktops", keywords: "tape window strip per desktop desktops spaces mission control on off name names rename each"),
        .init(destination: .tape, card: "Displays", keywords: "tape window strip monitors screens enable disable external independent strips"),
        .init(destination: .tape, card: "Layout", keywords: "tape window strip gap edge spacing centre center centring focused column width presets third half full resize together stacks tabs join instantly animation"),
        .init(destination: .tape, card: "Managed Apps", keywords: "tape window strip apps applications include exclude select choose rule manage"),
        .init(destination: .tape, card: "Managed Windows", keywords: "tape window strip individual include exclude checked floating scope manage"),
        .init(destination: .tape, card: "Keyboard", keywords: "tape window strip shortcuts hotkeys keys bindings focus move float unavailable"),
        .init(destination: .tape, card: "Trackpad", keywords: "tape window strip scroll swipe gesture two fingers horizontal momentum control option browse"),
        .init(destination: .tape, card: "Mac Setup and log", keywords: "tape window strip stage manager tiling conflict window manager log logging diagnostics reveal"),
        .init(destination: .appearance, card: "Themes", keywords: "theme live scenes editorial classics custom picture blur fade see through appearance light dark system colors colours custom background accent two-tone gradient picture photo image wallpaper everforest rainbow synthwave midnight noir scarlet rose coral iris orchid nord ghostty iterm glass clear frost smoke tinted tint transparent see-through translucent terminal live animated scenes nature bloom flowers forest earth water sky tech"),
        .init(destination: .heartable, card: "Music Player", keywords: "music player page look standard terminal shelf scroll covers carousel lyrics lyric styles poster album art cover covers artwork ascii braille text art vinyl record pulse spiral scene style detail blocks contour binary 8-bit 16-bit pixel clock orb cuts around rain warp tunnel colours colors tint"),
        .init(destination: .heartable, card: "Local files", keywords: "local files folder music files covers lyrics own songs spotify embedded"),
        .init(destination: .activities, card: "Closed Notch", keywords: "notch look style clear transparent bubbles circles hide notch camera island external display hint faint pill pop-outs popouts bubble shapes shape circle round squircle rounded square music timers keep awake meeting screenshot paste queue battery system desktop follow theme colours colors"),
        .init(destination: .heartable, card: "Swipe", keywords: "swipe sideways two finger gesture skip next previous change song music panel"),
        .init(destination: .activities, card: "Beside the notch", keywords: "live activities show hide closed notch spaces desktop changes now playing music running timer upcoming video meeting power low battery alerts paste queue count screenshot thumbnail microphone mute focus pop-out popout bubble"),
        .init(destination: .tsukumo, card: "Coding agents", keywords: "agent coding agents claude codex hooks needs you pop-out popout bubble pulse agents tab answer permission requests allow deny approve peek face mascot character bot working while agents work finished done smile"),
        .init(destination: .permissions, card: "Automation", keywords: "permissions privacy access automation"),
        .init(destination: .permissions, card: "Accessibility", keywords: "permissions privacy access accessibility"),
        .init(destination: .permissions, card: "Calendars", keywords: "permissions privacy access calendars"),
        .init(destination: .permissions, card: "Reminders", keywords: "permissions privacy access reminders"),
        .init(destination: .permissions, card: "Camera", keywords: "permissions privacy access camera"),
        .init(destination: .permissions, card: "Location", keywords: "permissions privacy access location"),
        .init(destination: .permissions, card: "Bluetooth", keywords: "permissions privacy access bluetooth"),
    ]

    private static let order = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) })

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
            // Within a page, in the order its cards are listed here, which follows the page.
            return (order[$0.id] ?? 0) < (order[$1.id] ?? 0)
        }
    }
}
