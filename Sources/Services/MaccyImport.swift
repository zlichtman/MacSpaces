import AppKit
import SQLite3

/// Reads Maccy's history store (a Core Data / SwiftData SQLite file) read-only,
/// keeping the formats MacSpaces records and leaving out anything filtered or
/// shaped like a credential. Pins stay pinned.
enum MaccyImport {
    static func read(_ url: URL, filter: ClipboardFilter) -> [ClipboardEntry] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else { sqlite3_close(db); return [] }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = """
        SELECT i.Z_PK, COALESCE(i.ZAPPLICATION, ''), COALESCE(i.ZFIRSTCOPIEDAT, 0), COALESCE(i.ZLASTCOPIEDAT, 0),
               COALESCE(i.ZNUMBEROFCOPIES, 1), COALESCE(i.ZPIN, ''), c.ZTYPE, c.ZVALUE
        FROM ZHISTORYITEM i JOIN ZHISTORYITEMCONTENT c ON c.ZITEM = i.Z_PK
        ORDER BY i.ZLASTCOPIEDAT DESC LIMIT 20000
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
        defer { sqlite3_finalize(statement) }
        let allowed = Set(filter.allowedTypes.map(\.rawValue))
        // Same rules as a live copy: concealed/transient markers and ignored types
        // reject the whole item (every type row is seen, not only kept formats).
        let rejecting = Set(ClipboardCapture.sensitiveTypes.map(\.rawValue)).union(filter.ignoredTypes)
        var byItem: [Int64: (app: String, first: Double, last: Double, count: Int, pinned: Bool, values: [String: Data])] = [:]
        var order: [Int64] = []
        var rejected: Set<Int64> = []
        while sqlite3_step(statement) == SQLITE_ROW {
            let id = sqlite3_column_int64(statement, 0)
            guard let typePointer = sqlite3_column_text(statement, 6) else { continue }
            let type = String(cString: typePointer)
            if rejecting.contains(type) { rejected.insert(id); continue }
            guard allowed.contains(type), let blob = sqlite3_column_blob(statement, 7) else { continue }
            let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, 7)))
            if byItem[id] == nil {
                order.append(id)
                byItem[id] = (String(cString: sqlite3_column_text(statement, 1)), sqlite3_column_double(statement, 2),
                              sqlite3_column_double(statement, 3), Int(sqlite3_column_int64(statement, 4)),
                              !(String(cString: sqlite3_column_text(statement, 5))).isEmpty, [:])
            }
            byItem[id]?.values[type] = data
        }
        return order.compactMap { id -> ClipboardEntry? in
            guard !rejected.contains(id), let item = byItem[id], filter.allows(app: item.app) else { return nil }
            let text = item.values["public.utf8-plain-text"].flatMap { String(data: $0, encoding: .utf8) }
                ?? item.values["public.file-url"].flatMap { String(data: $0, encoding: .utf8) }
                ?? (item.values["public.png"] != nil || item.values["public.tiff"] != nil ? "Image" : nil)
            guard let text, !ClipboardSecrets.looksSecret(text), filter.allows(text: text),
                  item.values.values.reduce(0, { $0 + $1.count }) <= 8 * 1024 * 1024 else { return nil }
            var clip = ClipboardEntry(text: text, date: Date(timeIntervalSinceReferenceDate: item.last), isFavorite: item.pinned)
            clip.firstDate = Date(timeIntervalSinceReferenceDate: item.first)
            clip.copyCount = max(1, item.count)
            clip.representations = [item.values]
            clip.sourceBundleID = item.app
            clip.sourceName = NSWorkspace.shared.urlForApplication(withBundleIdentifier: item.app)
                .map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? ""
            return clip
        }
    }
}
