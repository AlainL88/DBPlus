//
//  BridgeTransport.swift
//  DB+
//
//  Connessione al database attraverso uno script remoto db_bridge.php
//  esposto su HTTPS. Tutte le richieste sono autenticate con:
//    - Bearer token (header X-DBPlus-Token)
//    - firma HMAC-SHA256 su timestamp + body (anti-replay) se abilitata
//  Il server applica rate limiting e prepared statement lato PHP.
//

import CryptoKit
import Foundation

final class BridgeTransport: DatabaseTransport {
    let mode: ConnectionMode = .bridge
    private(set) var isConnected = false

    private let profile: ConnectionProfile
    private let token: String?
    private let hmacSecret: String?
    private let session: URLSession
    private var cachedVersion: String?

    init(profile: ConnectionProfile, token: String?, hmacSecret: String?) {
        self.profile = profile
        self.token = token
        self.hmacSecret = hmacSecret
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.session = URLSession(configuration: config)
    }

    private var endpoint: URL {
        get throws {
            guard let url = URL(string: profile.bridgeURL), url.scheme == "https" else {
                throw DBError.invalid("URL del bridge non valido (deve essere HTTPS).")
            }
            return url
        }
    }

    // MARK: - Connection

    func connect() async throws -> ServerInfo {
        let start = DispatchTime.now()
        DebugLog.shared.log("[DB+DEBUG] BridgeTransport.connect() url=\(profile.bridgeURL)")
        DebugLog.shared.log("[DB+DEBUG]   -> post(ping): inizio")
        let response = try await post(action: "ping")
        DebugLog.shared.log("[DB+DEBUG]   -> post(ping): OK — ok=\(response.ok)")
        let latency = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000

        guard response.ok else {
            throw DBError.invalid(response.error ?? "Bridge non raggiungibile")
        }
        cachedVersion = response.serverVersion ?? "Sconosciuta"
        isConnected = true
        return ServerInfo(
            version: cachedVersion ?? "Sconosciuta",
            host: profile.bridgeURL,
            latencyMS: latency,
            transportMode: .bridge
        )
    }

    func close() async {
        isConnected = false
        cachedVersion = nil
    }

    func pingLatency() async throws -> Double {
        let start = DispatchTime.now()
        DebugLog.shared.log("[DB+DEBUG] BridgeTransport.pingLatency() post(ping): inizio")
        let response = try await post(action: "ping")
        DebugLog.shared.log("[DB+DEBUG] BridgeTransport.pingLatency() OK")
        guard response.ok else {
            throw DBError.invalid(response.error ?? "Ping fallito")
        }
        return Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
    }

    // MARK: - Execute

    func execute(_ request: StatementRequest) async throws -> StatementResult {
        let start = DispatchTime.now()
        let params: [Any] = request.binds.map { cell in
            if cell.isNull { return NSNull() }
            return cell.bridgeString ?? ""
        }
        let response = try await post(
            action: "execute",
            sql: request.sql,
            params: params,
            rowLimit: request.rowLimit
        )
        return Self.makeResult(from: response, sql: request.sql, start: start)
    }

    func stream(_ sql: String, onRow: @escaping @Sendable ([CellValue]) async throws -> Void) async throws -> Int {
        let response = try await post(action: "execute", sql: sql, rowLimit: 1_000_000)
        guard response.ok, let rows = response.rows else {
            throw DBError.invalid(response.error ?? "Stream fallito")
        }
        let headers = (response.columns ?? []).enumerated().map {
            ColumnHeader(name: $1.name, typeName: $1.type, isUnsigned: $1.unsigned, index: $0)
        }
        for row in rows {
            var cells: [CellValue] = []
            for (index, value) in row.enumerated() {
                if let value {
                    let header = index < headers.count ? headers[index] : nil
                    cells.append(Self.cell(from: value, header: header))
                } else {
                    cells.append(.null)
                }
            }
            try await onRow(cells)
        }
        return rows.count
    }

    // MARK: - Introspezione (esegue le stesse query information_schema)

    func listSchemas() async throws -> [String] {
        try await strings(sql: """
            SELECT SCHEMA_NAME AS t FROM information_schema.SCHEMATA
            WHERE SCHEMA_NAME NOT IN ('information_schema','mysql','performance_schema','sys')
            ORDER BY 1
            """)
    }

    func listTables(schema: String) async throws -> [String] {
        try await strings(sql: """
            SELECT TABLE_NAME AS t FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = ? AND TABLE_TYPE = 'BASE TABLE' ORDER BY 1
            """, params: [schema])
    }

    func listViews(schema: String) async throws -> [String] {
        try await strings(sql: """
            SELECT TABLE_NAME AS t FROM information_schema.TABLES
            WHERE TABLE_SCHEMA = ? AND TABLE_TYPE = 'VIEW' ORDER BY 1
            """, params: [schema])
    }

    func listRoutines(schema: String, kind: String) async throws -> [String] {
        try await strings(sql: """
            SELECT ROUTINE_NAME AS t FROM information_schema.ROUTINES
            WHERE ROUTINE_SCHEMA = ? AND ROUTINE_TYPE = ? ORDER BY 1
            """, params: [schema, kind])
    }

    func tableStructure(schema: String, table: String) async throws -> TableStructure {
        // Il bridge non espone un'azione dedicata: il client ricostruisce la
        // struttura con le stesse query usate dal trasporto diretto.
        let helper = BridgeSchemaHelper(transport: self, schema: schema, table: table)
        return try await helper.load()
    }

    func tableRowCount(schema: String, table: String) async throws -> Int {
        let sql = "SELECT COUNT(*) AS c FROM \(SQLIdentifier.quote(schema)).\(SQLIdentifier.quote(table))"
        let rows = try await strings(sql: sql, key: "c")
        return Int(rows.first ?? "0") ?? 0
    }

    func primaryKeyColumns(schema: String, table: String) async throws -> [String] {
        try await strings(sql: """
            SELECT COLUMN_NAME AS t FROM information_schema.KEY_COLUMN_USAGE
            WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ? AND CONSTRAINT_NAME = 'PRIMARY'
            ORDER BY ORDINAL_POSITION
            """, params: [schema, table])
    }

    func useSchema(_ schema: String) async throws {
        // Il bridge esegue USE sul proprio collegamento per ogni richiesta:
        // per coerenza lo richiediamo esplicitamente con il prefisso.
        _ = try await post(action: "execute", sql: "USE \(SQLIdentifier.quote(schema))")
    }

    private func strings(sql: String, params: [String] = [], key: String = "t") async throws -> [String] {
        let response = try await post(action: "execute", sql: sql, params: params)
        guard response.ok else {
            throw DBError.invalid(response.error ?? "Query fallita")
        }
        return (response.rows ?? []).compactMap { row in row.first ?? nil }
    }

    // MARK: - Richieste

    func post(action: String, sql: String? = nil, params: [Any] = [], rowLimit: Int? = nil) async throws -> BridgeResponse {
        var body: [String: Any] = ["action": action]
        if let sql { body["sql"] = sql }
        if !params.isEmpty { body["params"] = params }
        if let rowLimit { body["rowLimit"] = rowLimit }

        let jsonData = try JSONSerialization.data(withJSONObject: body)
        let bodyString = String(data: jsonData, encoding: .utf8) ?? ""

        var request = URLRequest(url: try endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token ?? "", forHTTPHeaderField: "X-DBPlus-Token")

        if let secret = hmacSecret, profile.bridgeUseHMAC {
            let timestamp = String(Int(Date().timeIntervalSince1970))
            let message = timestamp + ":" + bodyString
            let signature = HMAC<SHA256>.authenticationCode(for: Data(message.utf8), using: SymmetricKey(data: Data(secret.utf8)))
                .map { String(format: "%02x", $0) }
                .joined()
            request.setValue(signature, forHTTPHeaderField: "X-DBPlus-Signature")
            request.setValue(timestamp, forHTTPHeaderField: "X-DBPlus-Timestamp")
        }

        request.httpBody = jsonData

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw DBError.invalid("Risposta del bridge non HTTP.")
        }
        guard (200..<300).contains(http.statusCode) else {
            throw DBError.invalid("Il bridge ha risposto con HTTP \(http.statusCode).")
        }
        return try JSONDecoder().decode(BridgeResponse.self, from: data)
    }

    // MARK: - Decodifica risultato

    static func makeResult(from response: BridgeResponse, sql: String, start: DispatchTime) -> StatementResult {
        var result = StatementResult()
        result.executedSQL = sql
        result.isError = !response.ok
        result.errorMessage = response.error

        if let columns = response.columns {
            result.columns = columns.enumerated().map { idx, col in
                ColumnHeader(name: col.name, typeName: col.type, isUnsigned: col.unsigned, index: idx)
            }
        }
        if let rows = response.rows {
            let headers = (response.columns ?? []).enumerated().map {
                ColumnHeader(name: $1.name, typeName: $1.type, isUnsigned: $1.unsigned, index: $0)
            }
            result.rows = rows.map { row in
                row.enumerated().map { index, value in
                    guard let value else { return CellValue.null }
                    let header = index < headers.count ? headers[index] : nil
                    return cell(from: value, header: header)
                }
            }
        }
        result.affectedRows = response.affectedRows ?? 0
        result.lastInsertID = response.lastInsertID
        result.truncated = response.truncated ?? false
        result.executionTimeMS = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000
        return result
    }

    private static func cell(from string: String, header: ColumnHeader?) -> CellValue {
        guard let header else { return .string(string) }
        let type = header.typeName.lowercased()
        if type.contains("int") || type.contains("bit") {
            if let v = Int64(string) { return .int(v) }
            if let v = UInt64(string) { return .uint(v) }
        }
        if type.contains("double") || type.contains("float") || type.contains("decimal") {
            if let v = Double(string) { return .double(v) }
            return .decimal(string)
        }
        if type.contains("blob") || type.contains("binary") || type.contains("varbinary") {
            return .data(Data(string.utf8))
        }
        return .string(string)
    }
}

/// Ricostruisce la struttura della tabella tramite il bridge usando le stesse
/// query information_schema del trasporto diretto.
private struct BridgeSchemaHelper {
    let transport: BridgeTransport
    let schema: String
    let table: String

    func load() async throws -> TableStructure {
        var structure = TableStructure(schema: schema, table: table)

        let pk = try await transport.primaryKeyColumns(schema: schema, table: table)
        let pkSet = Set(pk)

        let colRows = try await rows(sql: """
            SELECT COLUMN_NAME, DATA_TYPE, COLUMN_TYPE, IS_NULLABLE, COLUMN_DEFAULT,
                   EXTRA, COLLATION_NAME, COLUMN_KEY, COLUMN_POSITION
            FROM information_schema.COLUMNS
            WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
            ORDER BY ORDINAL_POSITION
            """, params: [schema, table])

        for (index, row) in colRows.enumerated() {
            let name = row[0] ?? ""
            let dataType = row[1] ?? ""
            let columnType = row[2] ?? dataType
            let isNullable = (row[3]?.lowercased() == "yes")
            structure.columns.append(ColumnInfo(
                name: name,
                dataType: dataType,
                columnType: columnType,
                isNullable: isNullable,
                isPrimaryKey: pkSet.contains(name),
                defaultValue: row[4],
                extra: row[5] ?? "",
                collation: row[6],
                keyType: row[7] ?? "",
                isUnsigned: columnType.lowercased().contains("unsigned"),
                ordinal: Int(row[8] ?? "") ?? index
            ))
        }

        let idxRows = try await rows(sql: """
            SELECT INDEX_NAME, COLUMN_NAME, SEQ_IN_INDEX, NON_UNIQUE, INDEX_TYPE
            FROM information_schema.STATISTICS
            WHERE TABLE_SCHEMA = ? AND TABLE_NAME = ?
            ORDER BY INDEX_NAME, SEQ_IN_INDEX
            """, params: [schema, table])
        for row in idxRows {
            let name = row[0] ?? ""
            structure.indexes.append(TableIndex(
                name: name,
                columnName: row[1] ?? "",
                sequence: Int(row[2] ?? "") ?? 1,
                nonUnique: (Int(row[3] ?? "1") ?? 1) != 0,
                indexType: row[4] ?? "",
                isPrimary: name == "PRIMARY"
            ))
        }

        return structure
    }

    private func rows(sql: String, params: [String] = []) async throws -> [[String?]] {
        let response = try await transport.post(action: "execute", sql: sql, params: params)
        guard response.ok else {
            throw DBError.invalid(response.error ?? "Query fallita")
        }
        return response.rows ?? []
    }
}
