//
//  DebugLog.swift
//  DB+
//
//  Raccolta temporanea dei messaggi di debug per mostrarli IN-APP
//  (su device i `print` non sono visibili). I messaggi vengono anche
//  stampati su console. Da rimuovere a fine fase di test.
//

import Foundation
import Observation

@Observable
final class DebugLog {
    static let shared = DebugLog()

    /// Se false, i messaggi non vengono raccolti né stampati.
    var enabled = true
    private(set) var lines: [String] = []

    private let maxLines = 300
    private let start = DispatchTime.now()
    // `log` viene chiamato da più thread (NIO event loop, dispatch queue di
    // lavoro): senza lock l'array `lines` va in data race e l'app crasha
    // (EXC_BAD_ACCESS in _ArrayBuffer durante append/removeFirst).
    private let lock = NSLock()

    func log(_ message: String) {
        guard enabled else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        let line = String(format: "%6.1fs  %@", elapsed, message)
        lock.lock()
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        lock.unlock()
        print(line)
    }

    func clear() {
        lock.lock()
        lines = []
        lock.unlock()
    }

    /// Snapshot thread-safe per la UI (i log arrivano da thread in background).
    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
