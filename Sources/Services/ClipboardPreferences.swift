import AppKit
import Combine

/// The keyboard shortcut that opens clipboard history anywhere.
enum ClipboardHistoryShortcut: String, CaseIterable, Identifiable {
    case off
    case shiftCommandC
    case optionCommandC
    case controlCommandV
    case shiftOptionCommandV

    var id: String { rawValue }
    var title: String {
        switch self {
        case .off: return "Off"
        case .shiftCommandC: return "⇧⌘C"
        case .optionCommandC: return "⌥⌘C"
        case .controlCommandV: return "⌃⌘V"
        case .shiftOptionCommandV: return "⇧⌥⌘V"
        }
    }
}

/// Where the history popup opens.
enum ClipboardPopupPosition: String, CaseIterable, Identifiable {
    case pointer, center, notch
    var id: String { rawValue }
    var title: String {
        switch self {
        case .pointer: return "At the pointer"
        case .center: return "Centre of the screen"
        case .notch: return "Under the notch"
        }
    }
}

/// Clipboard history settings (Settings → Clipboard). Everything here stays on
/// this Mac in UserDefaults; the clips themselves never do unless "Keep history
/// after quitting" is on.
@MainActor
final class ClipboardPreferences: ObservableObject {
    static let shared = ClipboardPreferences()
    private let defaults: UserDefaults

    @Published var shortcut: ClipboardHistoryShortcut { didSet { save(shortcut.rawValue, "shortcut"); ClipboardPopup.shared.registerShortcut() } }
    @Published var popupPosition: ClipboardPopupPosition { didSet { save(popupPosition.rawValue, "popupPosition") } }
    @Published var historyLimit: Int { didSet { save(historyLimit, "historyLimit") } }
    @Published var sortOrder: ClipboardSortOrder { didSet { save(sortOrder.rawValue, "sortOrder") } }
    @Published var searchMode: ClipboardSearchMode { didSet { save(searchMode.rawValue, "searchMode") } }
    @Published var pinsOnTop: Bool { didSet { save(pinsOnTop, "pinsOnTop") } }
    /// Return pastes the clip into the app you were in (instead of only copying it).
    @Published var pasteOnSelect: Bool { didSet { save(pasteOnSelect, "pasteOnSelect") } }
    /// Pasting drops formatting unless ⇧ is held (the reverse when off).
    @Published var plainTextByDefault: Bool { didSet { save(plainTextByDefault, "plainTextByDefault") } }
    @Published var showsPreview: Bool { didSet { save(showsPreview, "showsPreview") } }
    @Published var showsAppIcons: Bool { didSet { save(showsAppIcons, "showsAppIcons") } }
    @Published var clearsOnQuit: Bool { didSet { save(clearsOnQuit, "clearsOnQuit") } }
    /// Clearing history also empties the system clipboard.
    @Published var clearsSystemClipboard: Bool { didSet { save(clearsSystemClipboard, "clearsSystemClipboard") } }
    @Published var filter: ClipboardFilter { didSet { saveFilter() } }
    /// Recording is paused until turned back on (not saved: a relaunch records again).
    @Published var paused = false
    /// The next copy is left out, then recording carries on.
    @Published var ignoresNextCopy = false

    static let historyLimits = [50, 100, 200, 500, 1000]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        func value<T>(_ key: String, _ fallback: T) -> T { defaults.object(forKey: "clipboard." + key) as? T ?? fallback }
        shortcut = ClipboardHistoryShortcut(rawValue: value("shortcut", "")) ?? .shiftCommandC
        popupPosition = ClipboardPopupPosition(rawValue: value("popupPosition", "")) ?? .pointer
        historyLimit = value("historyLimit", 200)
        sortOrder = ClipboardSortOrder(rawValue: value("sortOrder", "")) ?? .lastCopied
        searchMode = ClipboardSearchMode(rawValue: value("searchMode", "")) ?? .mixed
        pinsOnTop = value("pinsOnTop", true)
        pasteOnSelect = value("pasteOnSelect", false)
        plainTextByDefault = value("plainTextByDefault", false)
        showsPreview = value("showsPreview", true)
        showsAppIcons = value("showsAppIcons", true)
        clearsOnQuit = value("clearsOnQuit", false)
        clearsSystemClipboard = value("clearsSystemClipboard", false)
        var filter = ClipboardFilter()
        filter.recordsText = value("recordsText", true)
        filter.recordsImages = value("recordsImages", true)
        filter.recordsFiles = value("recordsFiles", true)
        if let types = defaults.stringArray(forKey: "clipboard.ignoredTypes") { filter.ignoredTypes = Set(types) }
        filter.ignoredPatterns = defaults.stringArray(forKey: "clipboard.ignoredPatterns") ?? []
        filter.apps = Set(defaults.stringArray(forKey: "clipboard.apps") ?? [])
        filter.onlyListedApps = value("onlyListedApps", false)
        self.filter = filter
    }

    private func save(_ value: Any, _ key: String) { defaults.set(value, forKey: "clipboard." + key) }

    private func saveFilter() {
        save(filter.recordsText, "recordsText")
        save(filter.recordsImages, "recordsImages")
        save(filter.recordsFiles, "recordsFiles")
        save(filter.ignoredTypes.sorted(), "ignoredTypes")
        save(filter.ignoredPatterns, "ignoredPatterns")
        save(filter.apps.sorted(), "apps")
        save(filter.onlyListedApps, "onlyListedApps")
    }
}
