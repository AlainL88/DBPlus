//
//  DirectTransport.swift
//  DB+
//
//  Connessione TCP/IP diretta a MySQL/MariaDB tramite MySQLNIO.
//  Supporta TLS opzionale (con opzione per certificati self-signed),
//  prepared statements e streaming delle righe.
//

import Foundation
import MySQLNIO
import NIOSSL
import NIOPosix

final class DirectTransport: DatabaseTransport {
    let mode: ConnectionMode = .direct
    private(set) var isConnected = false

    private let profile: ConnectionProfile
    private let password: String?
    private let group: MultiThreadedEventLoopGroup
    private var conn: MySQLConnection?

    init(profile: ConnectionProfile, password: String?) {
        self.profile = profile
        self.password = password
        self.group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
    }

    // MARK: - TLS

    private var tlsConfiguration: TLSConfiguration? {
        guard profile.useTLS else { return nil }
        var config = TLSConfiguration.makeClientConfiguration()
        if profile.allowSelfSignedTLS {
            config.certificateVerification = .none
        }
        return config
    }

    // MARK: - Connection

    func connect() async throws -> ServerInfo {
        let start = DispatchTime.now()
        let host = profile.host.isEmpty ? "localhost" : profile.host
        DebugLog.shared.log("[DB+DEBUG] DirectTransport.connect() host=\(host):\(profile.port) useTLS=\(profile.useTLS)")

        let connection: MySQLConnection
        do {
            DebugLog.shared.log("[DB+DEBUG]   -> MySQLConnection.connect: inizio (timeout 30s)")
            connection = try await Timeout.withTimeout(30) {
                try await MySQLConnection.connect(
                    to: .makeAddressResolvingHost(host, port: self.profile.port),
                    username: self.profile.username,
                    database: self.profile.defaultSchema,
                    password: self.password,
                    tlsConfiguration: self.tlsConfiguration,
                    on: self.group.next()
                ).get()
            }
            DebugLog.shared.log("[DB+DEBUG]   -> MySQLConnection.connect: OK")
        } catch {
            DebugLog.shared.log("[DB+DEBUG]   -> MySQLConnection.connect ERRORE: \(error.localizedDescription)")
            throw DBError.invalid(Self.describeConnectionFailure(error, host: host, port: profile.port))
        }

        self.conn = connection
        self.isConnected = true

        var version = "Sconosciuta"
        DebugLog.shared.log("[DB+DEBUG]   -> SELECT VERSION(): inizio")
        do {
            let rows = try await Timeout.withTimeout(5) {
                try await connection.simpleQuery("SELECT VERSION() AS v").get()
            }
            if let v = rows.first?.column("v")?.string {
                version = v
            }
        } catch {
            // Versione non determinabile: non è bloccante.
        }
        DebugLog.shared.log("[DB+DEBUG]   -> SELECT VERSION(): version=\(version)")

        let latency = Self.elapsedMS(from: start)
        return ServerInfo(version: version, host: host, latencyMS: latency, transportMode: .direct)
    }

    /// Traduce un errore di connessione NIO/POSIX in un messaggio chiaro per l'utente.
    private static func describeConnectionFailure(_ error: Error, host: String, port: Int) -> String {
        let target = "\(host):\(port)"
        if let nioError = error as? NIOConnectionError {
            if nioError.dnsAError != nil || nioError.dnsAAAAError != nil {
                return "Host \(target) non risolvibile: controlla il nome host e la rete."
            }
            for failure in nioError.connectionErrors {
                if let reason = describePOSIX(failure.error, target: target) {
                    return reason
                }
            }
            return "Impossibile raggiungere \(target): \(nioError.localizedDescription)"
        }
        if let reason = describePOSIX(error, target: target) {
            return reason
        }
        return "Impossibile raggiungere \(target): \(error.localizedDescription)"
    }

    private static func describePOSIX(_ error: Error, target: String) -> String? {
        let code: Int32?
        if let io = error as? IOError {
            code = io.errnoCode
        } else {
            let nsError = error as NSError
            code = nsError.domain == NSPOSIXErrorDomain ? Int32(nsError.code) : nil
        }
        guard let code else { return nil }
        switch code {
        case ECONNREFUSED:
            return "Connessione rifiutata su \(target) — porta chiusa o servizio non attivo. Verifica la porta e che il server MySQL/MariaDB sia in esecuzione."
        case ETIMEDOUT:
            return "Timeout su \(target) — host irraggiungibile. Verifica rete, firewall e indirizzo."
        case EHOSTUNREACH:
            return "Host \(target) irraggiungibile (nessuna rotta di rete)."
        case ENETUNREACH:
            return "Rete non raggiungibile verso \(target)."
        default:
            return nil
        }
    }

    func close() async {
        if let connection = conn {
            try? await connection.close().get()
        }
        conn = nil
        isConnected = false
        group.shutdownGracefully { _ in }
    }

    func pingLatency() async throws -> Double {
        let start = DispatchTime.now()
        DebugLog.shared.log("[DB+DEBUG] DirectTransport.pingLatency() SELECT 1: inizio")
        _ = try await Timeout.withTimeout(5) {
            try await self.requireConnection().simpleQuery("SELECT 1").get()
        }
        let ms = Self.elapsedMS(from: start)
        DebugLog.shared.log("[DB+DEBUG] DirectTransport.pingLatency() OK: \(ms) ms")
        return ms
    }

    private func requireConnection() throws -> MySQLConnection {
        guard let conn else { throw DBError.notConnected }
        return conn
    }

    private static func elapsedMS(from start: DispatchTime) -> Double {
        Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    // MARK: - Execute

    func execute(_ request: StatementRequest) async throws -> StatementResult {
        let db = try requireConnection()
        let start = DispatchTime.now()

        guard !request.binds.isEmpty else {
            return try await executeRaw(db: db, request: request, start: start)
        }
        return try await executePrepared(db: db, request: request, start: start)
    }

    private func executeRaw(db: MySQLConnection, request: StatementRequest, start: DispatchTime) async throws -> StatementResult {
        var result = StatementResult()
        result.executedSQL = request.sql
        var sawColumns = false
        var columns: [ColumnHeader] = []

        _ = try await db.simpleQuery(request.sql, onRow: { row in
            if !sawColumns {
                sawColumns = !row.columnDefinitions.isEmpty
                columns = row.columnDefinitions.enumerated().map { idx, def in
                    ColumnHeader(
                        name: def.name,
                        typeName: Self.typeName(for: def.columnType),
                        isUnsigned: def.flags.contains(.COLUMN_UNSIGNED),
                        index: idx
                    )
                }
                result.columns = columns
            }
            if result.rows.count < request.rowLimit {
                result.rows.append(Self.convert(row))
            } else {
                result.truncated = true
            }
        }).get()

        if !sawColumns {
            // Statement non-SELECT: recupera righe modificate e ultimo insert id.
            let rc = try await db.simpleQuery("SELECT ROW_COUNT() AS c, LAST_INSERT_ID() AS l").get()
            if let first = rc.first {
                result.affectedRows = first.column("c")?.uint64 ?? 0
                result.lastInsertID = first.column("l")?.uint64
            }
        }

        result.executionTimeMS = Self.elapsedMS(from: start)
        return result
    }

    private func executePrepared(db: MySQLConnection, request: StatementRequest, start: DispatchTime) async throws -> StatementResult {
        var result = StatementResult()
        result.executedSQL = request.sql

        var metadata: MySQLQueryMetadata?
        var columns: [ColumnHeader] = []

        try await db.query(request.sql, request.binds.map(Self.toMySQLData), onRow: { row in
            if columns.isEmpty {
                columns = row.columnDefinitions.enumerated().map { idx, def in
                    ColumnHeader(
                        name: def.name,
                        typeName: Self.typeName(for: def.columnType),
                        isUnsigned: def.flags.contains(.COLUMN_UNSIGNED),
                        index: idx
                    )
                }
                result.columns = columns
            }
            if result.rows.count < request.rowLimit {
                result.rows.append(Self.convert(row))
            } else {
                result.truncated = true
            }
        }, onMetadata: { meta in
            metadata = meta
        }).get()

        if let metadata {
            result.affectedRows = metadata.affectedRows
            result.lastInsertID = metadata.lastInsertID
        }

        result.executionTimeMS = Self.elapsedMS(from: start)
        return result
    }

    // MARK: - Streaming

    func stream(_ sql: String, onRow: @escaping @Sendable ([CellValue]) async throws -> Void) async throws -> Int {
        let db = try requireConnection()
        var count = 0
        try await db.simpleQuery(sql, onRow: { row in
            count += 1
            let cells = Self.convert(row)
            // Sincronizzazione: la callback di NIO non è async; eseguiamo su un Task.
            let semaphore = DispatchSemaphore(value: 0)
            Task {
                do {
                    try await onRow(cells)
                } catch {
                    // Propagato al termine del flusso.
                }
                semaphore.signal()
            }
            semaphore.wait()
        }).get()
        return count
    }

    // MARK: - Introspezione

    func listSchemas() async throws -> [String] {
        let rows = try await requireConnection()
            .simpleQuery("""
                SELECT SCHEMA_NAME AS s FROM information_schema.SCHEMATA
                WHERE SCHEMA_NAME NOT IN ('information_schema','mysql','performance_schema','sys')
                ORDER BY 1
                """).get()
        return rows.compactMap { $0.column("s")?.string }
    }

    func listTables(schema: String) async throws -> [String] {
        try await listWithSchemaSQL("""
            SELECT TABLE_NAME AS t FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = ? AND TABLE_TYPE = 'BASE TABLE' ORDER BY 1
            """, schema: schema)
    }

    func listViews(schema: String) async throws -> [String] {
        try await listWithSchemaSQL("""
            SELECT TABLE_NAME AS t FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = ? AND TABLE_TYPE = 'VIEW' ORDER BY 1
            """, schema: schema)
    }

    func listRoutines(schema: String, kind: String) async throws -> [String] {
        try await listWithSchemaSQL("""
            SELECT ROUTINE_NAME AS t FROM information_schema.ROUTINES
            WHERE ROUTINE_SCHEMA = ? AND ROUTINE_TYPE = ? ORDER BY 1
            """, schema: schema, extra: [MySQLData(string: kind)])
    }

    private func listWithSchemaSQL(_ sql: String, schema: String, extra: [MySQLData] = []) async throws -> [String] {
        var binds = extra
        binds.insert(MySQLData(string: schema), at: 0)
        let rows = try await requireConnection().query(sql, binds).get()
        return rows.compactMap { $0.column("t")?.string }
    }

    func tableStructure(schema: String, table: String) async throws -> TableStructure {
        let db = try requireConnection()
        var structure = TableStructure(schema: schema, table: table)

        // Colonne
        let colRows = try await db.query("""
            SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, IS_NULLABLE,
                   COLUMN_DEFAULT, EXTRA, COLLATION_NAME, COLUMN_KEY, COLUMN_POSITION
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
            ORDER BY ORDINAL_POSITION
            """, [MySQLData(string: schema), MySQLData(string: table)]).get()

        let pkColumns = try await primaryKeyColumns(schema: schema, table: table)
        let pkSet = Set(pkColumns)

        for row in colRows {
            let name = row.column("COLUMN_NAME")?.string ?? ""
            let dataType = row.column("DATA_TYPE")?.string ?? ""
            let columnType = row.column("COLUMN_TYPE")?.string ?? dataType
            let isNullable = (row.column("IS_NULLABLE")?.string?.lowercased() == "yes")
            let extra = row.column("EXTRA")?.string ?? ""
            structure.columns.append(ColumnInfo(
                name: name,
                dataType: dataType,
                columnType: columnType,
                isNullable: isNullable,
                isPrimaryKey: pkSet.contains(name),
                defaultValue: row.column("COLUMN_DEFAULT")?.string,
                extra: extra,
                collation: row.column("COLLATION_NAME")?.string,
                keyType: row.column("COLUMN_KEY")?.string ?? "",
                isUnsigned: columnType.lowercased().contains("unsigned"),
                ordinal: Int(row.column("COLUMN_POSITION")?.int64 ?? 0)
            ))
        }

        // Indici
        let idxRows = try await db.query("""
            SELECT INDEX_NAME, COLUMN_NAME, SEQ_IN_INDEX, NON_UNIQUE, INDEX_TYPE
            FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
            ORDER BY INDEX_NAME, SEQ_IN_INDEX
            """, [MySQLData(string: schema), MySQLData(string: table)]).get()
        for row in idxRows {
            let name = row.column("INDEX_NAME")?.string ?? ""
            structure.indexes.append(TableIndex(
                name: name,
                columnName: row.column("COLUMN_NAME")?.string ?? "",
                sequence: Int(row.column("SEQ_IN_INDEX")?.int64 ?? 1),
                nonUnique: (row.column("NON_UNIQUE")?.int64 ?? 1) != 0,
                indexType: row.column("INDEX_TYPE")?.string ?? "",
                isPrimary: name == "PRIMARY"
            ))
        }

        // Foreign keys
        let fkRows = try await db.query("""
            SELECT k.CONSTRAINT_NAME, k.COLUMN_NAME, k.REFERENCED_TABLE_NAME, k.REFERENCED_COLUMN_NAME,
                   r.UPDATE_RULE, r.DELETE_RULE
            FROM information_schema.KEY_COLUMN_USAGE k
            LEFT JOIN information_schema.REFERENTIAL_CONSTRAINTS r
              ON r.CONSTRAINT_NAME = k.CONSTRAINT_NAME
             AND r.CONSTRAINT_SCHEMA = k.CONSTRAINT_SCHEMA
            WHERE k.TABLE_SCHEMA = ? AND k.TABLE_NAME = ?
              AND k.REFERENCED_TABLE_NAME IS NOT NULL
            ORDER BY k.CONSTRAINT_NAME, k.ORDINAL_POSITION
            """, [MySQLData(string: schema), MySQLData(string: table)]).get()
        for row in fkRows {
            structure.foreignKeys.append(ForeignKey(
                constraintName: row.column("CONSTRAINT_NAME")?.string ?? "",
                columnName: row.column("COLUMN_NAME")?.string ?? "",
                referencedTable: row.column("REFERENCED_TABLE_NAME")?.string ?? "",
                referencedColumn: row.column("REFERENCED_COLUMN_NAME")?.string ?? "",
                onUpdate: row.column("UPDATE_RULE")?.string ?? "",
                onDelete: row.column("DELETE_RULE")?.string ?? ""
            ))
        }

        // SHOW CREATE TABLE
        do {
            let sc = try await db.simpleQuery("SHOW CREATE TABLE \(SQLIdentifier.quote(schema)).\(SQLIdentifier.quote(table))").get()
            structure.createSQL = sc.first?.column("Create Table")?.string ?? sc.first?.column("Create View")?.string
        } catch { /* non bloccante */ }

        // Info tabella
        let ti = try await db.query("""
            SELECT ENGINE, TABLE_COLLATION, AUTO_INCREMENT FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
            """, [MySQLData(string: schema), MySQLData(string: table)]).get()
        if let row = ti.first {
            structure.engine = row.column("ENGINE")?.string
            structure.tableCollation = row.column("TABLE_COLLATION")?.string
            structure.autoIncrement = row.column("AUTO_INCREMENT")?.uint64
        }

        return structure
    }

    func tableRowCount(schema: String, table: String) async throws -> Int {
        let sql = "SELECT COUNT(*) AS c FROM \(SQLIdentifier.quote(schema)).\(SQLIdentifier.quote(table))"
        let rows = try await requireConnection().simpleQuery(sql).get()
        return Int(rows.first?.column("c")?.int64 ?? 0)
    }

    func primaryKeyColumns(schema: String, table: String) async throws -> [String] {
        let rows = try await requireConnection().query("""
            SELECT COLUMN_NAME AS c FROM information_schema.KEY_COLUMN_USAGE
            WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND CONSTRAINT_NAME = 'PRIMARY'
            ORDER BY ORDINAL_POSITION
            """, [MySQLData(string: schema), MySQLData(string: table)]).get()
        return rows.compactMap { $0.column("c")?.string }
    }

    func useSchema(_ schema: String) async throws {
        _ = try await requireConnection().simpleQuery("USE \(SQLIdentifier.quote(schema))").get()
    }

    // MARK: - Conversioni

    private static func convert(_ row: MySQLRow) -> [CellValue] {
        row.values.enumerated().map { index, buffer in
            let def = row.columnDefinitions[index]
            let data = MySQLData(
                type: def.columnType,
                format: row.format,
                buffer: buffer,
                isUnsigned: def.flags.contains(.COLUMN_UNSIGNED)
            )
            return toCell(data)
        }
    }

    /// Traduce il codice del protocollo MySQL in un nome di tipo leggibile.
    static func typeName(for type: MySQLProtocol.DataType) -> String {
        switch type.rawValue {
        case 0, 246: return "decimal"
        case 1: return "tinyint"
        case 2: return "smallint"
        case 3, 9: return "int"
        case 4: return "float"
        case 5: return "double"
        case 7: return "timestamp"
        case 8: return "bigint"
        case 10: return "date"
        case 11: return "time"
        case 12: return "datetime"
        case 13: return "year"
        case 15: return "varchar"
        case 16: return "bit"
        case 247: return "enum"
        case 248: return "set"
        case 249: return "tinyblob"
        case 250: return "mediumblob"
        case 251: return "longblob"
        case 252: return "blob"
        case 253: return "varchar"
        case 254: return "char"
        case 255: return "geometry"
        default: return "type\(type.rawValue)"
        }
    }

    private static func toCell(_ data: MySQLData) -> CellValue {
        guard data.buffer != nil else { return .null }
        switch data.type {
        case .longlong, .long, .int24, .short, .tiny:
            if data.isUnsigned {
                return data.uint64.map(CellValue.uint) ?? .string(data.string ?? "")
            }
            return data.int64.map(CellValue.int) ?? .string(data.string ?? "")
        case .bit:
            return data.bool.map(CellValue.bool) ?? .int(data.int64 ?? 0)
        case .double, .float:
            return data.double.map(CellValue.double) ?? .string(data.string ?? "")
        case .newdecimal, .decimal:
            return .decimal(data.string ?? "")
        case .timestamp, .datetime, .date:
            return data.date.map(CellValue.date) ?? .string(data.string ?? "")
        case .blob, .tinyBlob, .mediumBlob, .longBlob, .geometry:
            if let buffer = data.buffer {
                return .data(Data(buffer.readableBytesView))
            }
            return .string(data.string ?? "")
        default:
            return .string(data.string ?? "")
        }
    }

    static func toMySQLData(_ cell: CellValue) -> MySQLData {
        switch cell {
        case .null:
            return .null
        case .int(let v):
            return .init(string: String(v))
        case .uint(let v):
            return .init(string: String(v))
        case .double(let v):
            return .init(string: String(v))
        case .decimal(let s):
            return .init(string: s)
        case .bool(let b):
            return .init(bool: b)
        case .string(let s):
            return .init(string: s)
        case .date(let d):
            return .init(string: Self.dateString(d))
        case .time(let t):
            return .init(string: String(t))
        case .data(let d):
            var buffer = ByteBufferAllocator().buffer(capacity: d.count)
            buffer.writeBytes(d)
            return MySQLData(type: .blob, format: .binary, buffer: buffer)
        }
    }

    private static let dbDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    static func dateString(_ date: Date) -> String {
        dbDateFormatter.string(from: date)
    }
}
