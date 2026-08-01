//
//  SQLHighlighter.swift
//  DB+
//
//  Evidenziazione sintattica leggera per il dialetto MySQL/MariaDB.
//  Tokenizer basato su espressioni regolari, applicato a un NSTextView.
//

import Foundation

#if os(macOS)
import AppKit

enum SQLHighlighter {

    static let keywords: Set<String> = [
        "select", "from", "where", "insert", "into", "values", "update", "set",
        "delete", "create", "alter", "drop", "truncate", "table", "database",
        "schema", "index", "view", "procedure", "function", "trigger", "grant",
        "revoke", "join", "inner", "left", "right", "outer", "full", "cross",
        "on", "as", "and", "or", "not", "null", "is", "in", "exists", "between",
        "like", "regexp", "rlike", "limit", "offset", "order", "by", "group",
        "having", "union", "all", "distinct", "primary", "key", "foreign",
        "references", "constraint", "unique", "default", "auto_increment",
        "collate", "engine", "charset", "character", "check", "begin",
        "commit", "rollback", "use", "show", "describe", "desc", "explain",
        "case", "when", "then", "else", "end", "if", "elseif", "while", "do",
        "loop", "declare", "cursor", "return", "returns", "with", "recursive",
        "over", "partition", "rows", "range", "preceding", "following", "current"
    ]

    static let functions: Set<String> = [
        "count", "sum", "avg", "min", "max", "abs", "round", "floor", "ceil",
        "length", "char_length", "concat", "concat_ws", "substring", "substr",
        "replace", "upper", "lower", "trim", "ltrim", "rtrim", "left", "right",
        "ifnull", "coalesce", "nullif", "now", "curdate", "curtime", "date",
        "time", "year", "month", "day", "hour", "minute", "second", "date_format",
        "str_to_date", "datediff", "date_add", "date_sub", "unix_timestamp",
        "from_unixtime", "group_concat", "find_in_set", "locate", "instr",
        "reverse", "repeat", "space", "uuid", "uuid_short", "last_insert_id",
        "row_count", "cast", "convert", "bin", "hex", "unhex", "md5", "sha1",
        "sha2", "rand", "greatest", "least", "pow", "power", "sqrt", "mod",
        "database", "schema", "version", "user", "current_user", "connection_id"
    ]

    // MARK: - Colorazione

    static func highlight(_ text: String) -> NSAttributedString {
        let attr = NSMutableAttributedString(string: text, attributes: baseAttributes())

        // Commenti (con precedenza sulle stringhe)
        apply(pattern: #"(--[^\n]*|#[^\n]*)"#, in: text, to: attr,
              color: commentColor(), usesFont: true)
        apply(pattern: #"/\*[\s\S]*?\*/"#, in: text, to: attr,
              color: commentColor(), usesFont: true)

        // Stringhe (con escape \')
        apply(pattern: #"'(\\.|[^'\\])*'"#, in: text, to: attr,
              color: stringColor())

        // Identificatori tra backtick
        apply(pattern: #"`(\\.|[^`\\])*`"#, in: text, to: attr,
              color: identifierColor())

        // Variabili di sessione @var
        apply(pattern: #"@[\w.]+"#, in: text, to: attr,
              color: variableColor())

        // Numeri
        apply(pattern: #"\b\d+(\.\d+)?([eE][+-]?\d+)?"#, in: text, to: attr,
              color: numberColor())

        // Parole chiave (case-insensitive)
        let keywordPattern = "\\b(?:\(keywords.sorted { $0.count > $1.count }.joined(separator: "|")))\\b"
        apply(pattern: keywordPattern, in: text, to: attr, color: keywordColor(), options: [.caseInsensitive])

        // Funzioni
        let functionPattern = "\\b(?:\(functions.sorted { $0.count > $1.count }.joined(separator: "|")))\\s*\\("
        apply(pattern: functionPattern, in: text, to: attr, color: functionColor(), options: [.caseInsensitive])

        return attr
    }

    // MARK: - Helpers

    private static func baseAttributes() -> [NSAttributedString.Key: Any] {
        [
            .foregroundColor: NSColor.labelColor,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        ]
    }

    private static func apply(
        pattern: String,
        in text: String,
        to attr: NSMutableAttributedString,
        color: NSColor,
        usesFont: Bool = false,
        options: NSRegularExpression.Options = []
    ) {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return }
        let nsText = text as NSString
        let fullRange = NSRange(location: 0, length: nsText.length)
        regex.enumerateMatches(in: text, options: [], range: fullRange) { match, _, _ in
            guard let match, let range = match.rangeOptimal(in: text) else { return }
            attr.addAttribute(.foregroundColor, value: color, range: range)
            if usesFont {
                attr.addAttribute(.font,
                                  value: NSFont.monospacedSystemFont(ofSize: 13, weight: .semibold),
                                  range: range)
            }
        }
    }

    private static func dynamicColor(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        }
    }

    private static func keywordColor() -> NSColor { dynamicColor(light: .systemPurple, dark: .systemPink) }
    private static func functionColor() -> NSColor { dynamicColor(light: .systemTeal, dark: .systemTeal) }
    private static func stringColor() -> NSColor { dynamicColor(light: .systemGreen, dark: .systemGreen) }
    private static func commentColor() -> NSColor { .secondaryLabelColor }
    private static func numberColor() -> NSColor { dynamicColor(light: .systemOrange, dark: .systemOrange) }
    private static func identifierColor() -> NSColor { dynamicColor(light: .systemBlue, dark: .systemCyan) }
    private static func variableColor() -> NSColor { dynamicColor(light: .systemRed, dark: .systemRed) }
}

extension NSTextCheckingResult {
    /// Restituisce il range senza catturare gruppi vuoti problematici.
    func rangeOptimal(in text: String) -> NSRange? {
        range(at: 0)
    }
}

#endif // os(macOS)
