import Foundation

enum FeatureID: String, Codable, CaseIterable, Hashable, Sendable {
    case media, shortcuts, calendar, todos, timer, notes, mirror, battery, clock, weather
    case clipboard, pomodoro, quickActions, systemStats, keepAwake
    case files, lyrics, systemFeedback, notifications, capture, ocr, transcription
    case backgroundRemoval, converter, pdfCompression, videoCompression, windows, meetings
    case launcher, terminal, script, selectedText, rings, emoji, obsidian, scrolling
    case menuBar, keyboardSounds, lidEffects, localSend, sharing, sync, extensions
    case devServers, calculator
}
enum FeatureSurface: String, Codable, Hashable, Sendable {
    case nook, tray, activity, floating, shortcut, ring, companion, settings, menuBar, selection, finder
}
enum FeaturePermission: String, Codable, Hashable, Sendable {
    case camera, microphone, calendar, reminders, location, automation, accessibility
    case screenCapture, audioCapture, fullDiskAccess, notifications, iCloud
}
enum FeatureAvailability: String, Codable, Sendable { case available, developing }

/// Pure metadata. Reading the catalog never constructs a service or asks for access.
struct FeatureDescriptor: Identifiable, Sendable {
    let id: FeatureID
    let title: String
    let symbol: String
    let summary: String
    let surfaces: Set<FeatureSurface>
    let dependencies: Set<FeatureID>
    let permissions: Set<FeaturePermission>
    let availability: FeatureAvailability
    let preferredWidth: Double
    let compact: Bool
    var settingsDestination: String { "features/" + id.rawValue }
}

enum FeatureCatalog {
    static let all: [FeatureDescriptor] = [
        feature(.media, "Media", "music.note", "Artwork and playback from your active player.", [.nook, .activity, .shortcut], [.automation], width: 260),
        feature(.shortcuts, "Shortcuts", "bolt.fill", "Run your Apple Shortcuts.", [.nook, .shortcut], width: 150),
        feature(.calendar, "Calendar", "calendar", "Your upcoming events.", [.nook, .companion], [.calendar]),
        feature(.todos, "Reminders", "checklist", "Your lists and tasks.", [.nook, .companion], [.reminders]),
        feature(.timer, "Timers", "timer", "Countdowns that continue when the Nook closes.", [.nook, .activity, .companion], [.notifications], width: 116, compact: true),
        feature(.notes, "Notes", "note.text", "Local notes, with optional personal sync.", [.nook, .companion]),
        feature(.mirror, "Mirror", "web.camera", "A camera preview only while you use it.", [.nook], [.camera]),
        feature(.battery, "Battery", "battery.100percent", "Mac and accessory battery readings.", [.nook, .activity], width: 116, compact: true),
        feature(.clock, "Clock", "clock", "Time and date at a glance.", [.nook], width: 116, compact: true),
        feature(.weather, "Weather", "cloud.sun", "Current conditions and forecast.", [.nook, .companion], [.location], width: 116, compact: true),
        feature(.clipboard, "Clipboard", "doc.on.clipboard", "Your recent copies; collection is opt-in.", [.nook, .companion]),
        feature(.pomodoro, "Focus timer", "timer.circle", "Focus and break sessions.", [.nook, .activity, .companion], width: 116, compact: true),
        feature(.quickActions, "Quick actions", "bolt", "Useful Mac actions in one place.", [.nook, .ring], [.automation], width: 150),
        feature(.systemStats, "System stats", "chart.xyaxis.line", "Resource usage and history.", [.nook], width: 200),
        feature(.keepAwake, "Keep awake", "cup.and.saucer", "Keep your Mac or display awake for a session.", [.nook, .activity], width: 200),
        feature(.files, "Files", "tray.full", "Persistent Tray and floating baskets.", [.tray, .floating, .companion, .finder]),
        feature(.lyrics, "Lyrics", "quote.bubble", "Lyrics and captions below the Nook widgets.", [.nook], dependencies: [.media]),
        feature(.systemFeedback, "System feedback", "waveform.path", "Microphone mute and Focus feedback.", [.activity]),
        feature(.notifications, "Messages", "bubble.left.and.bubble.right", "New messages through the notch, and replies from Home.", [.nook, .activity], [.fullDiskAccess, .automation], width: 260),
        feature(.capture, "Capture", "viewfinder", "Screen and window captures with annotation.", [.shortcut, .ring], [.screenCapture], developing: true),
        feature(.ocr, "Recognize text", "text.viewfinder", "Extract text from selected images and PDFs on your Mac.", [.tray, .finder]),
        feature(.transcription, "Dictation", "waveform", "Explicit on-device dictation into an editable draft.", [.shortcut], [.microphone]),
        feature(.backgroundRemoval, "Remove background", "person.crop.rectangle", "Isolate subjects in selected images without sending them to a server.", [.tray, .finder]),
        feature(.converter, "File Converter", "arrow.triangle.2.circlepath", "Shift-drag a file to convert it; Option-Shift for tools. Copies are saved beside the original.", [.finder]),
        feature(.pdfCompression, "Compress PDFs", "doc.zipper", "Smaller PDFs with selectable text.", [.tray], developing: true),
        feature(.videoCompression, "Compress video", "video", "Target a file size with progress and cancellation.", [.tray], developing: true),
        feature(.windows, "Window snapping", "rectangle.split.2x1", "Arrange windows with keyboard actions.", [.shortcut, .ring], [.accessibility], developing: true),
        feature(.meetings, "Meetings", "video.bubble", "Microphone and camera controls for Zoom or a selected Google Meet tab; unknown controls stay disabled.", [.shortcut], [.accessibility, .automation]),
        feature(.launcher, "Action search", "magnifyingglass", "Find MacSpaces pages, file tools and Apple Shortcuts.", [.shortcut]),
        feature(.devServers, "Dev servers", "server.rack", "Your local servers by port, to open or stop.", [.nook], width: 260),
        feature(.calculator, "Calculator", "equal.square", "Sums, units and currencies as you type.", [.nook], width: 200),
        feature(.terminal, "Terminal", "apple.terminal", "Quick commands in a shell that keeps running when the Nook closes.", [.nook], width: 300),
        feature(.script, "Teleprompter", "text.alignleft", "Read your own script beneath the camera, scrolling or following your voice.", [.nook], [.microphone]),
        feature(.selectedText, "Text actions", "text.cursor", "Act on text you explicitly select.", [.selection, .shortcut], [.accessibility], developing: true),
        feature(.rings, "Action rings", "circle.grid.2x2", "Your registered actions on a shortcut.", [.ring, .shortcut], developing: true),
        feature(.emoji, "Emoji", "face.smiling", "Search and insert emoji.", [.shortcut, .selection], [.accessibility], developing: true),
        feature(.obsidian, "Obsidian", "book.closed", "Edit notes in a selected vault.", [.nook], developing: true),
        feature(.scrolling, "Scrolling", "computermouse", "Optional smooth and reverse scrolling.", [.settings], [.accessibility], developing: true),
        feature(.menuBar, "Menu bar", "menubar.rectangle", "Manage menu-bar items.", [.menuBar], [.accessibility], developing: true),
        feature(.keyboardSounds, "Keyboard sounds", "keyboard", "Optional sound feedback while typing.", [.settings], [.accessibility], developing: true),
        feature(.lidEffects, "Lid effects", "laptopcomputer", "Effects on supported MacBook hardware.", [.settings], developing: true),
        feature(.localSend, "LocalSend", "network", "Send selected files to a paired device.", [.tray], developing: true),
        feature(.sharing, "Share files", "square.and.arrow.up", "AirDrop and native iCloud sharing of selected copies.", [.tray, .finder], [.iCloud], developing: true),
        feature(.sync, "Personal sync", "icloud", "Optional encrypted MacSpaces records across your devices.", [.settings, .companion], [.iCloud], developing: true),
        feature(.extensions, "Extensions", "puzzlepiece.extension", "Versioned extensions with declared capabilities.", [.settings], developing: true)
    ]
    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func descriptor(_ id: FeatureID) -> FeatureDescriptor { byID[id]! }

    private static func feature(_ id: FeatureID, _ title: String, _ symbol: String, _ summary: String,
                                _ surfaces: Set<FeatureSurface>, _ permissions: Set<FeaturePermission> = [],
                                dependencies: Set<FeatureID> = [], width: Double = 180,
                                compact: Bool = false, developing: Bool = false) -> FeatureDescriptor {
        FeatureDescriptor(id: id, title: title, symbol: symbol, summary: summary, surfaces: surfaces,
                          dependencies: dependencies, permissions: permissions,
                          availability: developing ? .developing : .available,
                          preferredWidth: width, compact: compact)
    }
}
