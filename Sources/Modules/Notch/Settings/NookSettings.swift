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
    case pomodoro
    case quickActions
    case systemStats
    case keepAwake
    case terminal
    case devServers
    case calculator
    // The Tsukumo quick bar ("agents") was removed in 2.38; saved profiles that
    // list it drop it on decode.
    case notifications

    var isQuickBar: Bool { self == .notifications }
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
            ("Focus", [.timer, .pomodoro, .notes, .keepAwake]),
            ("Talk", [.notifications]),
            ("Tools", [.terminal, .devServers, .calculator, .clipboard, .shortcuts, .quickActions]),
            ("Status", [.battery, .systemStats, .mirror]),
        ]
        let listed = Set(groups.flatMap(\.1))
        let rest = allCases.filter { !listed.contains($0) }
        return rest.isEmpty ? groups : groups + [("More", rest)]
    }

    var supportedSizes: [NookWidgetSize] {
        switch self {
        case .mirror, .shortcuts, .quickActions: return [.medium, .large]
        case .notifications: return [.medium]
        case .terminal, .devServers, .calculator: return [.medium, .large]
        default: return NookWidgetSize.allCases
        }
    }

    /// The full page behind a widget: tapping its expand button opens it, so a
    /// Home tile is the small form of a page rather than a separate thing.
    var page: NotchTab? {
        switch self {
        case .media: return .music
        case .calendar: return .calendar
        case .todos: return .reminders
        case .timer, .pomodoro: return .timers
        case .notes: return .notes
        case .mirror: return .mirror
        case .weather: return .weather
        case .clipboard: return .clipboard
        case .systemStats, .battery, .keepAwake: return .system
        case .terminal, .devServers: return .terminal
        case .shortcuts, .quickActions: return .shortcuts
        case .notifications: return .messages
        case .clock, .calculator: return nil
        }
    }

    /// Widgets that have always stacked keep doing so for existing profiles.
    var defaultSize: NookWidgetSize { canUseCompactRow ? .small : .medium }

    func resolvedSize(_ size: NookWidgetSize?) -> NookWidgetSize {
        size.flatMap { supportedSizes.contains($0) ? $0 : nil } ?? defaultSize
    }

    func width(for size: NookWidgetSize) -> CGFloat {
        // The Dot clock's board needs room for "06:28 LOS ANGELES".
        if self == .clock, size != .small, UserDefaults.standard.string(forKey: "widget.clock.style") == "dot" {
            return size == .medium ? 320 : 460
        }
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
    /// Visual treatment is owned by the widget rather than the whole surface.
    /// Optional for seamless migration from existing profiles.
    var widgetStyles: [String: WidgetVisualStyle]? = nil
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
        widgetStyles: [String: WidgetVisualStyle]? = nil,
        widgetSizes: [String: NookWidgetSize]? = nil
    ) {
        self.id = id
        self.name = name
        self.widgets = widgets
        self.widgetWidths = widgetWidths
        self.widgetStyles = widgetStyles
        self.widgetSizes = widgetSizes
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, widgets, widgetWidths, widgetStyles, widgetSizes, symbol
    }

    /// A widget kind this build cannot decode is dropped rather than failing
    /// the whole profile and taking every other saved layout with it.
    private struct DecodableKind: Decodable {
        let value: NookWidgetKind?

        init(from decoder: Decoder) throws {
            // 2.68's World Clock is now the Clock in its Dot style.
            if (try? decoder.singleValueContainer().decode(String.self)) == "worldClock" {
                if UserDefaults.standard.string(forKey: "widget.clock.style") == nil {
                    UserDefaults.standard.set("dot", forKey: "widget.clock.style")
                }
                value = .clock
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
        widgetStyles = (try? container.decodeIfPresent(
            [String: WidgetVisualStyle].self,
            forKey: .widgetStyles
        )) ?? nil
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

    @Published var showMicrophoneLiveActivity: Bool {
        didSet {
            defaults.set(showMicrophoneLiveActivity, forKey: Keys.showMicrophoneLiveActivity)
        }
    }

    @Published var showFocusLiveActivity: Bool {
        didSet { defaults.set(showFocusLiveActivity, forKey: Keys.showFocusLiveActivity) }
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
        didSet { scheduleProfileSave() }
    }

    /// App pages in the dock, in order. Home and Settings are always present.
    @Published var dockApps: [NotchTab] {
        didSet { defaults.set(dockApps.map(\.rawValue), forKey: Keys.dockApps) }
    }

    @Published var activeProfileID: UUID {
        didSet { scheduleProfileSave() }
    }

    private enum Keys {
        static let expandOnHover = "expandOnHover"
        static let hoverDelay = "hoverDelay"
        static let showOnAllDisplays = "showOnAllDisplays"
        static let displayMode = "displayTargetMode"
        static let selectedDisplayIDs = "selectedDisplayIDs"
        static let showMusicLiveActivity = "showMusicLiveActivity"
        static let showPowerLiveActivity = "showPowerLiveActivity"
        static let showTimerLiveActivity = "showTimerLiveActivity"
        static let showMeetingLiveActivity = "showMeetingLiveActivity"
        static let hiddenInApps = "hiddenInApps"
        static let showMicrophoneLiveActivity = "showMicrophoneLiveActivity"
        static let showFocusLiveActivity = "showFocusLiveActivity"
        static let scrollGesturesEnabled = "scrollGesturesEnabled"
        static let openTrayOnFileDrag = "openTrayOnFileDrag"
        static let expandedWidth = "nookExpandedWidth"
        static let expandedHeight = "nookExpandedHeight"
        static let fitWidthToProfile = "nookFitWidthToProfile"
        static let dockApps = "dockApps"
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
        defaults.register(defaults: [
            Keys.expandOnHover: true,
            Keys.hoverDelay: 0.15,
            Keys.displayMode: DisplayTargetMode.primary.rawValue,
            Keys.selectedDisplayIDs: [] as [String],
            Keys.showMusicLiveActivity: true,
            Keys.showPowerLiveActivity: true,
            Keys.showTimerLiveActivity: true,
            Keys.showMeetingLiveActivity: true,
            Keys.showMicrophoneLiveActivity: true,
            Keys.showFocusLiveActivity: true,
            Keys.scrollGesturesEnabled: true,
            Keys.openTrayOnFileDrag: true,
            Keys.expandedWidth: 860.0,
            Keys.expandedHeight: 250.0,
            Keys.fitWidthToProfile: true,
        ])

        expandOnHover = defaults.bool(forKey: Keys.expandOnHover)
        hoverDelay = defaults.double(forKey: Keys.hoverDelay)
        displayMode = persistedDisplayMode
            .flatMap(DisplayTargetMode.init(rawValue:))
            ?? (legacyShowOnAllDisplays ? .all : .primary)
        selectedDisplayIDs = defaults.stringArray(forKey: Keys.selectedDisplayIDs) ?? []
        showMusicLiveActivity = defaults.bool(forKey: Keys.showMusicLiveActivity)
        showPowerLiveActivity = defaults.bool(forKey: Keys.showPowerLiveActivity)
        showTimerLiveActivity = defaults.bool(forKey: Keys.showTimerLiveActivity)
        showMeetingLiveActivity = defaults.bool(forKey: Keys.showMeetingLiveActivity)
        hiddenInApps = defaults.stringArray(forKey: Keys.hiddenInApps) ?? []
        showMicrophoneLiveActivity = defaults.bool(forKey: Keys.showMicrophoneLiveActivity)
        showFocusLiveActivity = defaults.bool(forKey: Keys.showFocusLiveActivity)
        scrollGesturesEnabled = defaults.bool(forKey: Keys.scrollGesturesEnabled)
        openTrayOnFileDrag = defaults.bool(forKey: Keys.openTrayOnFileDrag)
        expandedWidth = defaults.double(forKey: Keys.expandedWidth)
        expandedHeight = defaults.double(forKey: Keys.expandedHeight)
        fitWidthToProfile = defaults.bool(forKey: Keys.fitWidthToProfile)
        // Unknown pages from a newer build are skipped, never fatal.
        var seenPages = Set<NotchTab>()
        dockApps = (defaults.stringArray(forKey: Keys.dockApps)?
            .compactMap(NotchTab.init(rawValue:))
            .filter { NotchTab.appPages.contains($0) && seenPages.insert($0).inserted })
            ?? (hasSavedConfiguration ? NotchTab.legacyDock : NotchTab.defaultDock)

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

        if let persisted = decodedProfiles, !persisted.profiles.isEmpty {
            profiles = persisted.profiles
            activeProfileID = persisted.activeProfileID
        } else if let legacyData = defaults.data(forKey: Keys.legacyWidgets),
                  let legacyWidgets = try? JSONDecoder().decode([NookWidgetKind].self, from: legacyData) {
            let migrated = NookProfile(id: UUID(), name: "Current", widgets: legacyWidgets)
            profiles = [migrated]
            activeProfileID = migrated.id
        } else {
            // Only genuinely new configurations receive the starter layout.
            // Unreadable saved profiles remain recoverable without enabling features.
            let starter = NookProfile(id: UUID(), name: "My Nook",
                                      widgets: hasSavedConfiguration ? [] : Self.starterWidgets,
                                      widgetSizes: hasSavedConfiguration ? nil : Self.starterSizes)
            profiles = [starter]
            activeProfileID = starter.id
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

    func setDockApp(_ page: NotchTab, shown: Bool) {
        guard NotchTab.appPages.contains(page) else { return }
        if shown {
            guard !dockApps.contains(page) else { return }
            dockApps.append(page)
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

    func widgetStyle(for kind: NookWidgetKind) -> WidgetVisualStyle {
        .studio
    }

    func setWidgetStyle(_ style: WidgetVisualStyle, for kind: NookWidgetKind) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }
        var styles = profiles[index].widgetStyles ?? [:]
        styles[kind.rawValue] = .studio
        profiles[index].widgetStyles = styles
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
            widgetStyles: copyingCurrent ? activeProfile.widgetStyles : nil,
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
        showMeetingLiveActivity = true
        showMicrophoneLiveActivity = true
        showFocusLiveActivity = true
        scrollGesturesEnabled = true
        openTrayOnFileDrag = true
        expandedWidth = 860
        expandedHeight = 250
        fitWidthToProfile = true
        dockApps = NotchTab.defaultDock

        let profile = NookProfile(id: UUID(), name: "My Nook", widgets: Self.starterWidgets, widgetSizes: Self.starterSizes)
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
        guard !profiles.isEmpty else { return }
        let persisted = PersistedProfiles(
            profiles: profiles,
            activeProfileID: activeProfileID
        )
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        defaults.set(data, forKey: Keys.profiles)
    }
}
