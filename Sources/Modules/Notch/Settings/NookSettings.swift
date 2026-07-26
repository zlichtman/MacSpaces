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

    var id: String { rawValue }

    var title: String {
        switch self {
        case .media: return "Media"
        case .shortcuts: return "Shortcuts"
        case .calendar: return "Calendar"
        case .todos: return "Todos"
        case .timer: return "Timer"
        case .notes: return "Notes"
        case .mirror: return "Mirror"
        case .battery: return "Battery"
        case .clock: return "Clock"
        }
    }

    var systemImage: String {
        switch self {
        case .media: return "music.note"
        case .shortcuts: return "bolt.fill"
        case .calendar: return "calendar"
        case .todos: return "checklist"
        case .timer: return "timer"
        case .notes: return "note.text"
        case .mirror: return "web.camera"
        case .battery: return "battery.100percent"
        case .clock: return "clock"
        }
    }

    var preferredWidth: CGFloat {
        switch self {
        case .media: return 260
        case .calendar, .todos, .notes, .mirror: return 180
        case .shortcuts: return 150
        case .timer, .battery, .clock: return 116
        }
    }

    var canUseCompactRow: Bool {
        switch self {
        case .timer, .battery, .clock:
            return true
        default:
            return false
        }
    }
}

struct NookLayoutItem: Identifiable {
    let kinds: [NookWidgetKind]

    var id: String { kinds.map(\.rawValue).joined(separator: "+") }
    var isStack: Bool { kinds.count == 2 }

    var width: CGFloat {
        kinds.map(\.preferredWidth).max() ?? 0
    }
}

extension Array where Element == NookWidgetKind {
    func nookLayoutItems() -> [NookLayoutItem] {
        var result: [NookLayoutItem] = []
        var index = startIndex
        while index < endIndex {
            let current = self[index]
            let nextIndex = self.index(after: index)
            if current.canUseCompactRow,
               nextIndex < endIndex,
               self[nextIndex].canUseCompactRow {
                result.append(NookLayoutItem(kinds: [current, self[nextIndex]]))
                index = self.index(after: nextIndex)
            } else {
                result.append(NookLayoutItem(kinds: [current]))
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

    init(
        id: UUID,
        name: String,
        widgets: [NookWidgetKind],
        widgetWidths: [String: Double]? = nil,
        widgetStyles: [String: WidgetVisualStyle]? = nil
    ) {
        self.id = id
        self.name = name
        self.widgets = widgets
        self.widgetWidths = widgetWidths
        self.widgetStyles = widgetStyles
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, widgets, widgetWidths, widgetStyles
    }

    /// A widget kind this build cannot decode is dropped rather than failing
    /// the whole profile and taking every other saved layout with it.
    private struct DecodableKind: Decodable {
        let value: NookWidgetKind?

        init(from decoder: Decoder) throws {
            value = try? NookWidgetKind(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        widgets = try container
            .decode([DecodableKind].self, forKey: .widgets)
            .compactMap(\.value)
        widgetWidths = try container.decodeIfPresent(
            [String: Double].self,
            forKey: .widgetWidths
        )
        widgetStyles = (try? container.decodeIfPresent(
            [String: WidgetVisualStyle].self,
            forKey: .widgetStyles
        )) ?? nil
    }
}

/// User preferences and Nook profiles. A profile owns its ordered widget
/// layout, matching the Dock profile model rather than keeping one global
/// Nook arrangement.
@MainActor
final class NookSettings: ObservableObject {
    static let shared = NookSettings()

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

    @Published var showTimerLiveActivity: Bool {
        didSet { defaults.set(showTimerLiveActivity, forKey: Keys.showTimerLiveActivity) }
    }

    @Published var showBluetoothLiveActivity: Bool {
        didSet { defaults.set(showBluetoothLiveActivity, forKey: Keys.showBluetoothLiveActivity) }
    }

    @Published var showVolumeLiveActivity: Bool {
        didSet { defaults.set(showVolumeLiveActivity, forKey: Keys.showVolumeLiveActivity) }
    }

    @Published var showBrightnessLiveActivity: Bool {
        didSet { defaults.set(showBrightnessLiveActivity, forKey: Keys.showBrightnessLiveActivity) }
    }

    @Published var showKeyboardBrightnessLiveActivity: Bool {
        didSet {
            defaults.set(
                showKeyboardBrightnessLiveActivity,
                forKey: Keys.showKeyboardBrightnessLiveActivity
            )
        }
    }

    @Published var showMicrophoneLiveActivity: Bool {
        didSet {
            defaults.set(showMicrophoneLiveActivity, forKey: Keys.showMicrophoneLiveActivity)
        }
    }

    @Published var showFocusLiveActivity: Bool {
        didSet { defaults.set(showFocusLiveActivity, forKey: Keys.showFocusLiveActivity) }
    }

    @Published var showTeleprompterBar: Bool {
        didSet { defaults.set(showTeleprompterBar, forKey: Keys.showTeleprompterBar) }
    }

    /// Applies only while the Nook is closed. The expanded Nook deliberately
    /// leaves all trackpad gestures to its widgets and horizontal scroller.
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
        static let showBluetoothLiveActivity = "showBluetoothLiveActivity"
        static let showVolumeLiveActivity = "showVolumeLiveActivity"
        static let showBrightnessLiveActivity = "showBrightnessLiveActivity"
        static let showKeyboardBrightnessLiveActivity = "showKeyboardBrightnessLiveActivity"
        static let showMicrophoneLiveActivity = "showMicrophoneLiveActivity"
        static let showFocusLiveActivity = "showFocusLiveActivity"
        static let showTeleprompterBar = "showTeleprompterBar"
        static let scrollGesturesEnabled = "scrollGesturesEnabled"
        static let expandedWidth = "nookExpandedWidth"
        static let expandedHeight = "nookExpandedHeight"
        static let fitWidthToProfile = "nookFitWidthToProfile"
        static let legacyWidgets = "nookWidgets"
        static let profiles = "nookProfilesV2"
        static let profilesBackup = "nookProfilesV2.corrupt"
    }

    private struct PersistedProfiles: Codable {
        var profiles: [NookProfile]
        var activeProfileID: UUID
    }

    private let defaults = UserDefaults.standard
    private var profileSaveWorkItem: DispatchWorkItem?
    private(set) var isInteractiveReorderActive = false

    private init() {
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
            Keys.showBluetoothLiveActivity: true,
            Keys.showVolumeLiveActivity: true,
            Keys.showBrightnessLiveActivity: true,
            Keys.showKeyboardBrightnessLiveActivity: true,
            Keys.showMicrophoneLiveActivity: true,
            Keys.showFocusLiveActivity: true,
            Keys.showTeleprompterBar: false,
            Keys.scrollGesturesEnabled: true,
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
        showBluetoothLiveActivity = defaults.bool(forKey: Keys.showBluetoothLiveActivity)
        showVolumeLiveActivity = defaults.bool(forKey: Keys.showVolumeLiveActivity)
        showBrightnessLiveActivity = defaults.bool(forKey: Keys.showBrightnessLiveActivity)
        showKeyboardBrightnessLiveActivity = defaults.bool(
            forKey: Keys.showKeyboardBrightnessLiveActivity
        )
        showMicrophoneLiveActivity = defaults.bool(forKey: Keys.showMicrophoneLiveActivity)
        showFocusLiveActivity = defaults.bool(forKey: Keys.showFocusLiveActivity)
        showTeleprompterBar = defaults.bool(forKey: Keys.showTeleprompterBar)
        scrollGesturesEnabled = defaults.bool(forKey: Keys.scrollGesturesEnabled)
        expandedWidth = defaults.double(forKey: Keys.expandedWidth)
        expandedHeight = defaults.double(forKey: Keys.expandedHeight)
        fitWidthToProfile = defaults.bool(forKey: Keys.fitWidthToProfile)

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
                  let legacyWidgets = try? JSONDecoder().decode([NookWidgetKind].self, from: legacyData),
                  !legacyWidgets.isEmpty {
            let migrated = NookProfile(id: UUID(), name: "Current", widgets: legacyWidgets)
            profiles = [migrated]
            activeProfileID = migrated.id
        } else {
            // Fresh setup begins empty so the user intentionally composes the
            // Nook instead of deleting a demo layout.
            let empty = NookProfile(id: UUID(), name: "My Nook", widgets: [])
            profiles = [empty]
            activeProfileID = empty.id
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

    func setEnabled(_ enabled: Bool, for kind: NookWidgetKind) {
        if enabled {
            guard !widgets.contains(kind) else { return }
            widgets.append(kind)
        } else {
            widgets.removeAll { $0 == kind }
        }
    }

    func widgetStyle(for kind: NookWidgetKind) -> WidgetVisualStyle {
        activeProfile.widgetStyles?[kind.rawValue] ?? .studio
    }

    func setWidgetStyle(_ style: WidgetVisualStyle, for kind: NookWidgetKind) {
        guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else {
            return
        }
        var styles = profiles[index].widgetStyles ?? [:]
        styles[kind.rawValue] = style
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
            widgetStyles: copyingCurrent ? activeProfile.widgetStyles : nil
        )
        profiles.append(profile)
        activeProfileID = profile.id
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
