import Foundation
import SQLite3

/// One notification another app posted, as Notification Center stored it.
struct SystemNotification: Identifiable, Equatable {
    let id: Int64
    let bundleID: String
    let title: String
    let subtitle: String
    let body: String
}

/// Read-only adapter for Notification Center's store
/// (~/Library/Group Containers/group.com.apple.usernoted/db2/db), which needs
/// Full Disk Access. Only notifications delivered after watching starts are
/// returned; nothing is written or copied, and an unfamiliar layout fails closed.
struct SystemNotificationsReader {
    let url: URL

    static var defaultURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Group Containers/group.com.apple.usernoted/db2/db")
    }

    func read(after cursor: Int64?) throws -> (cursor: Int64, notifications: [SystemNotification]) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw IncomingMessagesReader.Failure.access
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 150)
        func failure() -> IncomingMessagesReader.Failure {
            let code = sqlite3_errcode(db)
            if code == SQLITE_BUSY || code == SQLITE_LOCKED { return .busy }
            return code == SQLITE_AUTH || code == SQLITE_CANTOPEN || code == SQLITE_PERM ? .access : .schema
        }
        func prepare(_ sql: String) throws -> OpaquePointer {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw failure() }
            return statement
        }
        let maximum = try prepare("SELECT COALESCE(MAX(rec_id), 0) FROM record")
        defer { sqlite3_finalize(maximum) }
        guard sqlite3_step(maximum) == SQLITE_ROW else { throw failure() }
        let upper = sqlite3_column_int64(maximum, 0)
        guard let cursor, upper >= cursor else { return (upper, []) }
        let query = try prepare("""
        SELECT r.rec_id, COALESCE(a.identifier, ''), r.data
        FROM record r LEFT JOIN app a ON a.app_id = r.app_id
        WHERE r.rec_id > ? AND r.rec_id <= ?
        ORDER BY r.rec_id DESC LIMIT 10
        """)
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, cursor); sqlite3_bind_int64(query, 2, upper)
        var found: [SystemNotification] = []
        var step = sqlite3_step(query)
        while step == SQLITE_ROW {
            let id = sqlite3_column_int64(query, 0)
            let bundle = sqlite3_column_text(query, 1).map { String(cString: $0) } ?? ""
            if let blob = sqlite3_column_blob(query, 2) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(query, 2)))
                if let parsed = Self.parse(data, id: id, bundleID: bundle) { found.append(parsed) }
            }
            step = sqlite3_step(query)
        }
        guard step == SQLITE_DONE else { throw failure() }
        return (upper, found)
    }

    /// The record is a property list; the request ("req") holds title ("titl"),
    /// subtitle ("subt") and body ("body"). The app may also be named inside it.
    static func parse(_ data: Data, id: Int64, bundleID: String) -> SystemNotification? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        let request = plist["req"] as? [String: Any] ?? [:]
        let title = request["titl"] as? String ?? ""
        let subtitle = request["subt"] as? String ?? ""
        let body = request["body"] as? String ?? ""
        guard !(title.isEmpty && subtitle.isEmpty && body.isEmpty) else { return nil }
        let app = bundleID.isEmpty ? (plist["app"] as? String ?? "") : bundleID
        return SystemNotification(id: id, bundleID: app, title: title, subtitle: subtitle,
                                  body: String(body.prefix(400)))
    }
}
