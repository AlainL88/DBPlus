//
//  SSHProcessTunnel.swift
//  DB+
//
//  Tunnel SSH locale basato su OpenSSH di sistema (/usr/bin/ssh).
//
//  Gestione della segretezza:
//  - Password / passphrase vengono fornite a ssh tramite SSH_ASKPASS
//    (script temporaneo + file segreto chmod 600), eliminati subito
//    dopo il teardown. Nessun segreto persistito su disco.
//  - Chiave privata (RSA/Ed25519) via flag -i.
//
//  Resilienza: ServerAliveInterval, ExitOnForwardFailure e riconnessione
//  trasparente gestita dal livello superiore.
//

import Darwin
import Foundation

#if os(macOS)

final class SSHProcessTunnel: SSHTunnel {
    private var process: Process?
    private var helperDirectory: URL?
    private var stderrBuffer = LockedBuffer()

    /// Avvia il tunnel e restituisce la porta locale da usare per MySQL.
    func start(
        profile: ConnectionProfile,
        password: String?,
        passphrase: String?,
        timeout: TimeInterval = 30
    ) async throws -> Int {
        let localPort = Self.randomFreePort()
        let sshHost = profile.sshHost.isEmpty ? "localhost" : profile.sshHost
        let username = profile.sshUsername.isEmpty ? profile.username : profile.sshUsername
        let dbHost = profile.host.isEmpty ? "localhost" : profile.host

        var args: [String] = [
            "-N",
            "-L", "\(localPort):\(dbHost):\(profile.port)",
            "-o", "ServerAliveInterval=15",
            "-o", "ServerAliveCountMax=3",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "ConnectTimeout=15",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "LogLevel=ERROR",
            "-p", String(profile.sshPort)
        ]

        var needsSecret = false
        switch profile.sshAuthType {
        case .password:
            needsSecret = true
        case .privateKey:
            if !profile.sshKeyPath.isEmpty {
                args.append(contentsOf: ["-i", SSHKeyGenerator.resolvedKeyPath(profile.sshKeyPath)])
            }
            needsSecret = profile.sshUsePassphrase
        }

        args.append("\(username)@\(sshHost)")

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.arguments = args
        process.standardOutput = Pipe()

        let errPipe = Pipe()
        process.standardError = errPipe
        errPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let s = String(data: data, encoding: .utf8) {
                self?.stderrBuffer.append(s)
            }
        }

        if needsSecret {
            let secret = profile.sshAuthType == .password ? password : passphrase
            process.environment = try Self.setupAskpass(secret: secret ?? "")
        }

        self.process = process
        try process.run()
        process.terminationHandler = { [weak self] proc in
            self?.stderrBuffer.append("(ssh terminato, codice \(proc.terminationStatus))")
        }
        DebugLog.shared.log("[DB+DEBUG] SSHProcessTunnel: /usr/bin/ssh avviato — attendo la porta locale \(localPort)…")

        // Attende che la porta locale accetti connessioni.
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !process.isRunning {
                break
            }
            if Self.canConnect(host: "127.0.0.1", port: localPort, timeout: 0.2) {
                DebugLog.shared.log("[DB+DEBUG] SSHProcessTunnel: porta locale \(localPort) pronta")
                return localPort
            }
            try await Task.sleep(nanoseconds: 200_000_000)
        }

        let isUp = process.isRunning
        let stderr = stderrBuffer.drain()
        DebugLog.shared.log("[DB+DEBUG] SSHProcessTunnel: FALLITO — isUp=\(isUp) stderr=\(stderr.isEmpty ? "(vuoto)" : stderr)")
        await teardown()

        if isUp && !stderr.isEmpty {
            throw DBError.invalid("Tunnel SSH stabilito ma il server ha riportato: \(stderr)")
        }
        throw DBError.invalid("Tunnel SSH non riuscito\(stderr.isEmpty ? "" : ": \(stderr)")")
    }

    /// Rilascia il processo ssh e i file temporanei dei segreti.
    func teardown() async {
        if let process, process.isRunning {
            process.terminate()
            let deadline = Date().addingTimeInterval(3)
            while process.isRunning && Date() < deadline {
                usleep(100_000)
            }
            if process.isRunning {
                Darwin.kill(process.processIdentifier, SIGKILL)
            }
        }
        process = nil
        cleanupAskpass()
    }

    // MARK: - Askpass

    /// Crea una directory temporanea con script askpass + file segreto.
    private static func setupAskpass(secret: String) throws -> [String: String] {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DBplus-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let secretURL = dir.appendingPathComponent("secret")
        try secret.data(using: .utf8)?.write(to: secretURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: secretURL.path)

        let helperURL = dir.appendingPathComponent("askpass.sh")
        try "#! /bin/sh\ncat \"\(secretURL.path)\"\n".write(to: helperURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: helperURL.path)

        var env = ProcessInfo.processInfo.environment
        env["SSH_ASKPASS"] = helperURL.path
        env["SSH_ASKPASS_REQUIRE"] = "force"
        env["DISPLAY"] = ":0"
        env["HOME"] = NSHomeDirectory()
        // Conserva il riferimento per la pulizia.
        SharedHelperDirectory.value = dir
        return env
    }

    private func cleanupAskpass() {
        if let dir = SharedHelperDirectory.value {
            try? FileManager.default.removeItem(at: dir)
        }
        SharedHelperDirectory.value = nil
    }

    // MARK: - Utility socket

    static func canConnect(host: String, port: Int, timeout: TimeInterval) -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = in_port_t(port).bigEndian
        addr.sin_addr.s_addr = inet_addr(host)

        let sock = socket(AF_INET, SOCK_STREAM, 0)
        guard sock >= 0 else { return false }
        defer { close(sock) }

        let wholeSeconds = Int(timeout)
        let microSeconds = Int32((timeout - Double(wholeSeconds)) * 1_000_000)
        var tv = timeval(tv_sec: wholeSeconds, tv_usec: microSeconds)
        setsockopt(sock, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(sock, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        let result = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                Darwin.connect(sock, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        return result == 0
    }

    static func randomFreePort() -> Int {
        for _ in 0..<50 {
            let candidate = Int.random(in: 49152...65535)
            if !canConnect(host: "127.0.0.1", port: candidate, timeout: 0.05) {
                return candidate
            }
        }
        return Int.random(in: 49152...65535)
    }
}

/// Buffer thread-safe per l'accumulo dello stderr del processo ssh.
private final class LockedBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var text = ""

    func append(_ s: String) {
        lock.lock()
        text += s
        lock.unlock()
    }

    func drain() -> String {
        lock.lock()
        defer { lock.unlock() }
        let t = text
        text = ""
        return t
    }
}

/// Directory askpass condivisa tra setup (static) e teardown (instance).
private enum SharedHelperDirectory {
    static var value: URL?
}

#else

/// Su iOS/iPadOS il tunnel via OpenSSH di sistema non esiste: qui vive solo
/// lo stub di compatibilità; la modalità SSH usa `SSHInProcessTunnel`.
final class SSHProcessTunnel: SSHTunnel {
    func start(
        profile: ConnectionProfile,
        password: String?,
        passphrase: String?,
        timeout: TimeInterval = 30
    ) async throws -> Int {
        throw DBError.invalid("Tunnel OpenSSH di sistema non disponibile su iOS: usare il tunnel in-process.")
    }

    func teardown() async {}
}

#endif // os(macOS)
