//
//  Timeout.swift
//  DB+
//
//  Timeout generico per operazioni asincrone che altrimenti potrebbero
//  restare appese (es. il connect MySQL di MySQLNIO non espone timeout).
//

import Foundation

struct TimeoutError: LocalizedError {
    let seconds: TimeInterval
    var errorDescription: String? {
        "Timeout dopo \(Int(seconds))s — il server non ha risposto. Verifica rete, firewall e che il servizio sia raggiungibile."
    }
}

enum Timeout {
    /// Esegue `operation` e, se non termina entro `seconds`, lancia `TimeoutError`.
    static func withTimeout<T>(
        _ seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw TimeoutError(seconds: seconds)
            }
            let result = try await group.next()
            group.cancelAll()
            guard let result else { throw CancellationError() }
            return result
        }
    }
}
