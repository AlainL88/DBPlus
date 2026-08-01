//
//  SQLGuard.swift
//  DB+
//
//  Protezione delle operazioni distruttive: richiede conferma esplicita
//  per DROP / TRUNCATE / DELETE senza WHERE / UPDATE massivi / ALTER.
//

import Foundation

enum SQLGuard {

    struct Verdict {
        let requiresConfirmation: Bool
        let message: String
    }

    static func assess(_ sql: String) -> Verdict {
        let trimmed = sql.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return Verdict(requiresConfirmation: false, message: "") }

        let upper = trimmed.uppercased()

        if upper.hasPrefix("DROP") {
            return Verdict(requiresConfirmation: true,
                           message: "DROP elimina definitivamente oggetti del database. L'operazione è irreversibile. Continuare?")
        }
        if upper.hasPrefix("TRUNCATE") {
            return Verdict(requiresConfirmation: true,
                           message: "TRUNCATE svuota completamente la tabella. L'operazione è irreversibile. Continuare?")
        }
        if upper.hasPrefix("DELETE") {
            if !containsWhereClause(sql) {
                return Verdict(requiresConfirmation: true,
                               message: "DELETE senza clausola WHERE cancellerà TUTTE le righe della tabella. Continuare?")
            }
        }
        if upper.hasPrefix("UPDATE") {
            if !containsWhereClause(sql) {
                return Verdict(requiresConfirmation: true,
                               message: "UPDATE senza clausola WHERE modificherà TUTTE le righe della tabella. Continuare?")
            }
        }
        if upper.hasPrefix("ALTER") {
            return Verdict(requiresConfirmation: true,
                           message: "ALTER modifica la struttura di una tabella. Continuare?")
        }
        if upper.hasPrefix("RENAME") {
            return Verdict(requiresConfirmation: true,
                           message: "RENAME modifica i nomi degli oggetti. Continuare?")
        }
        return Verdict(requiresConfirmation: false, message: "")
    }

    /// Verifica in modo approssimativo la presenza di una clausola WHERE
    /// fuori da stringhe, ignorando commenti.
    static func containsWhereClause(_ sql: String) -> Bool {
        var i = sql.startIndex
        var inSingle = false
        var inDouble = false
        var inBacktick = false
        var inLineComment = false
        var inBlockComment = false
        var buffer = ""

        while i < sql.endIndex {
            let c = sql[i]
            let next = sql.index(after: i)

            if inLineComment {
                if c == "\n" { inLineComment = false }
            } else if inBlockComment {
                if c == "*", next < sql.endIndex, sql[next] == "/" {
                    inBlockComment = false
                    i = next
                }
            } else if inSingle {
                if c == "'", next < sql.endIndex, sql[next] == "'" {
                    i = next
                } else if c == "'" {
                    inSingle = false
                }
            } else if inDouble {
                if c == "\"", next < sql.endIndex, sql[next] == "\"" {
                    i = next
                } else if c == "\"" {
                    inDouble = false
                }
            } else if inBacktick {
                if c == "`" { inBacktick = false }
            } else {
                if c == "'" { inSingle = true }
                else if c == "\"" { inDouble = true }
                else if c == "`" { inBacktick = true }
                else if c == "-", next < sql.endIndex, sql[next] == "-" { inLineComment = true; i = next }
                else if c == "#" { inLineComment = true }
                else if c == "/", next < sql.endIndex, sql[next] == "*" { inBlockComment = true; i = next }
                else if c.isLetter || c.isNumber || c == "_" {
                    buffer.append(c)
                } else {
                    if buffer.uppercased() == "WHERE" {
                        return true
                    }
                    buffer = ""
                }
            }
            i = sql.index(after: i)
        }
        return buffer.uppercased() == "WHERE"
    }
}
