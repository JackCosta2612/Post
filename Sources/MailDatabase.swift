import Foundation
import SQLite3

/// Stores cache metadata and individually replaceable message records in one transaction.
final class MailDatabase {
    // Owned by MailStore's serial cache writer.
    final class Writer {
        private var database: MailDatabase?

        func save(_ snapshot: MailCache, directory: URL) throws {
            if database == nil { database = try MailDatabase(directory: directory) }
            try database?.save(snapshot)
        }
    }

    private var savedMessages: [String: MailMessage]?
    private let database: OpaquePointer
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

    init(directory: URL) throws {
        var handle: OpaquePointer?
        let path = directory.appendingPathComponent("mail-cache.sqlite3").path
        guard sqlite3_open(path, &handle) == SQLITE_OK, let handle else {
            if let handle { sqlite3_close(handle) }
            throw MailError.message("Could not open Post’s mail database.")
        }
        database = handle
        sqlite3_busy_timeout(handle, 5_000)
        try execute("CREATE TABLE IF NOT EXISTS cache_state (id INTEGER PRIMARY KEY CHECK(id = 1), data BLOB NOT NULL)")
        try execute("CREATE TABLE IF NOT EXISTS mail (id TEXT PRIMARY KEY, received REAL NOT NULL, data BLOB NOT NULL)")
        try execute("CREATE INDEX IF NOT EXISTS mail_received ON mail(received DESC, id)")
    }

    deinit { sqlite3_close(database) }

    static func load(from directory: URL) throws -> MailCache? {
        let databaseURL = directory.appendingPathComponent("mail-cache.sqlite3")
        if FileManager.default.fileExists(atPath: databaseURL.path),
           let snapshot = try MailDatabase(directory: directory).load() {
            return snapshot
        }
        let legacy = directory.appendingPathComponent("mail-cache.json")
        guard FileManager.default.fileExists(atPath: legacy.path) else { return nil }
        return try JSONDecoder().decode(MailCache.self, from: Data(contentsOf: legacy))
    }

    func load() throws -> MailCache? {
        try execute("BEGIN")
        defer { try? execute("ROLLBACK") }
        let decoder = JSONDecoder()
        var snapshot: MailCache?
        try statement("SELECT data FROM cache_state WHERE id = 1") {
            if try advance($0) { snapshot = try decoder.decode(MailCache.self, from: blob($0)) }
        }
        guard var snapshot else { return nil }
        try statement("SELECT data FROM mail ORDER BY received DESC, id") {
            while try advance($0) { snapshot.messages.append(try decoder.decode(MailMessage.self, from: blob($0))) }
        }
        return snapshot
    }

    func save(_ snapshot: MailCache) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        var state = snapshot
        state.messages = []
        let latest = Dictionary(snapshot.messages.map { ($0.id, $0) }, uniquingKeysWith: { _, last in last })
        try execute("BEGIN IMMEDIATE")
        do {
            try statement("INSERT INTO cache_state VALUES (1, ?) ON CONFLICT(id) DO UPDATE SET data = excluded.data WHERE data != excluded.data") {
                try bind(encoder.encode(state), to: 1, in: $0)
                _ = try advance($0)
            }
            var storedIDs = Set(savedMessages?.keys.map { $0 } ?? [])
            if savedMessages == nil {
                try statement("SELECT id FROM mail") {
                    while try advance($0) { storedIDs.insert(String(cString: sqlite3_column_text($0, 0))) }
                }
            }
            let removed = storedIDs.subtracting(latest.keys)
            try statement("INSERT INTO mail VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET received = excluded.received, data = excluded.data WHERE data != excluded.data") { row in
                for message in latest.values where savedMessages?[message.id] != message {
                    try check(sqlite3_bind_text(row, 1, message.id, -1, Self.transient))
                    try check(sqlite3_bind_double(row, 2, message.date.timeIntervalSince1970))
                    try bind(encoder.encode(message), to: 3, in: row)
                    _ = try advance(row)
                    try check(sqlite3_reset(row))
                }
            }
            try statement("DELETE FROM mail WHERE id = ?") { row in
                for id in removed {
                    try check(sqlite3_bind_text(row, 1, id, -1, Self.transient))
                    _ = try advance(row)
                    try check(sqlite3_reset(row))
                }
            }
            try execute("COMMIT")
            savedMessages = latest
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func execute(_ sql: String) throws {
        try check(sqlite3_exec(database, sql, nil, nil, nil))
    }

    private func statement(_ sql: String, _ body: (OpaquePointer) throws -> Void) throws {
        var prepared: OpaquePointer?
        try check(sqlite3_prepare_v2(database, sql, -1, &prepared, nil))
        guard let prepared else { throw databaseError }
        defer { sqlite3_finalize(prepared) }
        try body(prepared)
    }

    private func advance(_ row: OpaquePointer) throws -> Bool {
        switch sqlite3_step(row) {
        case SQLITE_ROW: return true
        case SQLITE_DONE: return false
        default: throw databaseError
        }
    }

    private func bind(_ data: Data, to column: Int32, in row: OpaquePointer) throws {
        try check(data.withUnsafeBytes { sqlite3_bind_blob64(row, column, $0.baseAddress, UInt64($0.count), Self.transient) })
    }

    private func blob(_ row: OpaquePointer) -> Data {
        guard let bytes = sqlite3_column_blob(row, 0) else { return Data() }
        return Data(bytes: bytes, count: Int(sqlite3_column_bytes(row, 0)))
    }

    private func check(_ result: Int32) throws {
        guard result == SQLITE_OK else { throw databaseError }
    }

    private var databaseError: MailError {
        .message(String(cString: sqlite3_errmsg(database)))
    }
}
