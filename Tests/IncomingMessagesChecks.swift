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
        sql("CREATE TABLE message (text TEXT, handle_id INTEGER, is_from_me INTEGER, is_read INTEGER); CREATE TABLE chat (guid TEXT); CREATE TABLE handle (id TEXT); CREATE TABLE chat_message_join (message_id INTEGER, chat_id INTEGER);")
        sql("INSERT INTO chat VALUES ('chat-exact'); INSERT INTO handle VALUES ('test-person'); INSERT INTO message VALUES ('old history', 1, 0, 0); INSERT INTO chat_message_join VALUES (1, 1);")
        let reader = IncomingMessagesReader(url: url)
        let baseline = try reader.read(after: nil)
        precondition(baseline.cursor == 1 && baseline.messages.isEmpty, "Do not import history")
        sql("INSERT INTO message VALUES ('new incoming', 1, 0, 0), ('my outgoing', 1, 1, 0), ('already read', 1, 0, 1), (NULL, 1, 0, 0); INSERT INTO chat_message_join VALUES (2, 1), (3, 1), (4, 1), (5, 1);")
        let snapshot = try reader.read(after: baseline.cursor)
        precondition(snapshot.cursor == 5 && snapshot.messages.count == 3)
        precondition(snapshot.messages[2].text == "new incoming" && snapshot.messages[2].conversationID == "chat-exact")
        precondition(snapshot.messages[0].text.contains("open Messages"))
        precondition(snapshot.messages[1].text == "already read", "A new arrival must survive being marked read between polls")
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
}
