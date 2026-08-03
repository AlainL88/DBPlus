//
//  SchemaInspector.swift
//  DB+
//
//  Ispezione della struttura: database, tabelle, viste, procedure e funzioni.
//

import Foundation

struct SchemaInspector {
    let transport: any DatabaseTransport

    func schemas() async throws -> [String] {
        try await transport.listSchemas()
    }

    /// Figli diretti di uno schema nell'albero di navigazione.
    func children(of schema: String) async throws -> [SchemaNode] {
        var nodes: [SchemaNode] = []
        let tables = try await transport.listTables(schema: schema)
        nodes.append(contentsOf: tables.map { SchemaNode.table($0, schema: schema) })
        let views = try await transport.listViews(schema: schema)
        nodes.append(contentsOf: views.map { SchemaNode.view($0, schema: schema) })
        for kind in ["PROCEDURE", "FUNCTION"] {
            let routines = try await transport.listRoutines(schema: schema, kind: kind)
            nodes.append(contentsOf: routines.map { SchemaNode.routine($0, kind: kind) })
        }
        return nodes
    }

    /// Nomi delle colonne di tutti gli oggetti di uno schema (per l'autocompletamento).
    func columns(in schema: String) async throws -> [String] {
        let escaped = schema.replacingOccurrences(of: "'", with: "''")
        let sql = """
        SELECT COLUMN_NAME
        FROM information_schema.COLUMNS
        WHERE TABLE_SCHEMA = '\(escaped)'
        ORDER BY TABLE_NAME, ORDINAL_POSITION
        """
        let result = try await transport.execute(StatementRequest(sql: sql, rowLimit: 20000))
        return result.rows.compactMap { row in
            guard let value = row.first, case .string(let name) = value else { return nil }
            return name
        }
    }
}
