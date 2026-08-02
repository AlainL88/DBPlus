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
    ///
    /// Il timeout è implementato con un timer su coda globale (DispatchQueue),
    /// indipendente dall'actor/executor corrente: scatta anche se l'operazione
    /// non cede mai il controllo (il pattern con `Task.sleep` in un task group
    /// può non scattare quando l'operazione blocca l'actor).
    static func withTimeout<T>(
        _ seconds: TimeInterval,
        operation: @escaping () async throws -> T
    ) async throws -> T {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<T, Error>) in
            let lock = NSLock()
            var finished = false

            func finish(_ result: Result<T, Error>) {
                lock.lock()
                guard !finished else { lock.unlock(); return }
                finished = true
                lock.unlock()
                continuation.resume(with: result)
            }

            let timer = DispatchWorkItem {
                finish(.failure(TimeoutError(seconds: seconds)))
            }
            DispatchQueue.global().asyncAfter(deadline: .now() + seconds, execute: timer)

            Task {
                do {
                    let value = try await operation()
                    timer.cancel()
                    finish(.success(value))
                } catch {
                    timer.cancel()
                    finish(.failure(error))
                }
            }
        }
    }
}
