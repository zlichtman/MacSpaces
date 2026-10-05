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
        SELECT m.ROWID, c.guid, COALESCE(h.id, ''), COALESCE(substr(m.text, 1, 1000), '')
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
            let body = string(3)
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
