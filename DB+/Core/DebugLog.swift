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

    func log(_ message: String) {
        guard enabled else { return }
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds - start.uptimeNanoseconds) / 1_000_000_000
        let line = String(format: "%6.1fs  %@", elapsed, message)
        lines.append(line)
        if lines.count > maxLines {
            lines.removeFirst(lines.count - maxLines)
        }
        print(line)
    }

    func clear() {
        lines = []
    }
}
