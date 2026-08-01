//
//  QueryTypes.swift
//  DB+
//

import Foundation

/// Intestazione di una colonna risultato.
struct ColumnHeader: Sendable, Equatable, Identifiable {
    var id: String { "\(name)#\(index)" }
    let name: String
    let typeName: String
    let isUnsigned: Bool
    let index: Int
}

/// Richiesta di esecuzione di una singola istruzione SQL.
struct StatementRequest: Sendable {
    var sql: String
    var binds: [CellValue] = []
    var rowLimit: Int = 1000
}

/// Risultato strutturato dell'esecuzione di una istruzione.
struct StatementResult: Sendable {
    var columns: [ColumnHeader] = []
    var rows: [[CellValue]] = []
    var affectedRows: UInt64 = 0
    var lastInsertID: UInt64?
    var executionTimeMS: Double = 0
    var truncated = false
    var totalRowCount: Int?
    var errorMessage: String?
    var isError = false
    var executedSQL: String = ""

    var isSelect: Bool { !columns.isEmpty }

    func summary() -> String {
        if isError {
            return errorMessage ?? "Errore"
        }
        if isSelect {
            return "\(rows.count) righe restituite"
        }
        return "\(affectedRows) righe modificate" + (lastInsertID.map { ", ultimo ID: \($0)" } ?? "")
    }
}

/// Envelope per il valore di una cella nel protocollo JSON del bridge.
struct BridgeResponse: Codable, Sendable {
    struct ColumnDTO: Codable, Sendable {
        let name: String
        let type: String
        let unsigned: Bool
    }

    let ok: Bool
    let columns: [ColumnDTO]?
    let rows: [[String?]]?
    let affectedRows: UInt64?
    let lastInsertID: UInt64?
    let ms: Double?
    let error: String?
    let serverVersion: String?
    let truncated: Bool?
}
