//
//  SSHInProcessTunnel.swift
//  DB+
//
//  Tunnel SSH in-process per iOS/iPadOS, basato su Citadel (client SSH puro
//  Swift costruito su SwiftNIO). Su iOS non esiste /usr/bin/ssh e la sandbox
//  vieta la creazione di processi figli: il tunnel apre quindi un listener
//  TCP su 127.0.0.1 e instrada ogni connessione su un canale SSH
//  "direct-tcpip" verso il server MySQL remoto.
//
//  Autenticazione supportata:
//    - password;
//    - chiave privata RSA / Ed25519 (formato OpenSSH "openssh-key-v1"),
//      anche protetta da passphrase.
//
//  Sicurezza: le credenziali restano in memoria per la durata del tunnel;
//  la chiave privata viene letta dal file al momento della connessione.
//

#if os(iOS)
import Foundation
import NIOCore
import NIOPosix
import NIOSSH
import Crypto
import Citadel

final class SSHInProcessTunnel: SSHTunnel {
    private var sshClient: SSHClient?
    private var serverChannel: Channel?
    private var group: MultiThreadedEventLoopGroup?

    // MARK: - SSHTunnel

    func start(profile: ConnectionProfile, password: String?, passphrase: String?, timeout: TimeInterval = 30) async throws -> Int {
        let sshHost = profile.sshHost.isEmpty ? "localhost" : profile.sshHost
        let username = profile.sshUsername.isEmpty ? profile.username : profile.sshUsername
        let dbHost = profile.host.isEmpty ? "localhost" : profile.host

        let auth = try Self.makeAuthentication(profile: profile, username: username, password: password, passphrase: passphrase)

        // Un singolo event loop per client SSH, listener locale e canali figli:
        // il `GlueHandler` accede ai canali partner senza attraversare thread.
        let group = MultiThreadedEventLoopGroup(numberOfThreads: 1)
        self.group = group

        let client: SSHClient
        do {
            DebugLog.shared.log("[DB+DEBUG] SSHInProcessTunnel: SSHClient.connect inizio — host=\(sshHost):\(profile.sshPort) user=\(username)")
            client = try await SSHClient.connect(
                host: sshHost,
                port: profile.sshPort,
                authenticationMethod: auth,
                hostKeyValidator: .acceptAnything(),
                reconnect: .never,
                group: group,
                connectTimeout: .seconds(Int64(timeout))
            )
            DebugLog.shared.log("[DB+DEBUG] SSHInProcessTunnel: SSHClient.connect OK")
        } catch {
            DebugLog.shared.log("[DB+DEBUG] SSHInProcessTunnel: SSHClient.connect ERRORE: \(error.localizedDescription)")
            self.group = nil
            try? group.syncShutdownGracefully()
            throw DBError.invalid("Connessione SSH non riuscita: \(error.localizedDescription)")
        }
        self.sshClient = client

        let bootstrap = ServerBootstrap(group: group)
            .serverChannelOption(ChannelOptions.socketOption(.so_reuseaddr), value: 1)
            // Letture sospese finché il canale SSH non è pronto, per non perdere
            // il primo byte (handshake MySQL) che potrebbe arrivare prima del glue.
            .childChannelOption(ChannelOptions.autoRead, value: false)
            .childChannelInitializer { inbound in
                Self.forward(inbound, client: client, dbHost: dbHost, dbPort: profile.port)
            }

        let bound: Channel
        do {
            DebugLog.shared.log("[DB+DEBUG] SSHInProcessTunnel: bind listener locale: inizio")
            bound = try await bootstrap.bind(host: "127.0.0.1", port: 0).get()
            DebugLog.shared.log("[DB+DEBUG] SSHInProcessTunnel: bind listener locale OK")
        } catch {
            DebugLog.shared.log("[DB+DEBUG] SSHInProcessTunnel: bind listener ERRORE: \(error.localizedDescription)")
            await teardown()
            throw DBError.invalid("Impossibile aprire il listener locale del tunnel: \(error.localizedDescription)")
        }
        self.serverChannel = bound

        guard let localPort = bound.localAddress?.port else {
            await teardown()
            throw DBError.invalid("Impossibile determinare la porta locale del tunnel.")
        }
        DebugLog.shared.log("[DB+DEBUG] SSHInProcessTunnel: listener pronto — porta locale \(localPort)")
        return localPort
    }

    func teardown() async {
        let group = self.group
        self.group = nil

        if let serverChannel {
            try? await serverChannel.close().get()
        }
        serverChannel = nil

        if let sshClient {
            try? await sshClient.close()
        }
        sshClient = nil

        if let group {
            try? group.syncShutdownGracefully()
        }
    }

    // MARK: - Autenticazione

    private static func makeAuthentication(
        profile: ConnectionProfile,
        username: String,
        password: String?,
        passphrase: String?
    ) throws -> SSHAuthenticationMethod {
        switch profile.sshAuthType {
        case .password:
            guard let password, !password.isEmpty else {
                throw DBError.invalid("Inserire la password SSH (campo segreto nel Keychain).")
            }
            return .passwordBased(username: username, password: password)

        case .privateKey:
            guard !profile.sshKeyPath.isEmpty else {
                throw DBError.invalid("Nessuna chiave privata selezionata.")
            }
            let url = URL(fileURLWithPath: profile.sshKeyPath)
            DebugLog.shared.log("[DB+DEBUG] makeAuthentication: sshKeyPath=\(profile.sshKeyPath)")
            DebugLog.shared.log("[DB+DEBUG] makeAuthentication: file esiste=\(FileManager.default.fileExists(atPath: url.path)) leggibile=\(FileManager.default.isReadableFile(atPath: url.path))")
            guard let content = try? String(contentsOf: url, encoding: .utf8) else {
                DebugLog.shared.log("[DB+DEBUG] makeAuthentication: lettura chiave FALLITA — \(url.path)")
                if let dirContents = try? FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path) {
                    DebugLog.shared.log("[DB+DEBUG] makeAuthentication: contenuto cartella = \(dirContents)")
                } else {
                    DebugLog.shared.log("[DB+DEBUG] makeAuthentication: cartella \(url.deletingLastPathComponent().path) non leggibile o inesistente")
                }
                throw DBError.invalid("Impossibile leggere la chiave privata '\(url.lastPathComponent)' — file mancante o non accessibile. Percorso: \(url.path)")
            }
            DebugLog.shared.log("[DB+DEBUG] makeAuthentication: chiave letta OK (\(content.count) byte)")

            let decryptionKey: Data?
            if profile.sshUsePassphrase, let passphrase, !passphrase.isEmpty {
                decryptionKey = Data(passphrase.utf8)
            } else {
                decryptionKey = nil
            }

            let keyType: SSHKeyType
            do {
                keyType = try SSHKeyDetection.detectPrivateKeyType(from: content)
            } catch {
                throw DBError.invalid("Chiave privata non valida: \(error.localizedDescription)")
            }

            do {
                switch keyType {
                case .ed25519:
                    let key = try Curve25519.Signing.PrivateKey(sshEd25519: content, decryptionKey: decryptionKey)
                    return .ed25519(username: username, privateKey: key)
                case .rsa:
                    let key = try Insecure.RSA.PrivateKey(sshRsa: content, decryptionKey: decryptionKey)
                    return .rsa(username: username, privateKey: key)
                default:
                    throw DBError.invalid("Chiave \(keyType) non supportata su iOS: usare RSA o Ed25519 (formato openssh-key-v1).")
                }
            } catch let error as DBError {
                throw error
            } catch {
                throw DBError.invalid("Impossibile decifrare la chiave \(keyType) (passphrase errata o formato non supportato): \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Bridging

    /// Collega una connessione TCP locale accettata a un canale SSH direct-tcpip.
    private static func forward(_ inbound: Channel, client: SSHClient, dbHost: String, dbPort: Int) -> EventLoopFuture<Void> {
        guard let originator = inbound.remoteAddress else {
            return inbound.eventLoop.makeFailedFuture(DBError.invalid("Connessione locale senza indirizzo remoto."))
        }
        let promise = inbound.eventLoop.makePromise(of: Void.self)

        Task {
            do {
                let settings = SSHChannelType.DirectTCPIP(
                    targetHost: dbHost,
                    targetPort: dbPort,
                    originatorAddress: originator
                )
                _ = try await client.createDirectTCPIPChannel(using: settings) { sshChannel in
                    let (ours, theirs) = GlueHandler.matchedPair()
                    return sshChannel.pipeline.addHandlers([ours])
                        .flatMap { inbound.pipeline.addHandlers([theirs]) }
                        .map { inbound.read() }
                }
                promise.succeed(())
            } catch {
                promise.fail(error)
            }
        }
        return promise.futureResult
    }
}

// MARK: - GlueHandler
//
// Ponte tra due canali NIO: inoltra letture, flush, cambi di writability e
// eventi di ciclo di vita tra un canale TCP locale e un canale SSH.
// Tratto dall'esempio NIOSSHClient di SwiftNIO.
//
//===----------------------------------------------------------------------===//
// This source file is part of the SwiftNIO open source project
// Copyright (c) 2020 Apple Inc. and the SwiftNIO project authors
// Licensed under Apache License v2.0
//===----------------------------------------------------------------------===//

final class GlueHandler {
    private var partner: GlueHandler?
    private var context: ChannelHandlerContext?
    private var pendingRead = false
    private init() {}
}

extension GlueHandler {
    static func matchedPair() -> (GlueHandler, GlueHandler) {
        let first = GlueHandler()
        let second = GlueHandler()
        first.partner = second
        second.partner = first
        return (first, second)
    }

    private func partnerWrite(_ data: NIOAny) {
        self.context?.write(data, promise: nil)
    }

    private func partnerFlush() {
        self.context?.flush()
    }

    private func partnerWriteEOF() {
        self.context?.close(mode: .output, promise: nil)
    }

    private func partnerCloseFull() {
        self.context?.close(promise: nil)
    }

    private func partnerBecameWritable() {
        if self.pendingRead {
            self.pendingRead = false
            self.context?.read()
        }
    }

    private var partnerWritable: Bool {
        self.context?.channel.isWritable ?? false
    }
}

extension GlueHandler: ChannelDuplexHandler {
    typealias InboundIn = NIOAny
    typealias OutboundIn = NIOAny
    typealias OutboundOut = NIOAny

    func handlerAdded(context: ChannelHandlerContext) {
        self.context = context
        // Potrebbe essere arrivato prima che il partner fosse registrato:
        // aggiorna la condizione di writability.
        if context.channel.isWritable {
            self.partner?.partnerBecameWritable()
        }
    }

    func handlerRemoved(context: ChannelHandlerContext) {
        self.context = nil
        self.partner = nil
    }

    func channelRead(context: ChannelHandlerContext, data: NIOAny) {
        self.partner?.partnerWrite(data)
    }

    func channelReadComplete(context: ChannelHandlerContext) {
        self.partner?.partnerFlush()
    }

    func channelInactive(context: ChannelHandlerContext) {
        self.partner?.partnerCloseFull()
    }

    func userInboundEventTriggered(context: ChannelHandlerContext, event: Any) {
        if let event = event as? ChannelEvent, case .inputClosed = event {
            // EOF letto: inoltra la chiusura della metà di scrittura.
            self.partner?.partnerWriteEOF()
        }
    }

    func errorCaught(context: ChannelHandlerContext, error: Error) {
        self.partner?.partnerCloseFull()
    }

    func channelWritabilityChanged(context: ChannelHandlerContext) {
        if context.channel.isWritable {
            self.partner?.partnerBecameWritable()
        }
    }

    func read(context: ChannelHandlerContext) {
        if let partner = self.partner, partner.partnerWritable {
            context.read()
        } else {
            self.pendingRead = true
        }
    }
}

#endif // os(iOS)
