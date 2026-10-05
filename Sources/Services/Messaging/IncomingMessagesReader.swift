import Foundation
import SQLite3

struct IncomingMessage: Identifiable, Equatable {
    let id: Int64
    let conversationID: String
    let sender: String
    let text: String
}

/// Read-only, bounded adapter for the macOS Messages database. No writes, no
/// copied database, no history import. An unsupported schema fails closed.
struct IncomingMessagesReader {
    let url: URL
    func read(after cursor: Int64?) throws -> (cursor: Int64, messages: [IncomingMessage]) {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw Failure.access
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 150)
        func readFailure() -> Failure {
            let code = sqlite3_errcode(db)
            return code == SQLITE_BUSY || code == SQLITE_LOCKED ? .busy : .schema
        }
        func prepare(_ sql: String) throws -> OpaquePointer {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else { throw readFailure() }
            return statement
        }
        let maximum = try prepare("SELECT COALESCE(MAX(ROWID), 0) FROM message")
        defer { sqlite3_finalize(maximum) }
        guard sqlite3_step(maximum) == SQLITE_ROW else { throw readFailure() }
        let upper = sqlite3_column_int64(maximum, 0)
        guard let cursor, upper >= cursor else { return (upper, []) }
        let query = try prepare("""
        SELECT m.ROWID, c.guid, COALESCE(h.id, ''), COALESCE(substr(m.text, 1, 1000), ''), m.attributedBody
        FROM message m
        JOIN chat_message_join j ON j.message_id = m.ROWID
        JOIN chat c ON c.ROWID = j.chat_id
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        WHERE m.ROWID > ? AND m.ROWID <= ? AND m.is_from_me = 0
        ORDER BY m.ROWID DESC LIMIT 20
        """)
        defer { sqlite3_finalize(query) }
        sqlite3_bind_int64(query, 1, cursor); sqlite3_bind_int64(query, 2, upper)
        var rows: [IncomingMessage] = []
        func string(_ column: Int32) -> String {
            guard let text = sqlite3_column_text(query, column) else { return "" }
            return String(cString: text)
        }
        var step = sqlite3_step(query)
        while step == SQLITE_ROW {
            var body = string(3)
            // Recent macOS keeps most message text only in attributedBody.
            if body.isEmpty, let blob = sqlite3_column_blob(query, 4) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(query, 4)))
                body = TypedStreamText.decode(data).map { String($0.prefix(1000)) } ?? ""
            }
            rows.append(.init(id: sqlite3_column_int64(query, 0), conversationID: string(1), sender: string(2), text: body.isEmpty ? "New message — open Messages to view" : body))
            step = sqlite3_step(query)
        }
        guard step == SQLITE_DONE else { throw readFailure() }
        return (upper, rows)
    }
    enum Failure: LocalizedError, Equatable {
        case access, schema, busy
        var errorDescription: String? {
            switch self {
            case .access: return "Incoming Messages needs Full Disk Access. Enable MacSpaces in System Settings, then retry."
            case .busy: return "Messages is updating. Incoming reception will retry automatically."
            case .schema: return "This Messages database could not be read. Open Messages; no data was changed."
            }
        }
    }
}

/// The plain text inside a Messages `attributedBody` (an NSAttributedString in
/// the old "typedstream" archive format), read directly from the bytes so no
/// archived objects are ever instantiated.
enum TypedStreamText {
    static func decode(_ data: Data) -> String? {
        let bytes = [UInt8](data)
        let marker = Array("NSString".utf8)
        guard let start = firstIndex(of: marker, in: bytes) else { return nil }
        // After the class name: a few type bytes, then '+' and the string's length.
        var index = start + marker.count
        while index < bytes.count, bytes[index] != 0x2B { index += 1 }
        index += 1
        guard index < bytes.count else { return nil }
        var length = Int(bytes[index]); index += 1
        if length == 0x81 {
            guard index + 2 <= bytes.count else { return nil }
            length = Int(bytes[index]) | Int(bytes[index + 1]) << 8; index += 2
        } else if length == 0x82 {
            guard index + 4 <= bytes.count else { return nil }
            length = (0..<4).reduce(0) { $0 | Int(bytes[index + $1]) << (8 * $1) }; index += 4
        }
        guard length > 0, index + length <= bytes.count else { return nil }
        let text = String(decoding: bytes[index..<(index + length)], as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    private static func firstIndex(of needle: [UInt8], in haystack: [UInt8]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        for i in 0...(haystack.count - needle.count) where haystack[i] == needle[0] {
            if Array(haystack[i..<(i + needle.count)]) == needle { return i }
        }
        return nil
    }
}

/// The Messages page's inbox: recent conversations and one conversation's
/// latest messages, read-only from the same database while the page shows.
/// Nothing is copied or kept after the page closes.
struct MessageInboxReader {
    struct Chat: Identifiable, Equatable {
        let id: String          // chat guid, the same id Messages' scripting uses
        let groupName: String
        let handle: String
        let lastText: String
        let lastFromMe: Bool
        let lastDate: Date
    }

    struct Line: Identifiable, Equatable {
        let id: Int64
        let fromMe: Bool
        let text: String
        let date: Date
        let sender: String
    }

    let url: URL

    func chats(limit: Int = 40) throws -> [Chat] {
        try query("""
        SELECT c.guid, COALESCE(c.display_name, ''),
               COALESCE((SELECT h.id FROM chat_handle_join ch JOIN handle h ON h.ROWID = ch.handle_id WHERE ch.chat_id = c.ROWID LIMIT 1), ''),
               COALESCE(substr(m.text, 1, 300), ''), m.attributedBody, m.is_from_me, m.date
        FROM chat c
        JOIN message m ON m.ROWID = (SELECT MAX(message_id) FROM chat_message_join WHERE chat_id = c.ROWID)
        ORDER BY m.date DESC LIMIT ?
        """, bind: { sqlite3_bind_int($0, 1, Int32(limit)) }) { row in
            Chat(id: row.string(0), groupName: row.string(1), handle: row.string(2),
                 lastText: row.body(3, 4), lastFromMe: row.int(5) == 1, lastDate: row.date(6))
        }
    }

    func thread(_ chatID: String, limit: Int = 50) throws -> [Line] {
        try query("""
        SELECT m.ROWID, m.is_from_me, COALESCE(substr(m.text, 1, 2000), ''), m.attributedBody, m.date, COALESCE(h.id, '')
        FROM message m
        JOIN chat_message_join j ON j.message_id = m.ROWID
        JOIN chat c ON c.ROWID = j.chat_id
        LEFT JOIN handle h ON h.ROWID = m.handle_id
        WHERE c.guid = ? ORDER BY m.ROWID DESC LIMIT ?
        """, bind: { statement in
            sqlite3_bind_text(statement, 1, chatID, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            sqlite3_bind_int(statement, 2, Int32(limit))
        }) { row in
            Line(id: row.int(0), fromMe: row.int(1) == 1, text: row.body(2, 3), date: row.date(4), sender: row.string(5))
        }
        .reversed()
    }

    struct Row {
        let statement: OpaquePointer
        func string(_ column: Int32) -> String {
            guard let text = sqlite3_column_text(statement, column) else { return "" }
            return String(cString: text)
        }
        func int(_ column: Int32) -> Int64 { sqlite3_column_int64(statement, column) }
        /// Messages stores dates as nanoseconds (or, on old databases, seconds) since 2001.
        func date(_ column: Int32) -> Date {
            let raw = Double(sqlite3_column_int64(statement, column))
            return Date(timeIntervalSinceReferenceDate: raw > 1e12 ? raw / 1e9 : raw)
        }
        /// The text column, or the text inside attributedBody when that's empty.
        func body(_ text: Int32, _ attributed: Int32) -> String {
            let plain = string(text)
            if !plain.isEmpty { return plain }
            if let blob = sqlite3_column_blob(statement, attributed) {
                let data = Data(bytes: blob, count: Int(sqlite3_column_bytes(statement, attributed)))
                if let decoded = TypedStreamText.decode(data) { return decoded }
            }
            return "Attachment"
        }
    }

    private func query<T>(_ sql: String, bind: (OpaquePointer) -> Void, _ make: (Row) -> T) throws -> [T] {
        var db: OpaquePointer?
        guard sqlite3_open_v2(url.path, &db, SQLITE_OPEN_READONLY | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK else {
            if let db { sqlite3_close(db) }
            throw IncomingMessagesReader.Failure.access
        }
        defer { sqlite3_close(db) }
        sqlite3_busy_timeout(db, 150)
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            let code = sqlite3_errcode(db)
            throw code == SQLITE_BUSY || code == SQLITE_LOCKED ? IncomingMessagesReader.Failure.busy : IncomingMessagesReader.Failure.schema
        }
        defer { sqlite3_finalize(statement) }
        bind(statement)
        var rows: [T] = []
        while sqlite3_step(statement) == SQLITE_ROW { rows.append(make(Row(statement: statement))) }
        return rows
    }
}
