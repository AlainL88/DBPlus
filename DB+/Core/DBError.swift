//
//  DBError.swift
//  DB+
//

import Foundation

/// Errori tipizzati dell'applicazione.
enum DBError: LocalizedError {
    case notConnected
    case server(code: Int, message: String)
    case invalid(String)
    case cancelled

    var errorDescription: String? {
        switch self {
        case .notConnected:
            return "Nessuna connessione attiva."
        case .server(let code, let message):
            return "Errore server MySQL (\(code)): \(message)"
        case .invalid(let message):
            return message
        case .cancelled:
            return "Operazione annullata."
        }
    }
}
