import Foundation
import Combine
import CoreGraphics

enum NookWidgetKind: String, Codable, CaseIterable, Identifiable {
    case media
    case shortcuts
    case calendar
    case todos
    case timer
    case notes
    case mirror
    case battery
    case clock
    case weather
    case clipboard
    case quickActions
    case systemStats
    case keepAwake
    case terminal
    case devServers
    case calculator
    case spaces
    // The Tsukumo quick bar ("agents", 2.38) and the Messages widget
    // ("notifications", 3.21) were removed; saved profiles that list them drop
    // them on decode.

    /// Widgets that became another, by their saved names.
    static let moved: [String: NookWidgetKind] = ["worldClock": .clock, "pomodoro": .timer]

    /// Widgets as offered in menus and the library: alphabetical by title.
    static var alphabetical: [NookWidgetKind] {
        allCases.sorted { $0.title.localizedStandardCompare($1.title) == .orderedAscending }
    }
    var id: String { rawValue }

    var featureID: FeatureID { FeatureID(rawValue: rawValue)! }
    var descriptor: FeatureDescriptor { FeatureCatalog.descriptor(featureID) }
    var title: String { descriptor.title }
    var systemImage: String { descriptor.symbol }
    var preferredWidth: CGFloat { CGFloat(descriptor.preferredWidth) }
    var canUseCompactRow: Bool { descriptor.compact }

}

/// How much room a widget takes on Home. Adjacent small widgets share a
/// column, one above the other, so the user decides which widgets pair up.
enum NookWidgetSize: String, Codable, CaseIterable, Identifiable {
    case small, medium, large

    var id: String { rawValue }
    var title: String { rawValue.capitalized }
}

extension NookWidgetKind {
    /// The Add Widgets sheet's groups. Every widget is in one; any not listed
    /// (a new one) falls into "More", so nothing can go missing from the sheet.
    static var libraryGroups: [(String, [NookWidgetKind])] {
        let groups: [(String, [NookWidgetKind])] = [
            ("Listen", [.media]),
            ("Plan", [.calendar, .todos, .weather, .clock]),
            ("Focus", [.timer, .notes, .keepAwake]),
            ("Tools", [.terminal, .devServers, .calculator, .clipboard, .shortcuts, .quickActions]),
            ("Status", [.battery, .systemStats, .mirror, .spaces]),
        ]
        let listed = Set(groups.flatMap(\.1))
        let rest = allCases.filter { !listed.contains($0) }
        return rest.isEmpty ? groups : groups + [("More", rest)]
    }

    var supportedSizes: [NookWidgetSize] { [defaultSize] }

    /// The full page behind a widget: tapping its expand button opens it, so a
    /// Home tile is the small form of a page rather than a separate thing.
    var page: NotchTab? {
        switch self {
        case .media: return .music
        case .calendar: return .calendar
        case .todos: return .reminders
        case .timer: return .timers
        case .notes: return .notes
        case .mirror: return .mirror
        case .weather: return .weather
        case .clipboard: return .tray   // Folio, on its Clipboard place (`NotchViewModel.openPage`).
        case .systemStats, .battery, .keepAwake: return .system
        case .terminal, .devServers: return .terminal
        case .shortcuts, .quickActions: return .shortcuts
        case .clock: return .clock
        case .calculator, .spaces: return nil
        }
    }

    /// Each feature has one fitted Home presentation; saved manual sizes are legacy data.
    var defaultSize: NookWidgetSize {
        switch self {
        case .media: return .large
        case .clock, .timer, .battery, .keepAwake, .spaces: return .small
        default: return .medium
        }
    }

    func resolvedSize(_ legacySize: NookWidgetSize?) -> NookWidgetSize { defaultSize }

    func width(for size: NookWidgetSize) -> CGFloat {
        switch (size, canUseCompactRow) {
        case (.small, true): return preferredWidth
        case (.small, false): return self == .media ? 200 : 160
        case (.medium, true): return 176
        case (.medium, false): return preferredWidth
        case (.large, true): return 300
        case (.large, false): return self == .calendar ? 380 : (preferredWidth * 1.5).rounded()
        }
    }
}

struct NookLayoutItem: Identifiable {
    let kinds: [NookWidgetKind]
    let width: CGFloat

    var id: String { kinds.map(\.rawValue).joined(separator: "+") }
    var isStack: Bool { kinds.count == 2 }
}

extension Array where Element == NookWidgetKind {
    /// Expand columns proportionally to occupy header-required space. Profiles
    /// wider than the available area retain their natural widths and scroll.
    func fittedNookWidths(availableWidth: CGFloat, spacing: CGFloat = 10,
                          sizes: [NookWidgetKind: NookWidgetSize] = [:]) -> [NookWidgetKind: CGFloat] {
        let columns = nookLayoutItems(sizes: sizes)
        let naturalWidth = columns.reduce(CGFloat.zero) { $0 + $1.width }
        guard naturalWidth > 0 else { return [:] }
        let gaps = CGFloat(Swift.max(0, columns.count - 1)) * spacing
        let scale = Swift.max(1, (availableWidth - gaps) / naturalWidth)
        return Dictionary(columns.flatMap { column in
            column.kinds.map { ($0, column.width * scale) }
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Consecutive small widgets pair into one stacked column; a small
    /// widget without a partner keeps its narrow width at full height.
    func nookLayoutItems(sizes: [NookWidgetKind: NookWidgetSize] = [:]) -> [NookLayoutItem] {
        var result: [NookLayoutItem] = []
        var index = startIndex
        while index < endIndex {
            let current = self[index]
            let currentSize = current.resolvedSize(sizes[current])
            let nextIndex = self.index(after: index)
            if currentSize == .small,
               nextIndex < endIndex,
               self[nextIndex].resolvedSize(sizes[self[nextIndex]]) == .small {
                let next = self[nextIndex]
                result.append(NookLayoutItem(kinds: [current, next],
                                             width: Swift.max(current.width(for: .small), next.width(for: .small))))
                index = self.index(after: nextIndex)
            } else {
                result.append(NookLayoutItem(kinds: [current], width: current.width(for: currentSize)))
                index = nextIndex
            }
        }
        return result
    }
}

struct NookProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var widgets: [NookWidgetKind]
    /// Optional so profiles created by older builds decode without migration
    /// failures. Widths remain specific to each named Nook profile.
    var widgetWidths: [String: Double]? = nil
    /// Chosen widget sizes; missing entries use each widget's default.
    var widgetSizes: [String: NookWidgetSize]? = nil
    /// The SF Symbol for this Home in the dock; nil uses a default by position.
    var symbol: String? = nil

    /// Symbols offered for a Home; the first six are the defaults, by position.
    static let symbols = ["square.grid.2x2.fill", "circle.grid.2x2.fill", "square.stack.3d.up.fill",
                          "rectangle.split.3x1.fill", "square.grid.3x2.fill", "rectangle.grid.2x2.fill",
                          "house.fill", "briefcase.fill", "music.note.house.fill", "moon.stars.fill",
                          "sparkles", "book.fill", "gamecontroller.fill", "cup.and.saucer.fill"]

    init(
        id: UUID,
        name: String,
        widgets: [NookWidgetKind],
        widgetWidths: [String: Double]? = nil,
        widgetSizes: [String: NookWidgetSize]? = nil
    ) {
        self.id = id
        self.name = name
        self.widgets = widgets
        self.widgetWidths = widgetWidths
        self.widgetSizes = widgetSizes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, widgets, widgetWidths, widgetSizes, symbol
    }

    /// A widget kind this build cannot decode is dropped rather than failing
    /// the whole profile and taking every other saved layout with it.
    private struct DecodableKind: Decodable {
        let value: NookWidgetKind?

        init(from decoder: Decoder) throws {
            let raw = try? decoder.singleValueContainer().decode(String.self)
            // 2.68's World Clock is now the Clock, and the Focus timer is now part of Timers.
            if let raw, let moved = NookWidgetKind.moved[raw] {
                value = moved
                return
            }
            value = try? NookWidgetKind(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        // Each widget appears once; a hand-edited or corrupted profile with
        // repeats keeps the first occurrence instead of breaking layout.
        var seen = Set<NookWidgetKind>()
        widgets = try container
            .decode([DecodableKind].self, forKey: .widgets)
            .compactMap(\.value)
            .filter { seen.insert($0).inserted }
        widgetWidths = try container.decodeIfPresent(
            [String: Double].self,
            forKey: .widgetWidths
        )
        // An unknown size from a newer build falls back to defaults.
        widgetSizes = (try? container.decodeIfPresent(
            [String: NookWidgetSize].self,
            forKey: .widgetSizes
        )) ?? nil
        symbol = try? container.decodeIfPresent(String.self, forKey: .symbol)
    }
}

/// User preferences and Nook profiles. A profile owns its ordered widget
/// layout, matching the Dock profile model rather than keeping one global
/// Nook arrangement.
@MainActor
final class NookSettings: ObservableObject {
    static let shared = NookSettings()
    /// A fresh install's Home: Music at full size, a timer and the clock.
    static let starterWidgets: [NookWidgetKind] = [.media, .timer, .clock]
    static let starterSizes: [String: NookWidgetSize] = [NookWidgetKind.media.rawValue: .large]

    @Published var expandOnHover: Bool {
        didSet { defaults.set(expandOnHover, forKey: Keys.expandOnHover) }
    }

    @Published var hoverDelay: Double {
        didSet { defaults.set(hoverDelay, forKey: Keys.hoverDelay) }
    }

    @Published var displayMode: DisplayTargetMode {
        didSet { defaults.set(displayMode.rawValue, forKey: Keys.displayMode) }
    }

    @Published var selectedDisplayIDs: [String] {
        didSet { defaults.set(selectedDisplayIDs, forKey: Keys.selectedDisplayIDs) }
    }

    @Published var showMusicLiveActivity: Bool {
        didSet { defaults.set(showMusicLiveActivity, forKey: Keys.showMusicLiveActivity) }
    }

    @Published var showPowerLiveActivity: Bool {
        didSet { defaults.set(showPowerLiveActivity, forKey: Keys.showPowerLiveActivity) }
    }

    /// Apps (bundle identifiers) in front of which the Nook steps out of the way entirely.
    @Published var hiddenInApps: [String] {
        didSet { defaults.set(hiddenInApps, forKey: Keys.hiddenInApps) }
    }
    /// A video meeting about to start (or just started) counts down beside the notch.
    @Published var showMeetingLiveActivity: Bool {
        didSet { defaults.set(showMeetingLiveActivity, forKey: Keys.showMeetingLiveActivity) }
    }
    @Published var showTimerLiveActivity: Bool {
        didSet { defaults.set(showTimerLiveActivity, forKey: Keys.showTimerLiveActivity) }
    }
    /// Keep Awake's cup (and its time left) beside the closed notch while it's on.
    @Published var showKeepAwakeLiveActivity: Bool {
        didSet { defaults.set(showKeepAwakeLiveActivity, forKey: Keys.showKeepAwakeLiveActivity) }
    }
    /// The paste queue's remaining-clips count beside the closed notch.
    @Published var showPasteQueueLiveActivity: Bool {
        didSet { defaults.set(showPasteQueueLiveActivity, forKey: Keys.showPasteQueueLiveActivity) }
    }
    /// A new screenshot's thumbnail and "In Tray" beside the closed notch.
    @Published var showScreenshotLiveActivity: Bool {
        didSet { defaults.set(showScreenshotLiveActivity, forKey: Keys.showScreenshotLiveActivity) }
    }

    @Published var showMicrophoneLiveActivity: Bool {
        didSet {
            defaults.set(showMicrophoneLiveActivity, forKey: Keys.showMicrophoneLiveActivity)
        }
    }

    @Published var showFocusLiveActivity: Bool {
        didSet { defaults.set(showFocusLiveActivity, forKey: Keys.showFocusLiveActivity) }
    }

    /// The desktop's number and name beside the closed notch for a moment after a Space
    /// change; off by default.
    @Published var showSpacesLiveActivity: Bool {
        didSet { defaults.set(showSpacesLiveActivity, forKey: Keys.showSpacesLiveActivity) }
    }

    /// Each pop-out's chosen shape, by `NotchPopOut.rawValue`; one not listed
    /// has its default (`NotchPopOut.defaultShape`).
    @Published var popOutShapes: [String: String] {
        didSet { defaults.set(popOutShapes, forKey: Keys.popOutShapes) }
    }

    func shape(of popOut: NotchPopOut) -> NotchBubbleShape {
        popOutShapes[popOut.rawValue].flatMap(NotchBubbleShape.init(rawValue:)) ?? popOut.defaultShape
    }

    func isSquircle(_ popOut: NotchPopOut) -> Bool { shape(of: popOut) == .squircle }

    /// The faint resting pill on displays without a camera.
    @Published var notchlessHint: Bool {
        didSet { defaults.set(notchlessHint, forKey: NotchGeometry.notchlessHintKey) }
    }


    /// Applies only while the Nook is closed. The expanded Nook deliberately
    /// leaves all trackpad gestures to its widgets and horizontal scroller.
    /// Dragging files onto the closed notch opens the Tray. When off, files can
    /// still be dropped into an already open Tray.
    @Published var openTrayOnFileDrag: Bool {
        didSet { defaults.set(openTrayOnFileDrag, forKey: Keys.openTrayOnFileDrag) }
    }

    @Published var scrollGesturesEnabled: Bool {
        didSet { defaults.set(scrollGesturesEnabled, forKey: Keys.scrollGesturesEnabled) }
    }

    /// The bubbles that take the theme's colour instead of their own.
    @Published var popOutsFollowingTheme: Set<String> {
        didSet { defaults.set(Array(popOutsFollowingTheme).sorted(), forKey: Keys.popOutsFollowingTheme) }
    }
    func followsTheme(_ popOut: NotchPopOut) -> Bool {
        popOutsFollowingTheme.contains(popOut.rawValue)
    }
    /// A sideways swipe on the notch or an open Music panel changes songs while one is loaded.
    @Published var swipeToChangeSongs: Bool {
        didSet { defaults.set(swipeToChangeSongs, forKey: Keys.swipeToChangeSongs) }
    }

    @Published var expandedWidth: Double {
        didSet { defaults.set(expandedWidth, forKey: Keys.expandedWidth) }
    }

    @Published var expandedHeight: Double {
        didSet { defaults.set(expandedHeight, forKey: Keys.expandedHeight) }
    }

    @Published var fitWidthToProfile: Bool {
        didSet { defaults.set(fitWidthToProfile, forKey: Keys.fitWidthToProfile) }
    }

    @Published var profiles: [NookProfile] {
        didSet { profilesUnreadable = false; scheduleProfileSave() }
    }
    /// The saved profiles couldn't be read: nothing overwrites them, quitting included,
    /// until the person changes a profile themselves.
    private var profilesUnreadable = false

    /// App pages in the dock, in order. Home and Settings are always present.
    @Published var dockApps: [NotchTab] {
        didSet { defaults.set(dockApps.map(\.rawValue), forKey: Keys.dockApps) }
    }

    @Published var showDockPin: Bool {
        didSet { defaults.set(showDockPin, forKey: Keys.showDockPin) }
    }
    @Published var showDockClose: Bool {
        didSet { defaults.set(showDockClose, forKey: Keys.showDockClose) }
    }

    /// Home is always an app in the first dock capsule; profiles are its controls.
    var dockPages: [NotchTab] { dockApps + [.nook] }

    /// Folio's Clipboard place keeps the history coming while Folio is in the dock, as the
    /// Clipboard page it replaced did; switched in Settings, Folio, Clipboard.
    @Published var folioClipboardHistory: Bool {
        didSet { defaults.set(folioClipboardHistory, forKey: Keys.folioClipboardHistory) }
    }
    /// Folio opens on its Clipboard place: set once for a dock whose Clipboard page became Folio.
    @Published var folioOpensOnClipboard: Bool {
        didSet { defaults.set(folioOpensOnClipboard, forKey: Keys.folioOpensOnClipboard) }
    }

    @Published var activeProfileID: UUID {
        didSet { profilesUnreadable = false; scheduleProfileSave() }
    }

    private enum Keys {
        static let expandOnHover = "expandOnHover"
        static let hoverDelay = "hoverDelay"
        static let showOnAllDisplays = "showOnAllDisplays"
        static let displayMode = "displayTargetMode"
        static let selectedDisplayIDs = "selectedDisplayIDs"
        static let showMusicLiveActivity = "showMusicLiveActivity"
        static let popOutShapes = "notch.popOutShapes"
        static let showPowerLiveActivity = "showPowerLiveActivity"
        static let showTimerLiveActivity = "showTimerLiveActivity"
        static let showKeepAwakeLiveActivity = "showKeepAwakeLiveActivity"
        static let showMeetingLiveActivity = "showMeetingLiveActivity"
        static let showPasteQueueLiveActivity = "showPasteQueueLiveActivity"
        static let showScreenshotLiveActivity = "showScreenshotLiveActivity"
        static let hiddenInApps = "hiddenInApps"
        static let showMicrophoneLiveActivity = "showMicrophoneLiveActivity"
        static let showFocusLiveActivity = "showFocusLiveActivity"
        static let showSpacesLiveActivity = "showSpacesLiveActivity"
        static let scrollGesturesEnabled = "scrollGesturesEnabled"
        static let swipeToChangeSongs = "swipeToChangeSongs"
        static let popOutsFollowingTheme = "notch.popOutsFollowingTheme"
        static let bubbleColoursSettled = "notch.bubbleColoursSettled"
        /// 3.87's one switch for every bubble: on becomes every bubble with its own colour.
        static let legacyBubblesFollowTheme = "notch.bubblesFollowTheme"
        static let openTrayOnFileDrag = "openTrayOnFileDrag"
        static let expandedWidth = "nookExpandedWidth"
        static let expandedHeight = "nookExpandedHeight"
        static let fitWidthToProfile = "nookFitWidthToProfile"
        static let dockApps = "dockApps"
        static let folioClipboardHistory = "folio.clipboardHistory"
        static let folioOpensOnClipboard = "folio.opensOnClipboard"
        static let showDockPin = "dock.showPin"
        static let showDockClose = "dock.showClose"
        /// Wisp's old on/off switch (3.33 and earlier), read once: off takes its page out of the dock.
        static let legacyWispEnabled = "wisp.enabled"
        /// Set by 3.31–3.34 when they added Wisp's page to the dock on their own.
        static let legacyWispPageAdded = "dock.wispPageAdded"
        static let wispPageWithdrawn = "dock.wispPageWithdrawn"
        static let legacyWidgets = "nookWidgets"
        static let profiles = "nookProfilesV2"
        static let profilesBackup = "nookProfilesV2.corrupt"
    }

    private struct PersistedProfiles: Codable {
        var profiles: [NookProfile]
        var activeProfileID: UUID
    }

    private let defaults: UserDefaults
    private var profileSaveWorkItem: DispatchWorkItem?
    private(set) var isInteractiveReorderActive = false

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let hasSavedConfiguration = defaults.data(forKey: Keys.profiles) != nil || defaults.data(forKey: Keys.legacyWidgets) != nil
        let persistedDisplayMode = defaults.string(forKey: Keys.displayMode)
        let legacyShowOnAllDisplays = defaults.bool(forKey: Keys.showOnAllDisplays)
        // Keep Awake beside the notch is on for new installs, like a running timer, and
        // off for existing ones, which never showed it (every install that has launched
        // has its dock stored). Written once, so it then reads as a stored choice.
        // The faint pill is off for a new install (no dock stored yet), written once, so an
        // existing install keeps the pill it has. Debug harnesses keep theirs.
        if defaults.object(forKey: NotchGeometry.notchlessHintKey) == nil, defaults.object(forKey: Keys.dockApps) == nil,
           Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" {
            defaults.set(false, forKey: NotchGeometry.notchlessHintKey)
        }
        // Swiping to change songs is on for new installs; an existing install keeps what it has.
        if defaults.object(forKey: Keys.swipeToChangeSongs) == nil, defaults.object(forKey: Keys.dockApps) == nil,
           Bundle.main.bundleIdentifier == "dev.opensource.MacSpaces" {
            defaults.set(true, forKey: Keys.swipeToChangeSongs)
        }
        // The Gateway's old menus become the same rules for an existing install; a new one has none.
        GatewayShare.migrateMenus(defaults, newInstall: defaults.object(forKey: Keys.dockApps) == nil)
        if defaults.object(forKey: Keys.showKeepAwakeLiveActivity) == nil {
            defaults.set(defaults.object(forKey: Keys.dockApps) == nil, forKey: Keys.showKeepAwakeLiveActivity)
        }
        defaults.register(defaults: [
            Keys.expandOnHover: true,
            Keys.hoverDelay: 0.15,
            Keys.displayMode: DisplayTargetMode.primary.rawValue,
            Keys.selectedDisplayIDs: [] as [String],
            Keys.showMusicLiveActivity: true,
            Keys.showPowerLiveActivity: true,
            Keys.showTimerLiveActivity: true,
            Keys.showMeetingLiveActivity: true,
            Keys.showPasteQueueLiveActivity: true,
            Keys.showScreenshotLiveActivity: true,
            Keys.showMicrophoneLiveActivity: true,
            Keys.showFocusLiveActivity: true,
            Keys.showSpacesLiveActivity: false,
            Keys.scrollGesturesEnabled: true,
            Keys.swipeToChangeSongs: false,
            Keys.openTrayOnFileDrag: true,
            Keys.expandedWidth: 860.0,
            Keys.expandedHeight: 250.0,
            Keys.fitWidthToProfile: true,
            Keys.showDockPin: true,
            Keys.showDockClose: true,
        ])

        showDockPin = defaults.bool(forKey: Keys.showDockPin)
        showDockClose = defaults.bool(forKey: Keys.showDockClose)
        expandOnHover = defaults.bool(forKey: Keys.expandOnHover)
        hoverDelay = defaults.double(forKey: Keys.hoverDelay)
        displayMode = persistedDisplayMode
            .flatMap(DisplayTargetMode.init(rawValue:))
            ?? (legacyShowOnAllDisplays ? .all : .primary)
        selectedDisplayIDs = defaults.stringArray(forKey: Keys.selectedDisplayIDs) ?? []
        showMusicLiveActivity = defaults.bool(forKey: Keys.showMusicLiveActivity)
        showPowerLiveActivity = defaults.bool(forKey: Keys.showPowerLiveActivity)
        showTimerLiveActivity = defaults.bool(forKey: Keys.showTimerLiveActivity)
        showKeepAwakeLiveActivity = defaults.bool(forKey: Keys.showKeepAwakeLiveActivity)
        showMeetingLiveActivity = defaults.bool(forKey: Keys.showMeetingLiveActivity)
        showPasteQueueLiveActivity = defaults.bool(forKey: Keys.showPasteQueueLiveActivity)
        showScreenshotLiveActivity = defaults.bool(forKey: Keys.showScreenshotLiveActivity)
        hiddenInApps = defaults.stringArray(forKey: Keys.hiddenInApps) ?? []
        showMicrophoneLiveActivity = defaults.bool(forKey: Keys.showMicrophoneLiveActivity)
        showFocusLiveActivity = defaults.bool(forKey: Keys.showFocusLiveActivity)
        showSpacesLiveActivity = defaults.bool(forKey: Keys.showSpacesLiveActivity)
        popOutShapes = defaults.dictionary(forKey: Keys.popOutShapes) as? [String: String] ?? [:]
        notchlessHint = defaults.object(forKey: NotchGeometry.notchlessHintKey) as? Bool ?? true
        scrollGesturesEnabled = defaults.bool(forKey: Keys.scrollGesturesEnabled)
        swipeToChangeSongs = defaults.bool(forKey: Keys.swipeToChangeSongs)
        if defaults.object(forKey: Keys.popOutsFollowingTheme) == nil, defaults.bool(forKey: Keys.legacyBubblesFollowTheme) {
            defaults.set(NotchPopOut.allCases.map(\.rawValue).sorted(), forKey: Keys.popOutsFollowingTheme)
        }
        defaults.removeObject(forKey: Keys.legacyBubblesFollowTheme)
        // These always wore the theme's colour, so an existing install keeps that; a new one
        // starts with each bubble's own. Done once, so unticking one later stays unticked.
        if !defaults.bool(forKey: Keys.bubbleColoursSettled) {
            if defaults.object(forKey: Keys.dockApps) != nil {
                let followed = Set(defaults.stringArray(forKey: Keys.popOutsFollowingTheme) ?? [])
                defaults.set(followed.union(NotchPopOut.alwaysThemedBefore3_91.map(\.rawValue)).sorted(), forKey: Keys.popOutsFollowingTheme)
            }
            defaults.set(true, forKey: Keys.bubbleColoursSettled)
        }
        popOutsFollowingTheme = Set(defaults.stringArray(forKey: Keys.popOutsFollowingTheme) ?? [])
        openTrayOnFileDrag = defaults.bool(forKey: Keys.openTrayOnFileDrag)
        expandedWidth = defaults.double(forKey: Keys.expandedWidth)
        expandedHeight = defaults.double(forKey: Keys.expandedHeight)
        fitWidthToProfile = defaults.bool(forKey: Keys.fitWidthToProfile)
        // Unknown pages from a newer build are skipped, never fatal. Merged pages are kept
        // until `mergingRetiredPages` below puts their new home in their place.
        let hadStoredDock = defaults.object(forKey: Keys.dockApps) != nil
        var seenPages = Set<NotchTab>()
        var savedDock = (defaults.stringArray(forKey: Keys.dockApps)?
            .compactMap(NotchTab.init(rawValue:))
            .filter { (NotchTab.appPages.contains($0) || $0.mergedInto != nil) && seenPages.insert($0).inserted })
            ?? (hasSavedConfiguration ? NotchTab.legacyDock : NotchTab.defaultDock)
        // Offer the integrated call and voice pages once; later removals stay removed.
        if !defaults.bool(forKey: "dock.communicationPagesAdded") {
            for page in [NotchTab.meetings, .dictation] where !savedDock.contains(page) { savedDock.append(page) }
            defaults.set(savedDock.map(\.rawValue), forKey: Keys.dockApps)
            defaults.set(true, forKey: "dock.communicationPagesAdded")
        }
        // The Clock page (2.100) is offered once too.
        if !defaults.bool(forKey: "dock.clockPageAdded") {
            if !savedDock.contains(.clock) { savedDock.append(.clock) }
            defaults.set(savedDock.map(\.rawValue), forKey: Keys.dockApps)
            defaults.set(true, forKey: "dock.clockPageAdded")
        }
        // Wisp ships off: its page is added only from Settings → Apps. 3.31–3.34 put it in
        // every dock (`dock.wispPageAdded`), so a dock that got it that way loses it once,
        // nothing else moving, unless 3.31–3.33's switch was explicitly turned back on.
        // Adding it back afterwards sticks.
        if !defaults.bool(forKey: Keys.wispPageWithdrawn) {
            if defaults.bool(forKey: Keys.legacyWispPageAdded), savedDock.contains(.wisp),
               defaults.object(forKey: Keys.legacyWispEnabled) as? Bool != true {
                savedDock.removeAll { $0 == .wisp }
                defaults.set(savedDock.map(\.rawValue), forKey: Keys.dockApps)
            }
            defaults.set(true, forKey: Keys.wispPageWithdrawn)
        }
        // Wisp is on exactly when its page is in the dock: an install that had turned it
        // off loses the page once, and the old switch is forgotten so adding it back sticks.
        if defaults.object(forKey: Keys.legacyWispEnabled) != nil {
            if !defaults.bool(forKey: Keys.legacyWispEnabled) {
                savedDock.removeAll { $0 == .wisp }
                defaults.set(savedDock.map(\.rawValue), forKey: Keys.dockApps)
            }
            defaults.removeObject(forKey: Keys.legacyWispEnabled)
        }

        // The Clipboard page became Folio's Clipboard place. A dock that had it keeps the
        // history coming, and gets Folio opening there unless Folio was already in it.
        // A new install, whose starting dock had Clipboard, keeps the history too.
        if defaults.object(forKey: Keys.folioClipboardHistory) == nil {
            let hadClipboard = hadStoredDock ? savedDock.contains(.clipboard) : !hasSavedConfiguration
            defaults.set(hadClipboard, forKey: Keys.folioClipboardHistory)
            if savedDock.contains(.clipboard), !savedDock.contains(.tray) { defaults.set(true, forKey: Keys.folioOpensOnClipboard) }
        }
        folioClipboardHistory = defaults.bool(forKey: Keys.folioClipboardHistory)
        folioOpensOnClipboard = defaults.bool(forKey: Keys.folioOpensOnClipboard)
        // Dictation became part of Studio and Clipboard part of Folio: a dock that had either
        // of a pair gets its page once, where the first of them was (Folio keeps its own place);
        // the rest keeps its order.
        let mergedDock = Self.mergingRetiredPages(savedDock)
        if mergedDock != savedDock {
            savedDock = mergedDock
            defaults.set(savedDock.map(\.rawValue), forKey: Keys.dockApps)
        }

        dockApps = savedDock

        let storedProfileData = defaults.data(forKey: Keys.profiles)
        let decodedProfiles = storedProfileData.flatMap {
            try? JSONDecoder().decode(PersistedProfiles.self, from: $0)
        }
        // Stored but undecodable means the layouts are still in there and we
        // simply cannot read them. Keep a copy and stay off the write path so a
        // downgrade or a bad key does not erase the user's Nooks.
        let hasUnreadableProfiles = storedProfileData != nil && decodedProfiles == nil
        if hasUnreadableProfiles, let storedProfileData {
            defaults.set(storedProfileData, forKey: Keys.profilesBackup)
        }
        profilesUnreadable = hasUnreadableProfiles

        if let persisted = decodedProfiles, !persisted.profiles.isEmpty {
            profiles = persisted.profiles
            activeProfileID = persisted.activeProfileID
        } else if let legacyData = defaults.data(forKey: Keys.legacyWidgets),
                  let legacyNames = try? JSONDecoder().decode([String].self, from: legacyData) {
            var seen = Set<NookWidgetKind>()
            let legacyWidgets = legacyNames.compactMap { NookWidgetKind.moved[$0] ?? NookWidgetKind(rawValue: $0) }
                .filter { seen.insert($0).inserted }
            let migrated = NookProfile(id: UUID(), name: "Current", widgets: legacyWidgets)
            profiles = [migrated]
            activeProfileID = migrated.id
        } else {
            // Only genuinely new configurations receive the starter layout.
            // Unreadable saved profiles remain recoverable without enabling features.
            let starter = NookProfile(id: UUID(), name: "Home",
                                      widgets: hasSavedConfiguration ? [] : Self.starterWidgets,
                                      widgetSizes: hasSavedConfiguration ? nil : Self.starterSizes)
            profiles = [starter]
            activeProfileID = starter.id
        }

        if !hasUnreadableProfiles && !defaults.bool(forKey: "profiles.neutralStarterName") {
            if profiles.count == 1, ["My Nook", "My Notepad"].contains(profiles[0].name) {
                profiles[0].name = "Home"
            }
            defaults.set(true, forKey: "profiles.neutralStarterName")
        }
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles[0].id
        }
        if !hasUnreadableProfiles {
            saveProfilesNow()
        }
    }

    var activeProfile: NookProfile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    var widgets: [NookWidgetKind] {
        get { activeProfile.widgets }
        set {
            guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
            profiles[index].widgets = newValue
        }
    }

    /// A saved dock with each retired page replaced by the page it now lives in, once,
    /// at the first of their positions. A dock with none of them is returned unchanged.
    static func mergingRetiredPages(_ dock: [NotchTab]) -> [NotchTab] {
        var result: [NotchTab] = []
        for page in dock {
            let target = page.mergedInto ?? page
            if page == .clipboard, dock.contains(.tray) { continue }
            if !result.contains(target) { result.append(target) }
        }
        return result
    }

    /// A page added to a dock goes beside its group (`NotchTab.groups`): after the last page
    /// of the group that comes before it, else before the first that comes after it, else at the end.
    static func adding(_ page: NotchTab, to dock: [NotchTab]) -> [NotchTab] {
        var dock = dock
        guard let group = page.group?.pages, let rank = group.firstIndex(of: page) else { dock.append(page); return dock }
        let rankOf = { (other: NotchTab) in group.firstIndex(of: other) }
        if let earlier = dock.lastIndex(where: { rankOf($0).map { $0 < rank } ?? false }) {
            dock.insert(page, at: earlier + 1)
        } else if let later = dock.firstIndex(where: { rankOf($0).map { $0 > rank } ?? false }) {
            dock.insert(page, at: later)
        } else {
            dock.append(page)
        }
        return dock
    }

    func setDockApp(_ page: NotchTab, shown: Bool) {
        guard NotchTab.appPages.contains(page) else { return }
        if shown {
            guard !dockApps.contains(page) else { return }
            dockApps = Self.adding(page, to: dockApps)
        } else {
            dockApps.removeAll { $0 == page }
        }
    }

    func moveDockApp(_ page: NotchTab, offset: Int) {
        guard let index = dockApps.firstIndex(of: page), dockApps.indices.contains(index + offset) else { return }
        dockApps.swapAt(index, index + offset)
    }

    /// Moves a dock page to a position (clamped), shifting the others along.
    func moveDockApp(_ page: NotchTab, to target: Int) {
        guard let index = dockApps.firstIndex(of: page) else { return }
        let destination = min(max(0, target), dockApps.count - 1)
        guard destination != index else { return }
        var pages = dockApps
        pages.remove(at: index)
        pages.insert(page, at: destination)
        dockApps = pages
    }

    func setEnabled(_ enabled: Bool, for kind: NookWidgetKind) {
        if enabled {
            guard !widgets.contains(kind) else { return }
            widgets.append(kind)
        } else {
            widgets.removeAll { $0 == kind }
        }
    }

    var widgetSizes: [NookWidgetKind: NookWidgetSize] {
        var sizes: [NookWidgetKind: NookWidgetSize] = [:]
        for (raw, size) in activeProfile.widgetSizes ?? [:] {
            if let kind = NookWidgetKind(rawValue: raw) { sizes[kind] = size }
        }
        return sizes
    }

    func size(for kind: NookWidgetKind) -> NookWidgetSize {
        kind.resolvedSize(widgetSizes[kind])
    }

    func setSize(_ size: NookWidgetSize, for kind: NookWidgetKind) {
        guard kind.supportedSizes.contains(size),
              let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
        var sizes = profiles[index].widgetSizes ?? [:]
        sizes[kind.rawValue] = size == kind.defaultSize ? nil : size
        profiles[index].widgetSizes = sizes.isEmpty ? nil : sizes
    }

    func moveWidget(_ kind: NookWidgetKind, offset: Int) {
        guard let index = widgets.firstIndex(of: kind) else { return }
        let destination = index + offset
        guard widgets.indices.contains(destination) else { return }
        widgets.swapAt(index, destination)
    }

    func moveWidget(_ kind: NookWidgetKind, to target: NookWidgetKind) {
        guard let sourceIndex = widgets.firstIndex(of: kind),
              let targetIndex = widgets.firstIndex(of: target),
              sourceIndex != targetIndex else { return }
        var reordered = widgets
        let moved = reordered.remove(at: sourceIndex)
        reordered.insert(moved, at: targetIndex)
        widgets = reordered
    }

    /// Commit the locally rendered drag order once, on pointer release.
    func setWidgetOrder(_ order: [NookWidgetKind]) {
        guard order != widgets,
              order.count == widgets.count,
              Set(order) == Set(widgets) else { return }
        widgets = order
    }

    /// Reordering is rendered from the published profile immediately, while
    /// disk persistence waits until the pointer is released. This keeps drag
    /// updates free of encoding and UserDefaults work.
    func beginInteractiveReorder() {
        isInteractiveReorderActive = true
        profileSaveWorkItem?.cancel()
        profileSaveWorkItem = nil
    }

    func endInteractiveReorder() {
        guard isInteractiveReorderActive else { return }
        isInteractiveReorderActive = false
        scheduleProfileSave()
    }

    /// A display rebuild can remove the dragged view before SwiftUI delivers
    /// `DragGesture.onEnded`. Never allow that cancellation to strand profile
    /// persistence in its suspended state.
    func cancelInteractiveReorder() {
        guard isInteractiveReorderActive else { return }
        isInteractiveReorderActive = false
        scheduleProfileSave()
    }

    func addProfile(named name: String, copyingCurrent: Bool = false) {
        let profile = NookProfile(
            id: UUID(),
            name: name,
            widgets: copyingCurrent ? activeProfile.widgets : [],
            widgetWidths: copyingCurrent ? activeProfile.widgetWidths : nil,
            widgetSizes: copyingCurrent ? activeProfile.widgetSizes : nil
        )
        profiles.append(profile)
        activeProfileID = profile.id
    }

    /// The dock symbol for a Home: its own choice, or a default by position.
    func symbol(for profile: NookProfile) -> String {
        if let symbol = profile.symbol { return symbol }
        let index = profiles.firstIndex(where: { $0.id == profile.id }) ?? 0
        return NookProfile.symbols[index % 6]
    }

    func setSymbol(_ symbol: String, for profile: NookProfile) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].symbol = symbol
    }

    func renameProfile(_ profile: NookProfile, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = name
    }

    func removeProfile(_ profile: NookProfile) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = profiles[0].id
        }
    }

    /// Explicit reset restores the same editable starter layout as first launch.
    func resetToDefaults() {
        profileSaveWorkItem?.cancel()
        profileSaveWorkItem = nil
        isInteractiveReorderActive = false

        expandOnHover = true
        hoverDelay = 0.15
        displayMode = .primary
        selectedDisplayIDs = []
        showMusicLiveActivity = true
        showPowerLiveActivity = true
        showTimerLiveActivity = true
        showKeepAwakeLiveActivity = true
        showMeetingLiveActivity = true
        showPasteQueueLiveActivity = true
        showScreenshotLiveActivity = true
        showMicrophoneLiveActivity = true
        showFocusLiveActivity = true
        showSpacesLiveActivity = false
        popOutShapes = [:]
        notchlessHint = false
        scrollGesturesEnabled = true
        swipeToChangeSongs = true
        popOutsFollowingTheme = []
        openTrayOnFileDrag = true
        expandedWidth = 860
        expandedHeight = 250
        fitWidthToProfile = true
        dockApps = NotchTab.defaultDock
        folioClipboardHistory = true
        folioOpensOnClipboard = false
        showDockPin = true
        showDockClose = true

        let profile = NookProfile(id: UUID(), name: "Home", widgets: Self.starterWidgets, widgetSizes: Self.starterSizes)
        profiles = [profile]
        activeProfileID = profile.id
        flushPersistence()
    }

    private func scheduleProfileSave() {
        guard !isInteractiveReorderActive else { return }
        profileSaveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveProfilesNow()
        }
        profileSaveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    func flushPersistence() {
        isInteractiveReorderActive = false
        profileSaveWorkItem?.cancel()
        profileSaveWorkItem = nil
        saveProfilesNow()
    }

    private func saveProfilesNow() {
        guard !profiles.isEmpty, !profilesUnreadable else { return }
        let persisted = PersistedProfiles(
            profiles: profiles,
            activeProfileID: activeProfileID
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        defaults.set(data, forKey: Keys.profiles)
    }
}

/// The two shapes a pop-out beside the camera can take.
enum NotchBubbleShape: String, CaseIterable {
    case circle, squircle

    var title: String { self == .circle ? "Circle" : "Squircle" }
}

/// What can pop out beside the camera, each with its own shape.
enum NotchPopOut: String, CaseIterable, Identifiable {
    case music, timer, agents, keepAwake, meeting, screenshot, pasteQueue, power, system, spaces

    var id: String { rawValue }

    var title: String {
        switch self {
        case .music: return "Music"
        case .timer: return "Timers"
        case .agents: return "Agents"
        case .keepAwake: return "Keep Awake"
        case .meeting: return "Video meeting"
        case .screenshot: return "Screenshot"
        case .pasteQueue: return "Paste queue"
        case .power: return "Battery"
        case .system: return "System controls"
        case .spaces: return "Desktop changes"
        }
    }

    var symbol: String {
        switch self {
        case .music: return "music.note"
        case .timer: return "timer"
        case .agents: return "terminal.fill"
        case .keepAwake: return "cup.and.saucer.fill"
        case .meeting: return "video.fill"
        case .screenshot: return "camera.viewfinder"
        case .pasteQueue: return "list.clipboard.fill"
        case .power: return "battery.25"
        case .system: return "moon.fill"
        case .spaces: return "square.on.square"
        }
    }

    /// What they've always been: the song like the album cover it holds, the rest round.
    var defaultShape: NotchBubbleShape { self == .music ? .squircle : .circle }

    /// The bubbles that had no colour of their own until 3.91.
    static let alwaysThemedBefore3_91: [NotchPopOut] = [.keepAwake, .meeting, .screenshot, .pasteQueue, .power, .spaces]
}
