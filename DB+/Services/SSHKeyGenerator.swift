//
//  SSHKeyGenerator.swift
//  DB+
//
//  Generazione di coppie di chiavi SSH Ed25519 in formato OpenSSH
//  ("openssh-key-v1"). swift-crypto genera la chiave, Citadel la
//  serializza. La chiave viene salvata non cifrata nella cartella
//  SSHKeys della sandbox.
//

import Foundation
import Crypto
import Citadel

struct GeneratedKey {
    let name: String
    let privateKeyURL: URL
    let publicKeyURL: URL
    let publicKeyLine: String
    let privatePEM: String
}

enum SSHKeyGenerator {
    /// Genera una coppia di chiavi Ed25519, salva la privata in
    /// `SSHKeys/<name>` e la pubblica in `SSHKeys/<name>.pub`,
    /// poi restituisce i percorsi e la chiave pubblica.
    static func generateEd25519(name: String, comment: String = "") throws -> GeneratedKey {
        let safeName = sanitize(name)
        // Il commento finisce nella riga .pub: rimuove i newline per evitare
        // di corrompere l'artefatto che l'utente incolla in authorized_keys.
        let safeComment = comment.filter { !$0.isNewline }
        let directory = try keysDirectory()
        let privateURL = try uniqueFileURL(in: directory, baseName: safeName)
        let publicURL = directory.appendingPathComponent(privateURL.lastPathComponent + ".pub")

        let privateKey = Curve25519.Signing.PrivateKey()
        let pem = privateKey.makeSSHRepresentation(comment: safeComment)
        let publicKeyLine = makePublicKeyLine(privateKey: privateKey, comment: safeComment)

        #if os(iOS)
        try Data(pem.utf8).write(to: privateURL, options: [.atomic, .completeFileProtection])
        #else
        try Data(pem.utf8).write(to: privateURL, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: privateURL.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: directory.path)

        try Data((publicKeyLine + "\n").utf8).write(to: publicURL, options: .atomic)

        return GeneratedKey(
            name: safeName,
            privateKeyURL: privateURL,
            publicKeyURL: publicURL,
            publicKeyLine: publicKeyLine,
            privatePEM: pem
        )
    }

    // MARK: - Helper

    /// Mantiene solo alfanumerici e `_-.`; nome vuoto → "dbplus".
    private static func sanitize(_ name: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_-."))
        let cleaned = String(
            name.trimmingCharacters(in: .whitespacesAndNewlines)
                .unicodeScalars.filter { allowed.contains($0) }
        )
        return cleaned.isEmpty ? "dbplus" : cleaned
    }

    /// Directory `Application Support/SSHKeys`, creata se manca.
    private static func keysDirectory() throws -> URL {
        let fm = FileManager.default
        let base = try fm.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        let dir = base.appendingPathComponent("SSHKeys", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Risolve il percorso di una chiave salvata che potrebbe essere diventato
    /// stantio: il percorso assoluto salvato nel profilo punta al container
    /// iOS di prima (es. dopo un ripristino da backup l'UUID del container
    /// cambia ma i file vengono ripristinati). Se il file al percorso salvato
    /// non esiste, cerca un file con lo stesso nome nella cartella `SSHKeys`
    /// attuale; se non lo trova, restituisce il percorso originale.
    static func resolvedKeyPath(_ storedPath: String) -> String {
        guard !storedPath.isEmpty else { return storedPath }
        let fm = FileManager.default
        if fm.fileExists(atPath: storedPath) {
            return storedPath
        }
        let name = URL(fileURLWithPath: storedPath).lastPathComponent
        guard !name.isEmpty else { return storedPath }
        if let dir = try? keysDirectory() {
            let candidate = dir.appendingPathComponent(name)
            if fm.fileExists(atPath: candidate.path) {
                return candidate.path
            }
        }
        return storedPath
    }

    /// Primo percorso libero: `<name>`, altrimenti `<name>-2`, `<name>-3`, …
    private static func uniqueFileURL(in dir: URL, baseName: String) throws -> URL {
        let fm = FileManager.default
        var candidate = baseName
        var i = 2
        while fm.fileExists(atPath: dir.appendingPathComponent(candidate).path)
            || fm.fileExists(atPath: dir.appendingPathComponent(candidate + ".pub").path) {
            candidate = "\(baseName)-\(i)"
            i += 1
        }
        return dir.appendingPathComponent(candidate)
    }

    /// Riga OpenSSH "ssh-ed25519 <base64> <comment>" (wire-format: due ssh-string).
    private static func makePublicKeyLine(
        privateKey: Curve25519.Signing.PrivateKey, comment: String
    ) -> String {
        var data = Data()
        appendSSHString("ssh-ed25519", to: &data)
        appendSSHString(privateKey.publicKey.rawRepresentation, to: &data)
        let suffix = comment.isEmpty ? "" : " \(comment)"
        return "ssh-ed25519 \(data.base64EncodedString())\(suffix)"
    }

    private static func appendSSHString(_ value: String, to data: inout Data) {
        appendSSHString(Data(value.utf8), to: &data)
    }

    private static func appendSSHString(_ bytes: Data, to data: inout Data) {
        var length = UInt32(bytes.count).bigEndian
        withUnsafeBytes(of: &length) { data.append(contentsOf: $0) }
        data.append(bytes)
    }
}
