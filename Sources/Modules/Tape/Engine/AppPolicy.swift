import Foundation

struct AppPolicy: Codable, Equatable, Sendable {
    var manageAll = true
    var selected: Set<String> = []
    var excluded: Set<String> = []
    init() {}
    func manages(_ bundleID: String?) -> Bool {
        guard let bundleID else { return manageAll }
        return manageAll ? !excluded.contains(bundleID) : selected.contains(bundleID)
    }
    mutating func setManaged(_ enabled: Bool, bundleID: String) {
        if enabled { selected.insert(bundleID); excluded.remove(bundleID) }
        else { selected.remove(bundleID); excluded.insert(bundleID) }
    }
}
