//
//  SchemaModels.swift
//  DB+
//

import Foundation

/// Informazioni sul server restituite dopo una connessione riuscita.
struct ServerInfo: Sendable, Equatable {
    var version: String
    var host: String
    var latencyMS: Double
    var transportMode: ConnectionMode
}

/// Tipologia di oggetto nell'albero di navigazione.
enum DatabaseObjectKind: String, Sendable {
    case database
    case table
    case view
    case procedure
    case function
}

/// Nodo dell'albero di navigazione.
enum SchemaNode: Identifiable, Sendable {
    case schema(String)
    case table(String)
    case view(String)
    case routine(String, kind: String)

    var id: String {
        switch self {
        case .schema(let s): return "schema.\(s)"
        case .table(let t): return "table.\(t)"
        case .view(let v): return "view.\(v)"
        case .routine(let r, let k): return "routine.\(k).\(r)"
        }
    }

    var displayName: String {
        switch self {
        case .schema(let s): return s
        case .table(let t): return t
        case .view(let v): return v
        case .routine(let r, _): return r
        }
    }

    var kind: DatabaseObjectKind {
        switch self {
        case .schema: return .database
        case .table: return .table
        case .view: return .view
        case .routine(_, let k): return k == "PROCEDURE" ? .procedure : .function
        }
    }

    var symbolName: String {
        switch self {
        case .schema: return "cylinder"
        case .table: return "table"
        case .view: return "square.stack.3d.up"
        case .routine: return "function"
        }
    }
}

/// Colonne di una tabella (information_schema.COLUMNS).
struct ColumnInfo: Identifiable, Sendable, Hashable {
    var id: String { name }
    let name: String
    let dataType: String
    let columnType: String
    let isNullable: Bool
    let isPrimaryKey: Bool
    let defaultValue: String?
    let extra: String
    let collation: String?
    let keyType: String
    let isUnsigned: Bool
    let ordinal: Int

    var typeDisplay: String {
        var t = columnType
        if isUnsigned && !t.lowercased().contains("unsigned") {
            t += " unsigned"
        }
        return t
    }
}

/// Indici di una tabella (information_schema.STATISTICS).
struct TableIndex: Identifiable, Sendable {
    var id: String { "\(name)#\(sequence)" }
    let name: String
    let columnName: String
    let sequence: Int
    let nonUnique: Bool
    let indexType: String
    let isPrimary: Bool
}

/// Foreign key di una tabella (information_schema.KEY_COLUMN_USAGE).
struct ForeignKey: Identifiable, Sendable {
    var id: String { "\(constraintName).\(columnName)" }
    let constraintName: String
    let columnName: String
    let referencedTable: String
    let referencedColumn: String
    let onUpdate: String
    let onDelete: String
}

/// Struttura completa di una tabella.
struct TableStructure: Sendable {
    let schema: String
    let table: String
    var columns: [ColumnInfo] = []
    var indexes: [TableIndex] = []
    var foreignKeys: [ForeignKey] = []
    var createSQL: String?
    var engine: String?
    var rowCount: Int?
    var tableCollation: String?
    var autoIncrement: UInt64?

    var primaryKeyColumns: [String] {
        indexes.filter { $0.isPrimary }.sorted { $0.sequence < $1.sequence }.map { $0.columnName }
    }

    var nonPKColumns: [String] {
        let pk = Set(primaryKeyColumns)
        return columns.filter { !pk.contains($0.name) }.map { $0.name }
    }
}
