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
    /// File persistito (Documents/DebugLog.txt): sopravvive alla terminazione
    /// dell'app, così dopo un crash/blocco si può ricostruire l'ultimo tratto.
    private let logFileURL: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        logFileURL = (docs ?? FileManager.default.temporaryDirectory).appendingPathComponent("DebugLog.txt")
    }

    func log(_ message: String) {
        guard enabled else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        let line = String(format: "%6.1fs  %@", elapsed, message)
        lock.lock()
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        appendToFile(line)
        lock.unlock()
        print(line)
    }

    private func appendToFile(_ line: String) {
        guard let data = (line + "\n").data(using: .utf8) else { return }
        if FileManager.default.fileExists(atPath: logFileURL.path) {
            guard let handle = try? FileHandle(forWritingTo: logFileURL) else { return }
            defer { try? handle.close() }
            handle.seekToEndOfFile()
            handle.write(data)
        } else {
            try? data.write(to: logFileURL)
        }
    }

    func clear() {
        lock.lock()
        lines = []
        try? FileManager.default.removeItem(at: logFileURL)
        lock.unlock()
    }

    /// Contenuto persistito su file (ultima sessione, sopravvive al crash).
    func readPersistedLog() -> String {
        lock.lock()
        defer { lock.unlock() }
        return (try? String(contentsOf: logFileURL, encoding: .utf8)) ?? ""
    }

    /// Snapshot thread-safe per la UI (i log arrivano da thread in background).
    func snapshot() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return lines
    }
}
