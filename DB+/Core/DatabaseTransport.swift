//
//  DatabaseTransport.swift
//  DB+
//
//  Astrazione unificata delle tre modalità di connessione:
//    .direct  → MySQLNIO TCP/IP (+TLS opzionale)
//    .ssh     → tunnel SSH locale (OpenSSH di sistema) + MySQLNIO
//    .bridge  → HTTPS verso lo script remoto db_bridge.php
//

import Foundation

protocol DatabaseTransport: AnyObject {
    var mode: ConnectionMode { get }
    var isConnected: Bool { get }

    /// Stabilisce la connessione e restituisce le informazioni del server.
    func connect() async throws -> ServerInfo

    /// Chiude la connessione e rilascia tutte le risorse (socket/SSH).
    func close() async

    /// Misura la latenza di un ping sul server.
    func pingLatency() async throws -> Double

    /// Esegue una singola istruzione SQL. Se `request.binds` è popolato usa
    /// prepared statement (anti SQL injection), altrimenti esecuzione diretta.
    func execute(_ request: StatementRequest) async throws -> StatementResult

    /// Esegue una SELECT in streaming riga-per-riga (per dataset molto grandi).
    /// Restituisce il numero di righe processate.
    func stream(_ sql: String, onRow: @escaping @Sendable ([CellValue]) async throws -> Void) async throws -> Int

    // MARK: - Introspezione schema

    func listSchemas() async throws -> [String]
    func listTables(schema: String) async throws -> [String]
    func listViews(schema: String) async throws -> [String]
    func listRoutines(schema: String, kind: String) async throws -> [String]
    func tableStructure(schema: String, table: String) async throws -> TableStructure
    func tableRowCount(schema: String, table: String) async throws -> Int
    func primaryKeyColumns(schema: String, table: String) async throws -> [String]

    /// Cambia lo schema di default della connessione (solo per connessioni dirette/SSH).
    func useSchema(_ schema: String) async throws
}

/// Helper per il quoting di identificatori SQL (nomi schema/tabella/colonna).
enum SQLIdentifier {
    static func quote(_ name: String) -> String {
        "`" + name.replacingOccurrences(of: "`", with: "``") + "`"
    }
}
