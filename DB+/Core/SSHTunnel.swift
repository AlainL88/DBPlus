//
//  SSHTunnel.swift
//  DB+
//
//  Contratto comune dei tunnel SSH. L'implementazione dipende dalla piattaforma:
//  - macOS: `SSHProcessTunnel` (OpenSSH di sistema via Process);
//  - iOS/iPadOS: `SSHInProcessTunnel` (client SSH in-process, Citadel).
//
//  Entrambe aprono un port forwarding locale e restituiscono la porta a cui
//  collegarsi per raggiungere il database remoto attraverso il tunnel.
//

import Foundation

protocol SSHTunnel: AnyObject {
    /// Avvia il tunnel e restituisce la porta locale da usare per MySQL.
    func start(profile: ConnectionProfile, password: String?, passphrase: String?, timeout: TimeInterval) async throws -> Int

    /// Rilascia processo/risorse e file temporanei dei segreti.
    func teardown() async
}
