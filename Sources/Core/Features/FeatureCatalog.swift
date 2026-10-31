import Foundation

enum FeatureID: String, Codable, CaseIterable, Hashable, Sendable {
    case media, shortcuts, calendar, todos, timer, notes, mirror, battery, clock, weather
    case clipboard, pomodoro, quickActions, systemStats, keepAwake, files, lyrics
    case systemFeedback, ocr, transcription, backgroundRemoval, converter
    case meetings, launcher, terminal, script, devServers, calculator
}
enum FeaturePermission: String, Codable, Hashable, Sendable {
    case camera, microphone, calendar, reminders, location, automation, accessibility, notifications
}

/// Pure metadata. Reading the catalog never constructs a service or asks for access.
struct FeatureDescriptor: Identifiable, Sendable {
    let id: FeatureID
    let title: String
    let symbol: String
    let summary: String
    let permissions: Set<FeaturePermission>
    let preferredWidth: Double
    let compact: Bool
}

enum FeatureCatalog {
    static let all: [FeatureDescriptor] = [
        feature(.media, "Music", "music.note", "Artwork and playback from your active player.", [.automation], width: 260),
        feature(.shortcuts, "Shortcuts", "bolt.fill", "Run your Apple Shortcuts.", width: 150),
        feature(.calendar, "Calendar", "calendar", "Your upcoming events.", [.calendar]),
        feature(.todos, "Reminders", "checklist", "Your lists and tasks.", [.reminders]),
        feature(.timer, "Timers", "timer", "Countdowns that continue when the Nook closes.", [.notifications], width: 116, compact: true),
        feature(.notes, "Notes", "note.text", "Local notes, with optional personal sync."),
        feature(.mirror, "Mirror", "web.camera", "A camera preview only while you use it.", [.camera]),
        feature(.battery, "Battery", "battery.100percent", "Mac and accessory battery readings.", width: 116, compact: true),
        feature(.clock, "Clock", "clock", "Time and date at a glance.", width: 116, compact: true),
        feature(.weather, "Weather", "cloud.sun", "Current conditions and forecast.", [.location], width: 116, compact: true),
        feature(.clipboard, "Clipboard", "doc.on.clipboard", "Your recent copies; collection is opt-in."),
        feature(.pomodoro, "Focus timer", "timer.circle", "Focus and break sessions.", width: 116, compact: true),
        feature(.quickActions, "Quick actions", "bolt", "Useful Mac actions in one place.", [.automation], width: 150),
        feature(.systemStats, "System stats", "chart.xyaxis.line", "Resource usage and history.", width: 200),
        feature(.keepAwake, "Keep awake", "cup.and.saucer", "Keep your Mac or display awake for a session.", width: 200),
        feature(.files, "Files", "tray.full", "Persistent Tray and floating baskets."),
        feature(.lyrics, "Lyrics", "quote.bubble", "Lyrics and captions below the Nook widgets."),
        feature(.systemFeedback, "System feedback", "waveform.path", "Microphone mute and Focus feedback."),
        feature(.ocr, "Recognize text", "text.viewfinder", "Extract text from selected images and PDFs on your Mac."),
        feature(.transcription, "Dictation", "waveform", "Explicit on-device dictation into an editable draft.", [.microphone]),
        feature(.backgroundRemoval, "Remove background", "person.crop.rectangle", "Isolate subjects in selected images without sending them to a server."),
        feature(.converter, "File Converter", "arrow.triangle.2.circlepath", "Shift-drag a file to convert it; Option-Shift for tools. Copies are saved beside the original."),
        feature(.meetings, "Meetings", "video.bubble", "Microphone and camera controls for Zoom or a selected Google Meet tab; unknown controls stay disabled.", [.accessibility, .automation]),
        feature(.launcher, "Action search", "magnifyingglass", "Find MacSpaces pages, file tools and Apple Shortcuts."),
        feature(.devServers, "Dev servers", "server.rack", "Your local servers by port, to open or stop.", width: 260),
        feature(.calculator, "Calculator", "equal.square", "Sums, units and currencies as you type.", width: 200),
        feature(.terminal, "Terminal", "apple.terminal", "Quick commands in a shell that keeps running when the Nook closes.", width: 300),
        feature(.script, "Teleprompter", "text.alignleft", "Read your own script beneath the camera, scrolling or following your voice.", [.microphone])
    ]
    static let byID = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
    static func descriptor(_ id: FeatureID) -> FeatureDescriptor { byID[id]! }

    private static func feature(_ id: FeatureID, _ title: String, _ symbol: String, _ summary: String,
                                _ permissions: Set<FeaturePermission> = [], width: Double = 180,
                                compact: Bool = false) -> FeatureDescriptor {
        FeatureDescriptor(id: id, title: title, symbol: symbol, summary: summary, permissions: permissions,
                          preferredWidth: width, compact: compact)
    }
}
