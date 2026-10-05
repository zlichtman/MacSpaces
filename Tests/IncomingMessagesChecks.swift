import Foundation
import SQLite3

@main enum IncomingMessagesChecks {
    static func main() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("fixture.db")
        var db: OpaquePointer?
        precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        func sql(_ value: String) { precondition(sqlite3_exec(db, value, nil, nil, nil) == SQLITE_OK) }
        sql("CREATE TABLE message (text TEXT, handle_id INTEGER, is_from_me INTEGER, is_read INTEGER, attributedBody BLOB); CREATE TABLE chat (guid TEXT); CREATE TABLE handle (id TEXT); CREATE TABLE chat_message_join (message_id INTEGER, chat_id INTEGER);")
        sql("INSERT INTO chat VALUES ('chat-exact'); INSERT INTO handle VALUES ('test-person'); INSERT INTO message VALUES ('old history', 1, 0, 0, NULL); INSERT INTO chat_message_join VALUES (1, 1);")
        let reader = IncomingMessagesReader(url: url)
        let baseline = try reader.read(after: nil)
        precondition(baseline.cursor == 1 && baseline.messages.isEmpty, "Do not import history")
        sql("INSERT INTO message VALUES ('new incoming', 1, 0, 0, NULL), ('my outgoing', 1, 1, 0, NULL), ('already read', 1, 0, 1, NULL), (NULL, 1, 0, 0, NULL); INSERT INTO chat_message_join VALUES (2, 1), (3, 1), (4, 1), (5, 1);")
        let snapshot = try reader.read(after: baseline.cursor)
        precondition(snapshot.cursor == 5 && snapshot.messages.count == 3)
        precondition(snapshot.messages[2].text == "new incoming" && snapshot.messages[2].conversationID == "chat-exact")
        precondition(snapshot.messages[0].text.contains("open Messages"))
        precondition(snapshot.messages[1].text == "already read", "A new arrival must survive being marked read between polls")
        // Text kept only in attributedBody (an archived NSAttributedString) is read from its bytes.
        for sample in ["Running 10 min late, save me a seat", String(repeating: "long message ", count: 30) + "end"] {
            let archive = NSArchiver.archivedData(withRootObject: NSAttributedString(string: sample))
            precondition(TypedStreamText.decode(archive) == sample, "typedstream text")
        }
        precondition(TypedStreamText.decode(Data([1, 2, 3])) == nil && TypedStreamText.decode(Data()) == nil)
        try notificationChecks(directory)
        let replay = try reader.read(after: snapshot.cursor)
        precondition(replay.messages.isEmpty, "Do not replay notifications")
        let replaced = try reader.read(after: 999)
        precondition(replaced.messages.isEmpty, "Database replacement must rebaseline")
        do { _ = try IncomingMessagesReader(url: directory.appendingPathComponent("missing.db")).read(after: nil); preconditionFailure("Missing store must fail") } catch {}
        precondition(!FileManager.default.fileExists(atPath: directory.appendingPathComponent("missing.db").path), "Reader must not create databases")
        sql("BEGIN EXCLUSIVE")
        do {
            _ = try reader.read(after: snapshot.cursor)
            preconditionFailure("A locked store must be retryable")
        } catch IncomingMessagesReader.Failure.busy {}
        sql("ROLLBACK")
        let recovered = try reader.read(after: snapshot.cursor)
        precondition(recovered.messages.isEmpty)
        sql("DROP TABLE chat")
        do { _ = try reader.read(after: 1); preconditionFailure("Unsupported schema must fail closed") } catch {}
        print("Incoming Messages fixture checks passed: no history import, incoming filtering including read-state races, exact IDs, replay prevention, read-only missing store, schema failure. No personal messages accessed.")
    }

    /// Notification Center's store, as a fixture: app and record tables with property-list records.
    static func notificationChecks(_ directory: URL) throws {
        let url = directory.appendingPathComponent("notifications.db")
        var db: OpaquePointer?
        precondition(sqlite3_open(url.path, &db) == SQLITE_OK)
        defer { sqlite3_close(db) }
        func sql(_ value: String) { precondition(sqlite3_exec(db, value, nil, nil, nil) == SQLITE_OK) }
        sql("CREATE TABLE app (app_id INTEGER PRIMARY KEY, identifier TEXT); CREATE TABLE record (rec_id INTEGER PRIMARY KEY, app_id INTEGER, data BLOB);")
        sql("INSERT INTO app VALUES (1, 'com.example.chat'), (2, 'com.example.calendar');")
        func insert(_ id: Int, app: Int, _ request: [String: Any]) {
            let data = try! PropertyListSerialization.data(fromPropertyList: ["req": request, "app": "ignored"], format: .binary, options: 0)
            var statement: OpaquePointer?
            sqlite3_prepare_v2(db, "INSERT INTO record VALUES (?, ?, ?)", -1, &statement, nil)
            sqlite3_bind_int64(statement, 1, Int64(id)); sqlite3_bind_int64(statement, 2, Int64(app))
            _ = data.withUnsafeBytes { sqlite3_bind_blob(statement, 3, $0.baseAddress, Int32(data.count), unsafeBitCast(-1, to: sqlite3_destructor_type.self)) }
            precondition(sqlite3_step(statement) == SQLITE_DONE); sqlite3_finalize(statement)
        }
        insert(1, app: 1, ["titl": "Old", "body": "history"])
        let reader = SystemNotificationsReader(url: url)
        let baseline = try reader.read(after: nil)
        precondition(baseline.cursor == 1 && baseline.notifications.isEmpty, "No notification history import")
        insert(2, app: 1, ["titl": "Sam", "body": "Lunch?"])
        insert(3, app: 2, ["titl": "Standup", "subt": "in 5 minutes", "body": ""])
        insert(4, app: 2, ["other": "nothing to show"])
        let fresh = try reader.read(after: baseline.cursor)
        precondition(fresh.cursor == 4 && fresh.notifications.map(\.title) == ["Standup", "Sam"], "new, readable notifications only")
        precondition(fresh.notifications[1].bundleID == "com.example.chat" && fresh.notifications[1].body == "Lunch?")
        let replayed = try reader.read(after: fresh.cursor)
        precondition(replayed.notifications.isEmpty, "no replays")
        do { _ = try SystemNotificationsReader(url: directory.appendingPathComponent("absent.db")).read(after: nil); preconditionFailure("missing store") } catch {}
        sql("DROP TABLE record")
        do { _ = try reader.read(after: 1); preconditionFailure("unfamiliar layout fails closed") } catch {}
    }
}
