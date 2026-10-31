import AppKit
import SQLite3

/// Reads Maccy's history store (a Core Data / SwiftData SQLite file) read-only,
/// keeping the formats MacSpaces records and leaving out anything filtered or
/// shaped like a credential. Pins stay pinned, with Maccy's letter where it's free.
enum MaccyImport {
    /// Why Maccy's store couldn't be read: not there, not a database, or a schema MacSpaces doesn't know.
    struct Unreadable: LocalizedError {
        let reason: String
        var errorDescription: String? { reason }
    }

    /// What an import did, for Settings.
    enum Outcome: Equatable {
        case cancelled
        case unreadable(String)
        case nothingToImport
        case imported(clips: Int, pins: Int)

        var message: String? {
            func count(_ number: Int, _ noun: String) -> String { "\(number) \(noun)\(number == 1 ? "" : "s")" }
            switch self {
            case .cancelled: return nil
            case .unreadable(let reason): return "Couldn't read Maccy's history (\(reason))."
            case .nothingToImport: return "Maccy's history had nothing to import."
            case .imported(0, 0): return "Nothing was kept: your history is full of newer clips."
            case .imported(let clips, 0): return "Imported \(count(clips, "clip"))."
            case .imported(0, let pins): return "Imported \(count(pins, "pin"))."
            case .imported(let clips, let pins): return "Imported \(count(clips, "clip")) and \(count(pins, "pin"))."
            }
        }
    }

    /// Everything importable, or nothing when the store can't be read (see `load`).
    static func read(_ url: URL, filter: ClipboardFilter) -> [ClipboardEntry] {
        (try? load(url, filter: filter)) ?? []
    }

    /// The pins and the newest `historyLimit` other clips: all history could keep.
    /// Maccy's clips arrive newest first.
    static func newest(_ clips: [ClipboardEntry], historyLimit: Int) -> [ClipboardEntry] {
        var ordinary = 0
        return clips.filter { clip in
            if clip.isFavorite { return true }
            ordinary += 1
            return ordinary <= historyLimit
        }
    }

    /// Reads the store; throws `Unreadable` when it can't be opened or isn't Maccy's schema.
    static func load(_ url: URL, filter: ClipboardFilter) throws -> [ClipboardEntry] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
            let reason = db.map { String(cString: sqlite3_errmsg($0)) } ?? "it couldn't be opened"
            sqlite3_close(db)
            throw Unreadable(reason: reason)
        }
        defer { sqlite3_close(db) }
        var statement: OpaquePointer?
        let sql = """
        SELECT i.Z_PK, COALESCE(i.ZAPPLICATION, ''), COALESCE(i.ZFIRSTCOPIEDAT, 0), COALESCE(i.ZLASTCOPIEDAT, 0),
               COALESCE(i.ZNUMBEROFCOPIES, 1), COALESCE(i.ZPIN, ''), c.ZTYPE, c.ZVALUE
        FROM ZHISTORYITEM i JOIN ZHISTORYITEMCONTENT c ON c.ZITEM = i.Z_PK
        ORDER BY i.ZLASTCOPIEDAT DESC LIMIT 20000
        """
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw Unreadable(reason: "not a Maccy history this version can read: \(String(cString: sqlite3_errmsg(db)))")
        }
        defer { sqlite3_finalize(statement) }
        let allowed = Set(filter.allowedTypes.map(\.rawValue))
        // Same rules as a live copy: concealed/transient markers and ignored types
        // reject the whole item (every type row is seen, not only kept formats).
        let rejecting = Set(ClipboardCapture.sensitiveTypes.map(\.rawValue)).union(filter.ignoredTypes)
        var byItem: [Int64: (app: String, first: Double, last: Double, count: Int, pin: String, values: [String: Data])] = [:]
        var order: [Int64] = []
        var rejected: Set<Int64> = []
        while true {
            let step = sqlite3_step(statement)
            if step == SQLITE_DONE { break }
            // A busy, locked or damaged store stops the import rather than bringing in part of it.
            guard step == SQLITE_ROW else { throw Unreadable(reason: String(cString: sqlite3_errmsg(db))) }
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
                              String(cString: sqlite3_column_text(statement, 5)), [:])
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
            var clip = ClipboardEntry(text: text, date: Date(timeIntervalSinceReferenceDate: item.last), isFavorite: !item.pin.isEmpty)
            let letter = item.pin.lowercased()
            clip.pinKey = ClipboardHistory.pinLetters.contains(letter) ? letter : nil
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
