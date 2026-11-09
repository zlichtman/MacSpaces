import SwiftUI

final class TapeSettings: ObservableObject {
    private typealias Keys = WidgetOptions.Keys
    @Published var gap: Double { didSet { defaults.set(gap, forKey: Keys.tapeGap) } }
    @Published var edgeGap: Double { didSet { defaults.set(edgeGap, forKey: Keys.tapeEdgeGap) } }
    @Published var centering: CenteringMode { didSet { defaults.set(centering.rawValue, forKey: Keys.tapeCentering) } }
    /// Move windows at once. The Mac's own Reduce Motion always counts too (`Animator`).
    @Published var reduceMotion: Bool { didSet { defaults.set(reduceMotion, forKey: Keys.tapeReduceMotion) } }
    @Published var sharedWidths: Bool { didSet { defaults.set(sharedWidths, forKey: Keys.tapeSharedWidths) } }
    @Published var appPolicy: AppPolicy { didSet { defaults.set(try? JSONEncoder().encode(appPolicy), forKey: Keys.tapeAppPolicy) } }
    @Published var appPaths: [String: String] { didSet { defaults.set(appPaths, forKey: Keys.tapeAppPaths) } }
    @Published var disabledDisplays: Set<String> { didSet { defaults.set(Array(disabledDisplays).sorted(), forKey: Keys.tapeDisabledDisplays) } }
    @Published var disabledSpaces: Set<String> { didSet { defaults.set(Array(disabledSpaces).sorted(), forKey: Keys.tapeDisabledSpaces) } }
    private let defaults: UserDefaults
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        disabledDisplays = Set(defaults.stringArray(forKey: Keys.tapeDisabledDisplays) ?? [])
        disabledSpaces = Set(defaults.stringArray(forKey: Keys.tapeDisabledSpaces) ?? [])
        gap = defaults.object(forKey: Keys.tapeGap) as? Double ?? 8
        edgeGap = defaults.object(forKey: Keys.tapeEdgeGap) as? Double ?? 8
        centering = CenteringMode(rawValue: defaults.string(forKey: Keys.tapeCentering) ?? "never") ?? .never
        reduceMotion = defaults.object(forKey: Keys.tapeReduceMotion) as? Bool ?? false
        sharedWidths = defaults.bool(forKey: Keys.tapeSharedWidths)
        appPolicy = defaults.data(forKey: Keys.tapeAppPolicy).flatMap { try? JSONDecoder().decode(AppPolicy.self, from: $0) } ?? AppPolicy()
        appPaths = defaults.dictionary(forKey: Keys.tapeAppPaths) as? [String: String] ?? [:]
    }
    /// On the first switch-on only: what's valid in the separate Tape app's settings, once.
    /// Its own domain is only read. Called before the settings object loads.
    static func importOnce(into defaults: UserDefaults, from domain: () -> [String: Any]?) {
        guard !defaults.bool(forKey: Keys.tapeImported) else { return }
        defaults.set(true, forKey: Keys.tapeImported)
        guard let tape = domain() else { return }
        func spacing(_ key: String) -> Double? {
            (tape[key] as? Double).flatMap { $0.isFinite && (0...40).contains($0) ? $0 : nil }
        }
        if let gap = spacing("gap") { defaults.set(gap, forKey: Keys.tapeGap) }
        if let edgeGap = spacing("edgeGap") { defaults.set(edgeGap, forKey: Keys.tapeEdgeGap) }
        if let centering = tape["centering"] as? String, CenteringMode(rawValue: centering) != nil {
            defaults.set(centering, forKey: Keys.tapeCentering)
        }
        if let reduceMotion = tape["reduceMotion"] as? Bool { defaults.set(reduceMotion, forKey: Keys.tapeReduceMotion) }
        if let sharedWidths = tape["layout.sharedWidths"] as? Bool { defaults.set(sharedWidths, forKey: Keys.tapeSharedWidths) }
        if let policy = tape["apps.policy"] as? Data, (try? JSONDecoder().decode(AppPolicy.self, from: policy)) != nil {
            defaults.set(policy, forKey: Keys.tapeAppPolicy)
        }
        if let paths = tape["apps.paths"] as? [String: String] { defaults.set(paths, forKey: Keys.tapeAppPaths) }
        if let displays = tape["displays.disabled"] as? [String] { defaults.set(displays, forKey: Keys.tapeDisabledDisplays) }
    }
    var layout: LayoutOptions { LayoutOptions(gap: gap, edgeGap: edgeGap, centering: centering) }
}
