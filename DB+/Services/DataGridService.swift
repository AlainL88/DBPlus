//
//  DataGridService.swift
//  DB+
//
//  Lettura paginata, ordinamento, filtri e operazioni CRUD generate
//  automaticamente a partire dalla chiave primaria. Tutte le scritture
//  usano prepared statement (anti SQL injection).
//

import Foundation

struct DataGridService {
    let transport: any DatabaseTransport
    let schema: String
    let table: String

    private let pageSize = 200

    func loadStructure() async throws -> TableStructure {
        try await transport.tableStructure(schema: schema, table: table)
    }

    func count() async throws -> Int {
        try await transport.tableRowCount(schema: schema, table: table)
    }

    /// Carica una pagina di dati con ordinamento e filtro opzionali.
    func loadPage(
        offset: Int,
        sortColumn: String? = nil,
        ascending: Bool = true,
        filter: String? = nil
    ) async throws -> TablePage {
        let structure = try await loadStructure()
        let columns = structure.columns.map {
            ColumnHeader(name: $0.name, typeName: $0.columnType, isUnsigned: $0.isUnsigned, index: $0.ordinal - 1)
        }

        let columnList = structure.columns.map { SQLIdentifier.quote($0.name) }.joined(separator: ", ")
        var sql = "SELECT \(columnList) FROM \(SQLIdentifier.quote(schema)).\(SQLIdentifier.quote(table))"

        if let filter, !filter.trimmingCharacters(in: .whitespaces).isEmpty {
            sql += " WHERE \(filter)"
        }
        if let sortColumn, structure.columns.contains(where: { $0.name == sortColumn }) {
            sql += " ORDER BY \(SQLIdentifier.quote(sortColumn)) \(ascending ? "ASC" : "DESC")"
        }
        sql += " LIMIT \(pageSize) OFFSET \(offset)"

        let result = try await transport.execute(StatementRequest(sql: sql, rowLimit: pageSize))
        let total = try await count()

        return TablePage(
            columns: columns,
            rows: result.rows,
            total: total,
            offset: offset,
            limit: pageSize
        )
    }

    // MARK: - CRUD

    /// Inserisce una riga. `values`: colonna → valore (i valori NULL omessi
    /// lasciano agire il default della colonna).
    func insertRow(values: [String: CellValue]) async throws -> StatementResult {
        let structure = try await loadStructure()
        let validColumns = Set(structure.columns.map { $0.name })
        let entries = values.filter { validColumns.contains($0.key) && !$0.value.isNull }

        guard !entries.isEmpty else {
            throw DBError.invalid("Nessuna colonna con valore da inserire.")
        }
        let colNames = Array(entries.keys)
        let colList = colNames.map { SQLIdentifier.quote($0) }.joined(separator: ", ")
        let placeholders = Array(repeating: "?", count: colNames.count).joined(separator: ", ")
        let sql = "INSERT INTO \(SQLIdentifier.quote(schema)).\(SQLIdentifier.quote(table)) (\(colList)) VALUES (\(placeholders))"
        let binds = colNames.map { entries[$0] ?? .null }
        return try await transport.execute(StatementRequest(sql: sql, binds: binds))
    }

    /// Aggiorna la riga individuata dalla chiave primaria.
    /// `changed`: sole colonne modificate (include NULL espliciti).
    func updateRow(pkValues: [String: CellValue], changed: [String: CellValue]) async throws -> StatementResult {
        let pkColumns = try await transport.primaryKeyColumns(schema: schema, table: table)
        guard !pkColumns.isEmpty else {
            throw DBError.invalid("La tabella non ha una chiave primaria: impossibile aggiornare in modo sicuro.")
        }

        let setColumns = changed.keys.filter { !pkColumns.contains($0) }
        guard !setColumns.isEmpty else {
            throw DBError.invalid("Nessuna colonna (non-PK) da aggiornare.")
        }
        let setClause = setColumns.map { "\(SQLIdentifier.quote($0)) = ?" }.joined(separator: ", ")
        let whereClause = pkColumns.map { "\(SQLIdentifier.quote($0)) = ?" }.joined(separator: " AND ")

        var binds: [CellValue] = []
        binds.append(contentsOf: setColumns.map { changed[$0] ?? .null })
        binds.append(contentsOf: pkColumns.map { pkValues[$0] ?? .null })

        let sql = "UPDATE \(SQLIdentifier.quote(schema)).\(SQLIdentifier.quote(table)) SET \(setClause) WHERE \(whereClause)"
        return try await transport.execute(StatementRequest(sql: sql, binds: binds))
    }

    /// Elimina la riga individuata dalla chiave primaria.
    func deleteRow(pkValues: [String: CellValue]) async throws -> StatementResult {
        let pkColumns = try await transport.primaryKeyColumns(schema: schema, table: table)
        guard !pkColumns.isEmpty else {
            throw DBError.invalid("La tabella non ha una chiave primaria: impossibile eliminare in modo sicuro.")
        }
        let whereClause = pkColumns.map { "\(SQLIdentifier.quote($0)) = ?" }.joined(separator: " AND ")
        let binds = pkColumns.map { pkValues[$0] ?? .null }
        let sql = "DELETE FROM \(SQLIdentifier.quote(schema)).\(SQLIdentifier.quote(table)) WHERE \(whereClause)"
        return try await transport.execute(StatementRequest(sql: sql, binds: binds))
    }
}

/// Una pagina di dati tabellari.
struct TablePage: Sendable {
    var columns: [ColumnHeader]
    var rows: [[CellValue]]
    var total: Int
    var offset: Int
    var limit: Int

    var pageNumber: Int { offset / limit + 1 }
    var totalPages: Int { max(1, Int(ceil(Double(total) / Double(limit)))) }

    func value(row: Int, column: Int) -> CellValue {
        guard row < rows.count, column < rows[row].count else { return .null }
        return rows[row][column]
    }
}
