//
//  CellValue.swift
//  DB+
//

import Foundation

/// Rappresentazione neutrale e serializzabile di un singolo valore di cella,
/// indipendente dal driver (MySQLNIO / Bridge JSON).
enum CellValue: Sendable, Equatable {
    case null
    case int(Int64)
    case uint(UInt64)
    case double(Double)
    case string(String)
    case data(Data)
    case decimal(String)
    case bool(Bool)
    case date(Date)
    case time(Double)

    var isNull: Bool {
        if case .null = self { return true }
        return false
    }

    /// Testo da mostrare nella griglia.
    var displayString: String {
        switch self {
        case .null: return "NULL"
        case .int(let v): return String(v)
        case .uint(let v): return String(v)
        case .double(let v): return String(v)
        case .string(let s): return s
        case .data(let d): return "\(d.count) byte"
        case .decimal(let s): return s
        case .bool(let b): return b ? "1" : "0"
        case .date(let d): return Self.dateFormatter.string(from: d)
        case .time(let t): return String(t)
        }
    }

    /// Valore "grezzo" come stringa, usato per la modifica inline.
    var editString: String {
        if isNull { return "" }
        return displayString
    }

    /// Rappresentazione stringa per il binding JSON verso il bridge.
    var bridgeString: String? {
        if isNull { return nil }
        return displayString
    }

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    /// Costruisce un valore da una stringa di input (modifica cella).
    static func fromEditString(_ s: String, asHeader: ColumnHeader) -> CellValue {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return .null }
        let type = asHeader.typeName.lowercased()
        if type.contains("int") || type.contains("bit") {
            if let v = Int64(trimmed) { return .int(v) }
            if let v = UInt64(trimmed) { return .uint(v) }
            return .string(trimmed)
        }
        if type.contains("double") || type.contains("float") || type.contains("decimal") {
            if let v = Double(trimmed) { return .double(v) }
            return .decimal(trimmed)
        }
        return .string(s)
    }
}
