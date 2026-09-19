import Foundation

/// Every widget type MacSpaces can render.
enum WidgetKind: String, Codable, CaseIterable, Identifiable {
    case clock
    case weather
    case calendar
    case reminders
    case nowPlaying
    case systemStats
    case apps
    case quickActions
    case clipboard
    case pomodoro
    case search
    case notes
    case colorPicker
    case converter
    case bookmarks
    case appSwitcher
    case audio
    case drinkWater
    case progress
    case downloads
    case fileShelf
    case emoji
    case screenshots
    case voiceMemo
    case mail
    case photos
    case crypto
    case claude
    case zoomMeetings
    case windowManager
    case wallpaper
    case spacer
    case separator
    case shortcuts

    var id: String { rawValue }

    var title: String {
        switch self {
        case .clock: return "Clock"
        case .weather: return "Weather"
        case .calendar: return "Calendar"
        case .reminders: return "Todos"
        case .nowPlaying: return "Now Playing"
        case .systemStats: return "System Stats"
        case .apps: return "Apps & Folders"
        case .quickActions: return "Quick Actions"
        case .clipboard: return "Clipboard"
        case .pomodoro: return "Pomodoro"
        case .search: return "Search"
        case .notes: return "Notes"
        case .colorPicker: return "Color Picker"
        case .converter: return "Converter"
        case .bookmarks: return "Bookmarks"
        case .appSwitcher: return "App Switcher"
        case .audio: return "Audio Controls"
        case .drinkWater: return "Drink Water"
        case .progress: return "Progress"
        case .downloads: return "Downloads"
        case .fileShelf: return "File Shelf"
        case .emoji: return "Emoji"
        case .screenshots: return "Screenshots"
        case .voiceMemo: return "Voice Memo"
        case .mail: return "Mail"
        case .photos: return "Photos"
        case .crypto: return "Crypto"
        case .claude: return "Claude"
        case .zoomMeetings: return "Meetings"
        case .windowManager: return "Window Manager"
        case .wallpaper: return "Wallpaper"
        case .spacer: return "Spacer"
        case .separator: return "Separator"
        case .shortcuts: return "Shortcuts"
        }
    }

    var systemImage: String {
        switch self {
        case .clock: return "clock"
        case .weather: return "cloud.sun"
        case .calendar: return "calendar"
        case .reminders: return "checklist"
        case .nowPlaying: return "music.note"
        case .systemStats: return "gauge.with.dots.needle.50percent"
        case .apps: return "square.grid.2x2"
        case .quickActions: return "bolt"
        case .clipboard: return "doc.on.clipboard"
        case .pomodoro: return "timer"
        case .search: return "magnifyingglass"
        case .notes: return "note.text"
        case .colorPicker: return "eyedropper"
        case .converter: return "arrow.left.arrow.right"
        case .bookmarks: return "bookmark"
        case .appSwitcher: return "rectangle.on.rectangle"
        case .audio: return "speaker.wave.2"
        case .drinkWater: return "drop"
        case .progress: return "chart.bar.fill"
        case .downloads: return "arrow.down.circle"
        case .fileShelf: return "tray.full"
        case .emoji: return "face.smiling"
        case .screenshots: return "camera.viewfinder"
        case .voiceMemo: return "mic"
        case .mail: return "envelope"
        case .photos: return "photo"
        case .crypto: return "bitcoinsign.circle"
        case .claude: return "sparkles"
        case .zoomMeetings: return "video"
        case .windowManager: return "rectangle.split.2x1"
        case .wallpaper: return "photo.on.rectangle.angled"
        case .spacer: return "arrow.left.and.right"
        case .separator: return "line.diagonal"
        case .shortcuts: return "square.stack.3d.up.fill"
        }
    }

    /// How many base tile units the widget occupies along the dock's axis.
    var units: Int {
        switch self {
        case .clock, .weather, .pomodoro, .search, .quickActions,
             .colorPicker, .drinkWater, .emoji, .voiceMemo, .mail, .photos,
             .claude, .wallpaper, .spacer, .separator:
            return 1
        case .calendar, .reminders, .nowPlaying, .systemStats,
             .apps, .clipboard, .notes, .converter, .bookmarks,
             .appSwitcher, .audio, .progress, .downloads, .fileShelf,
             .screenshots, .crypto, .zoomMeetings, .windowManager, .shortcuts:
            return 2
        }
    }

    func axisLength(tile: CGFloat, spacing: CGFloat) -> CGFloat {
        switch self {
        case .separator: return 12
        case .spacer: return max(30, tile * 0.45)
        default:
            return CGFloat(units) * tile + CGFloat(units - 1) * spacing
        }
    }

    /// Small glanceable controls can share one bottom-dock column instead of
    /// wasting a full square each. Wide and interaction-heavy widgets remain
    /// full height.
    var canUseCompactDockRow: Bool {
        switch self {
        case .clock, .weather, .pomodoro:
            return true
        default:
            return false
        }
    }
}

struct DockLayoutItem: Identifiable {
    let instances: [WidgetInstance]

    var id: UUID { instances[0].id }
    var isStack: Bool { instances.count == 2 }

    func axisLength(tile: CGFloat, spacing: CGFloat) -> CGFloat {
        instances
            .map { $0.kind.axisLength(tile: tile, spacing: spacing) }
            .max() ?? tile
    }
}

extension Array where Element == WidgetInstance {
    func dockLayoutItems(vertical: Bool) -> [DockLayoutItem] {
        guard !vertical else { return map { DockLayoutItem(instances: [$0]) } }

        var result: [DockLayoutItem] = []
        var index = startIndex
        while index < endIndex {
            let current = self[index]
            let nextIndex = self.index(after: index)
            if current.usesCompactDockRow,
               nextIndex < endIndex,
               self[nextIndex].usesCompactDockRow {
                result.append(
                    DockLayoutItem(instances: [current, self[nextIndex]])
                )
                index = self.index(after: nextIndex)
            } else {
                result.append(DockLayoutItem(instances: [current]))
                index = nextIndex
            }
        }
        return result
    }
}

enum DockWidgetSizeMode: String, Codable, CaseIterable, Identifiable {
    case automatic
    case compact
    case full

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: return "Automatic"
        case .compact: return "Compact"
        case .full: return "Full Height"
        }
    }
}

/// A widget placed in the dock. Kept separate from `WidgetKind` so the same
/// kind can appear multiple times, each with its own identity.
struct WidgetInstance: Identifiable, Codable, Equatable {
    var id: UUID
    var kind: WidgetKind
    var visualStyle: WidgetVisualStyle
    var sizeMode: DockWidgetSizeMode

    init(
        id: UUID = UUID(),
        kind: WidgetKind,
        visualStyle: WidgetVisualStyle = .studio,
        sizeMode: DockWidgetSizeMode = .automatic
    ) {
        self.id = id
        self.kind = kind
        self.visualStyle = visualStyle
        self.sizeMode = sizeMode
    }

    private enum CodingKeys: String, CodingKey {
        case id, kind, visualStyle, sizeMode
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        kind = try container.decode(WidgetKind.self, forKey: .kind)
        visualStyle = try container.decodeIfPresent(
            WidgetVisualStyle.self,
            forKey: .visualStyle
        ) ?? .studio
        sizeMode = try container.decodeIfPresent(
            DockWidgetSizeMode.self,
            forKey: .sizeMode
        ) ?? .automatic
    }

    var usesCompactDockRow: Bool {
        kind.canUseCompactDockRow
    }
}
