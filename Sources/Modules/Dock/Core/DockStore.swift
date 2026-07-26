import AppKit
import SwiftUI
import Combine

enum DockPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, left, right

    var id: String { rawValue }
    var isVertical: Bool { self != .bottom }

    var title: String {
        switch self {
        case .bottom: return "Bottom"
        case .left: return "Left"
        case .right: return "Right"
        }
    }
}

/// A named widget layout. Switch between profiles for different workflows
/// (e.g. Work, Focus, Music).
struct DockProfile: Identifiable, Codable, Equatable {
    var id: UUID
    var name: String
    var widgets: [WidgetInstance]

    init(id: UUID, name: String, widgets: [WidgetInstance]) {
        self.id = id
        self.name = name
        self.widgets = widgets
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, widgets
    }

    /// A widget this build cannot decode — a kind added by a newer version, or
    /// one that was renamed — is dropped rather than failing the whole profile
    /// and taking every other saved layout down with it.
    private struct DecodableWidget: Decodable {
        let value: WidgetInstance?

        init(from decoder: Decoder) throws {
            value = try? WidgetInstance(from: decoder)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        widgets = try container
            .decode([DecodableWidget].self, forKey: .widgets)
            .compactMap(\.value)
    }
}

/// Persisted dock configuration: widget profiles plus appearance and
/// behaviour options. Saved as JSON in Application Support.
@MainActor
final class DockStore: ObservableObject {
    static let shared = DockStore()

    @Published var profiles: [DockProfile] { didSet { scheduleSave() } }
    @Published var activeProfileID: UUID { didSet { scheduleSave() } }
    @Published var position: DockPosition { didSet { scheduleSave() } }
    @Published var tileSize: Double { didSet { scheduleSave() } }
    @Published var sideDockWidth: Double { didSet { scheduleSave() } }
    @Published var edgeOffset: Double { didSet { scheduleSave() } }
    @Published var autoHide: Bool { didSet { scheduleSave() } }
    @Published var displayMode: DisplayTargetMode { didSet { scheduleSave() } }
    @Published var selectedDisplayIDs: [String] { didSet { scheduleSave() } }
    @Published var hideDelay: Double { didSet { scheduleSave() } }
    @Published var windowPreviewsEnabled: Bool { didSet { scheduleSave() } }
    @Published var windowPreviewDelay: Double { didSet { scheduleSave() } }
    @Published var windowPreviewLimit: Int { didSet { scheduleSave() } }
    @Published var isDockVisible = true
    @Published private(set) var isInteractiveReorderActive = false
    private var saveWorkItem: DispatchWorkItem?

    // Shared long-lived services used by both MacSpaces modules.
    let nowPlaying = AppServices.shared.nowPlaying
    let clipboard = AppServices.shared.clipboard
    let systemStats = AppServices.shared.systemStats
    let weather = AppServices.shared.weather
    let calendar = AppServices.shared.calendar
    let crypto = AppServices.shared.crypto

    var effectivePosition: DockPosition { position }

    var shouldAutoHide: Bool { autoHide }

    // MARK: - Active profile access

    var activeProfile: DockProfile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    /// Widgets of the active profile. All layout code reads this.
    var widgets: [WidgetInstance] {
        get { activeProfile.widgets }
        set {
            guard let index = profiles.firstIndex(where: { $0.id == activeProfileID }) else { return }
            profiles[index].widgets = newValue
        }
    }

    func add(_ kind: WidgetKind) {
        widgets.append(WidgetInstance(kind: kind))
    }

    func remove(_ instance: WidgetInstance) {
        widgets.removeAll { $0.id == instance.id }
    }

    func duplicate(_ instance: WidgetInstance) {
        guard let index = widgets.firstIndex(of: instance) else { return }
        widgets.insert(
            WidgetInstance(
                kind: instance.kind,
                visualStyle: instance.visualStyle,
                sizeMode: instance.sizeMode
            ),
            at: index + 1
        )
    }

    func setWidgetStyle(_ style: WidgetVisualStyle, for instance: WidgetInstance) {
        guard let index = widgets.firstIndex(where: { $0.id == instance.id }) else {
            return
        }
        widgets[index].visualStyle = style
    }

    func setWidgetSize(
        _ sizeMode: DockWidgetSizeMode,
        for instance: WidgetInstance
    ) {
        guard instance.kind.canUseCompactDockRow,
              let index = widgets.firstIndex(
                where: { $0.id == instance.id }
              ) else { return }
        widgets[index].sizeMode = sizeMode
    }

    func move(_ instance: WidgetInstance, offset: Int) {
        guard let index = widgets.firstIndex(of: instance) else { return }
        let destination = index + offset
        guard widgets.indices.contains(destination) else { return }
        widgets.swapAt(index, destination)
    }

    func move(_ instance: WidgetInstance, to target: WidgetInstance) {
        guard let sourceIndex = widgets.firstIndex(of: instance),
              let targetIndex = widgets.firstIndex(of: target),
              sourceIndex != targetIndex else { return }
        var reordered = widgets
        let moved = reordered.remove(at: sourceIndex)
        reordered.insert(moved, at: targetIndex)
        widgets = reordered
    }

    func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        widgets.move(fromOffsets: source, toOffset: destination)
    }

    /// Commits a locally rendered drag order once, when the pointer is
    /// released. Widget configuration changes made during the drag are
    /// preserved by matching on identity.
    func setWidgetOrder(_ order: [WidgetInstance]) {
        let currentIDs = widgets.map(\.id)
        let orderIDs = order.map(\.id)
        guard Set(currentIDs) == Set(orderIDs),
              currentIDs.count == orderIDs.count,
              currentIDs != orderIDs else { return }

        let currentByID = Dictionary(uniqueKeysWithValues: widgets.map {
            ($0.id, $0)
        })
        widgets = orderIDs.compactMap { currentByID[$0] }
    }

    /// Keep pointer-driven layout updates in memory until the mouse is
    /// released. Encoding and atomic file writes do not belong in drag frames.
    func beginInteractiveReorder() {
        guard !isInteractiveReorderActive else { return }
        isInteractiveReorderActive = true
        saveWorkItem?.cancel()
        saveWorkItem = nil
    }

    func endInteractiveReorder() {
        guard isInteractiveReorderActive else { return }
        isInteractiveReorderActive = false
        scheduleSave()
    }

    func cancelInteractiveReorder() {
        guard isInteractiveReorderActive else { return }
        isInteractiveReorderActive = false
        scheduleSave()
    }

    // MARK: - Profile management

    func addProfile(named name: String, copyingCurrent: Bool = false) {
        let profile = DockProfile(
            id: UUID(),
            name: name,
            widgets: copyingCurrent ? activeProfile.widgets : []
        )
        profiles.append(profile)
        activeProfileID = profile.id
    }

    func removeProfile(_ profile: DockProfile) {
        guard profiles.count > 1 else { return }
        profiles.removeAll { $0.id == profile.id }
        if activeProfileID == profile.id {
            activeProfileID = profiles[0].id
        }
    }

    func renameProfile(_ profile: DockProfile, to name: String) {
        guard let index = profiles.firstIndex(where: { $0.id == profile.id }) else { return }
        profiles[index].name = name
    }

    // MARK: - Persistence

    private struct Persisted: Codable {
        var schemaVersion: Int?
        var profiles: [DockProfile]
        var activeProfileID: UUID
        var position: DockPosition
        var tileSize: Double
        var sideDockWidth: Double?
        var edgeOffset: Double
        var autoHide: Bool
        var showOnAllDisplays: Bool?
        var displayMode: DisplayTargetMode?
        var selectedDisplayIDs: [String]?
        var presentationMode: String?
        var followSystemDock: Bool?
        var hideDelay: Double?
        var windowPreviewsEnabled: Bool?
        var windowPreviewDelay: Double?
        var windowPreviewLimit: Int?
    }

    /// Pre-profiles config shape, for migration.
    private struct LegacyPersisted: Codable {
        var widgets: [WidgetInstance]
        var position: DockPosition
        var tileSize: Double
        var edgeOffset: Double
        var autoHide: Bool
    }

    private static var supportDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacSpaces", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static var configURL: URL {
        supportDirectory.appendingPathComponent("dock.json")
    }

    private static var legacyConfigURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("OpenDock", isDirectory: true)
            .appendingPathComponent("dock.json")
    }

    private init() {
        let outcome = Self.load()
        let persisted: Persisted?
        let hadUnreadableConfig: Bool
        switch outcome {
        case let .loaded(value):
            persisted = value
            hadUnreadableConfig = false
        case .missing:
            persisted = nil
            hadUnreadableConfig = false
        case let .unreadable(url):
            Self.quarantine(url)
            persisted = nil
            hadUnreadableConfig = true
        }

        let loadedProfiles = persisted?.profiles ?? []
        let initialProfiles = loadedProfiles.isEmpty ? [
            DockProfile(id: UUID(), name: "My Dock", widgets: [])
        ] : loadedProfiles
        profiles = initialProfiles
        activeProfileID = persisted?.activeProfileID ?? initialProfiles[0].id
        let savedPosition = persisted?.position ?? .bottom
        if persisted?.presentationMode == "companion",
           persisted?.followSystemDock == true {
            let raw = UserDefaults(suiteName: "com.apple.dock")?
                .string(forKey: "orientation") ?? savedPosition.rawValue
            position = DockPosition(rawValue: raw) ?? savedPosition
        } else {
            position = savedPosition
        }
        let needsCompanionMigration = (persisted?.schemaVersion ?? 1) < 2
        tileSize = needsCompanionMigration ? min(persisted?.tileSize ?? 72, 72) : (persisted?.tileSize ?? 72)
        sideDockWidth = persisted?.sideDockWidth ?? 128
        edgeOffset = needsCompanionMigration ? 4 : (persisted?.edgeOffset ?? 4)
        autoHide = persisted?.autoHide ?? false
        displayMode = persisted?.displayMode
            ?? ((persisted?.showOnAllDisplays ?? false) ? .all : .primary)
        selectedDisplayIDs = persisted?.selectedDisplayIDs ?? []
        hideDelay = persisted?.hideDelay ?? 0.32
        windowPreviewsEnabled = persisted?.windowPreviewsEnabled ?? false
        windowPreviewDelay = persisted?.windowPreviewDelay ?? 0.18
        windowPreviewLimit = persisted?.windowPreviewLimit ?? 6

        // Guard against a stale active id in a hand-edited config.
        if !profiles.contains(where: { $0.id == activeProfileID }) {
            activeProfileID = profiles[0].id
        }

        // Persist the one-time companion-mode migration immediately so future
        // launches never consult Apple Dock preferences again. Skipped when the
        // config was unreadable: the quarantined copy is the user's only record
        // of their layouts, so nothing is written until they change something.
        if !hadUnreadableConfig {
            saveNow()
        }
    }

    /// Distinguishes "no config yet" from "config present but unreadable" so a
    /// first launch and a corrupt file are never treated the same way.
    private enum LoadOutcome {
        case missing
        case loaded(Persisted)
        case unreadable(URL)
    }

    private static func load() -> LoadOutcome {
        let sourceURL = FileManager.default.fileExists(atPath: configURL.path)
            ? configURL
            : legacyConfigURL
        guard let data = try? Data(contentsOf: sourceURL) else { return .missing }

        if let current = try? JSONDecoder().decode(Persisted.self, from: data) {
            return .loaded(current)
        }

        // Migrate a legacy single-layout config into a "Default" profile.
        if let legacy = try? JSONDecoder().decode(LegacyPersisted.self, from: data) {
            let profile = DockProfile(id: UUID(), name: "Default", widgets: legacy.widgets)
            return .loaded(Persisted(schemaVersion: 1,
                                     profiles: [profile],
                                     activeProfileID: profile.id,
                                     position: legacy.position,
                                     tileSize: legacy.tileSize,
                                     sideDockWidth: nil,
                                     edgeOffset: legacy.edgeOffset,
                                     autoHide: legacy.autoHide,
                                     showOnAllDisplays: false,
                                     displayMode: nil,
                                     selectedDisplayIDs: nil,
                                     presentationMode: nil,
                                     followSystemDock: nil,
                                     hideDelay: nil,
                                     windowPreviewsEnabled: nil,
                                     windowPreviewDelay: nil,
                                     windowPreviewLimit: nil))
        }

        return .unreadable(sourceURL)
    }

    /// Moves a config we cannot parse aside instead of letting the next save
    /// overwrite it, so the user's layouts stay recoverable on disk.
    static func quarantine(_ url: URL) {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let destination = url
            .deletingLastPathComponent()
            .appendingPathComponent(
                "\(url.lastPathComponent).corrupt-\(formatter.string(from: Date()))"
            )
        try? FileManager.default.moveItem(at: url, to: destination)
    }

    private func scheduleSave() {
        guard !isInteractiveReorderActive else { return }
        saveWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        saveWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
    }

    func flushPersistence() {
        saveWorkItem?.cancel()
        saveWorkItem = nil
        saveNow()
    }

    private func saveNow() {
        let persisted = Persisted(schemaVersion: 6,
                                  profiles: profiles,
                                  activeProfileID: activeProfileID,
                                  position: position,
                                  tileSize: tileSize,
                                  sideDockWidth: sideDockWidth,
                                  edgeOffset: edgeOffset,
                                  autoHide: autoHide,
                                  showOnAllDisplays: nil,
                                  displayMode: displayMode,
                                  selectedDisplayIDs: selectedDisplayIDs,
                                  presentationMode: "pinned",
                                  followSystemDock: false,
                                  hideDelay: hideDelay,
                                  windowPreviewsEnabled: windowPreviewsEnabled,
                                  windowPreviewDelay: windowPreviewDelay,
                                  windowPreviewLimit: windowPreviewLimit)
        guard let data = try? JSONEncoder().encode(persisted) else { return }
        try? data.write(to: Self.configURL, options: .atomic)
    }

}
