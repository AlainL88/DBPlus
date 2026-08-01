//
//  QueryRunner.swift
//  DB+
//
//  Esegue script SQL multi-statement (SELECT, DDL, DML) nel Workbench,
//  riportando il tempo di esecuzione in ms e le righe modificate/restituite.
//

import Foundation

struct QueryRunner {
    let transport: any DatabaseTransport

    /// Esegue uno script (possibilmente multi-statement). Ogni risultato
    /// viene passato alla callback prima di restituire l'array completo.
    func runScript(_ sql: String, rowLimit: Int, onStatement: (StatementResult) -> Void) async throws -> [StatementResult] {
        let statements = SQLSplitter.split(sql)
        var results: [StatementResult] = []
        for statement in statements {
            let result = try await transport.execute(StatementRequest(sql: statement, rowLimit: rowLimit))
            results.append(result)
            onStatement(result)
        }
        return results
    }
}
