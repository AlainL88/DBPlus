//
//  SQLSplitter.swift
//  DB+
//

import Foundation

/// Splitta script SQL multi-statement rispettando stringhe, backtick e commenti.
enum SQLSplitter {

    static func split(_ sql: String) -> [String] {
        var statements: [String] = []
        var current = ""
        var i = sql.startIndex

        var inSingle = false
        var inDouble = false
        var inBacktick = false
        var inLineComment = false
        var inBlockComment = false

        while i < sql.endIndex {
            let c = sql[i]
            let next = sql.index(after: i)

            if inLineComment {
                current.append(c)
                if c == "\n" { inLineComment = false }
            } else if inBlockComment {
                current.append(c)
                if c == "*", next < sql.endIndex, sql[next] == "/" {
                    inBlockComment = false
                    i = next
                    current.append("/")
                }
            } else if inSingle {
                current.append(c)
                if c == "'" {
                    if next < sql.endIndex, sql[next] == "'" {
                        current.append("'")
                        i = next
                    } else {
                        inSingle = false
                    }
                }
            } else if inDouble {
                current.append(c)
                if c == "\"" {
                    if next < sql.endIndex, sql[next] == "\"" {
                        current.append("\"")
                        i = next
                    } else {
                        inDouble = false
                    }
                }
            } else if inBacktick {
                current.append(c)
                if c == "`" {
                    if next < sql.endIndex, sql[next] == "`" {
                        current.append("`")
                        i = next
                    } else {
                        inBacktick = false
                    }
                }
            } else {
                if c == "'" {
                    inSingle = true
                    current.append(c)
                } else if c == "\"" {
                    inDouble = true
                    current.append(c)
                } else if c == "`" {
                    inBacktick = true
                    current.append(c)
                } else if c == "-", next < sql.endIndex, sql[next] == "-" {
                    inLineComment = true
                    current.append(c)
                } else if c == "#" {
                    inLineComment = true
                    current.append(c)
                } else if c == "/", next < sql.endIndex, sql[next] == "*" {
                    inBlockComment = true
                    current.append("/*")
                    i = next
                } else if c == ";" {
                    let stmt = current.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !stmt.isEmpty { statements.append(stmt) }
                    current = ""
                } else {
                    current.append(c)
                }
            }

            i = sql.index(after: i)
        }

        let tail = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !tail.isEmpty { statements.append(tail) }
        return statements
    }
}
