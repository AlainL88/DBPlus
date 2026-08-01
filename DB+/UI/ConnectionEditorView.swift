//
//  ConnectionEditorView.swift
//  DB+
//

import SwiftUI
import UniformTypeIdentifiers

struct ConnectionEditorView: View {
    let onSave: (ConnectionProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var showKeyImporter = false
    @State private var showKeyGenerator = false

    /// Modalità disponibili su questa piattaforma (tutte, incluso il tunnel SSH).
    private var availableModes: [ConnectionMode] {
        ConnectionMode.allCases
    }

    @State private var name = ""
    @State private var host = ""
    @State private var port = "3306"
    @State private var username = ""
    @State private var defaultSchema = ""
    @State private var useTLS = true
    @State private var allowSelfSignedTLS = false
    @State private var mode: ConnectionMode = .direct

    // SSH
    @State private var sshHost = ""
    @State private var sshPort = "22"
    @State private var sshUsername = ""
    @State private var sshAuthType: SSHAuthType = .password
    @State private var sshKeyPath = ""
    @State private var sshUsePassphrase = false

    // Bridge
    @State private var bridgeURL = ""
    @State private var bridgeUseHMAC = true

    // Segreti (prefill dal Keychain; svuotandoli si cancellano)
    @State private var dbPassword = ""
    @State private var sshPassword = ""
    @State private var sshPassphrase = ""
    @State private var bridgeToken = ""
    @State private var bridgeHMACSecret = ""

    private let profileID: UUID?

    init(profile: ConnectionProfile?, onSave: @escaping (ConnectionProfile) -> Void) {
        self.onSave = onSave
        self.profileID = profile?.id
        _name = State(initialValue: profile?.name ?? "")
        _host = State(initialValue: profile?.host ?? "")
        _port = State(initialValue: String(profile?.port ?? 3306))
        _username = State(initialValue: profile?.username ?? "")
        _defaultSchema = State(initialValue: profile?.defaultSchema ?? "")
        _useTLS = State(initialValue: profile?.useTLS ?? true)
        _allowSelfSignedTLS = State(initialValue: profile?.allowSelfSignedTLS ?? false)
        _mode = State(initialValue: profile?.mode ?? .direct)
        _sshHost = State(initialValue: profile?.sshHost ?? "")
        _sshPort = State(initialValue: String(profile?.sshPort ?? 22))
        _sshUsername = State(initialValue: profile?.sshUsername ?? "")
        _sshAuthType = State(initialValue: profile?.sshAuthType ?? .password)
        _sshKeyPath = State(initialValue: profile?.sshKeyPath ?? "")
        _sshUsePassphrase = State(initialValue: profile?.sshUsePassphrase ?? false)
        _bridgeURL = State(initialValue: profile?.bridgeURL ?? "")
        _bridgeUseHMAC = State(initialValue: profile?.bridgeUseHMAC ?? true)

        let id = profile?.id
        _dbPassword = State(initialValue: id.flatMap { SecretStore.load(profileID: $0, kind: .databasePassword) } ?? "")
        _sshPassword = State(initialValue: id.flatMap { SecretStore.load(profileID: $0, kind: .sshPassword) } ?? "")
        _sshPassphrase = State(initialValue: id.flatMap { SecretStore.load(profileID: $0, kind: .sshPassphrase) } ?? "")
        _bridgeToken = State(initialValue: id.flatMap { SecretStore.load(profileID: $0, kind: .bridgeToken) } ?? "")
        _bridgeHMACSecret = State(initialValue: id.flatMap { SecretStore.load(profileID: $0, kind: .bridgeHMACSecret) } ?? "")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            formBody
            Divider()
            footer
        }
        #if os(macOS)
        .frame(width: 560, height: 620)
        #endif
        .sheet(isPresented: $showKeyGenerator) {
            SSHKeyGeneratorView { url in
                sshKeyPath = url.path
                sshUsePassphrase = false
            }
        }
    }

    /// Su macOS la `Form` non scrolla da sola: serve un `ScrollView`.
    /// Su iOS la `Form` è già scrollabile: posta dentro un `ScrollView`
    /// i campi non vengono renderizzati, quindi va messa direttamente
    /// nella VStack.
    @ViewBuilder
    private var formBody: some View {
        #if os(macOS)
        ScrollView {
            formContent
        }
        #else
        formContent
        #endif
    }

    private var formContent: some View {
        Form {
            generalSection
            if mode == .ssh { sshSection }
            if mode == .bridge { bridgeSection }
            securitySection
        }
        .formStyle(.grouped)
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            // Layout compatto (macOS, schermo largo): titolo e picker in riga.
            HStack {
                Text(profileID == nil ? "Nuova connessione" : "Modifica connessione")
                    .font(.headline)
                Spacer()
                modePicker
                    .frame(maxWidth: 420)
            }
            // Fallback (iPhone): titolo sopra e segmented a tutta larghezza.
            VStack(alignment: .leading, spacing: 10) {
                Text(profileID == nil ? "Nuova connessione" : "Modifica connessione")
                    .font(.headline)
                modePicker
            }
        }
        .padding()
    }

    private var modePicker: some View {
        Picker("", selection: $mode) {
            ForEach(availableModes) { m in
                Label(m.shortDisplayName, systemImage: m.symbolName).tag(m)
            }
        }
        .pickerStyle(.segmented)
    }

    private var generalSection: some View {
        Section("Server MySQL / MariaDB") {
            TextField("Nome connessione", text: $name)
            TextField("Host", text: $host)
            HStack {
                TextField("Porta", text: $port)
                    .frame(width: 90)
                TextField("Utente", text: $username)
            }
            TextField("Schema predefinito (opzionale)", text: $defaultSchema)
            Toggle("Usa SSL/TLS", isOn: $useTLS)
            if useTLS {
                Toggle("Accetta certificato self-signed", isOn: $allowSelfSignedTLS)
            }
        }
    }

    private var sshSection: some View {
        Section("Tunnel SSH") {
            TextField("Host SSH", text: $sshHost)
            HStack {
                TextField("Porta SSH", text: $sshPort)
                    .frame(width: 90)
                TextField("Utente SSH", text: $sshUsername)
            }
            Picker("Autenticazione", selection: $sshAuthType) {
                ForEach(SSHAuthType.allCases) { auth in
                    Text(auth.displayName).tag(auth)
                }
            }
            .pickerStyle(.segmented)
            if sshAuthType == .privateKey {
                HStack {
                    TextField("Percorso chiave privata", text: $sshKeyPath)
                    Button("Sfoglia…") {
                        showKeyImporter = true
                    }
                }
                .fileImporter(
                    isPresented: $showKeyImporter,
                    allowedContentTypes: [.item],
                    allowsMultipleSelection: false
                ) { result in
                    if case .success(let urls) = result, let url = urls.first {
                        importKey(url: url)
                    }
                }
                Button("Genera chiave Ed25519…") { showKeyGenerator = true }
                Toggle("La chiave ha una passphrase", isOn: $sshUsePassphrase)
            }
        }
    }

    private var bridgeSection: some View {
        Section("Bridge HTTPS") {
            TextField("URL dello script (https://…/db_bridge.php)", text: $bridgeURL)
            Toggle("Verifica firma HMAC-SHA256", isOn: $bridgeUseHMAC)
        }
    }

    private var securitySection: some View {
        Section("Segreti (Keychain)") {
            SecureField("Password database", text: $dbPassword)
            if mode == .ssh && sshAuthType == .password {
                SecureField("Password SSH", text: $sshPassword)
            }
            if mode == .ssh && sshAuthType == .privateKey && sshUsePassphrase {
                SecureField("Passphrase chiave SSH", text: $sshPassphrase)
            }
            if mode == .bridge {
                SecureField("Token Bearer", text: $bridgeToken)
                if bridgeUseHMAC {
                    SecureField("Segreto HMAC", text: $bridgeHMACSecret)
                }
            }
            Text("I segreti vuoti al salvataggio vengono rimossi dal Keychain.")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Annulla") { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button("Salva") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || host.isEmpty)
        }
        .padding()
    }

    /// Importa una chiave privata selezionata con il fileImporter.
    /// Su macOS conserva il percorso originale; su iOS/iPadOS la copia nella
    /// sandbox dell'app (Application Support/SSHKeys) perché il percorso
    /// temporaneo del fileImporter non persiste tra i lanci.
    private func importKey(url: URL) {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }

        #if os(macOS)
        sshKeyPath = url.path
        #else
        do {
            let fm = FileManager.default
            let dir = try fm.url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
                .appendingPathComponent("SSHKeys", isDirectory: true)
            try fm.createDirectory(at: dir, withIntermediateDirectories: true)
            let dest = dir.appendingPathComponent("key_\(url.lastPathComponent)")
            if fm.fileExists(atPath: dest.path) {
                try fm.removeItem(at: dest)
            }
            try fm.copyItem(at: url, to: dest)
            sshKeyPath = dest.path
        } catch {
            sshKeyPath = url.path
        }
        #endif
    }

    private func save() {
        var profile = ConnectionProfile()
        if let profileID { profile.id = profileID }
        profile.name = name
        profile.host = host
        profile.port = Int(port) ?? 3306
        profile.username = username
        profile.defaultSchema = defaultSchema
        profile.useTLS = useTLS
        profile.allowSelfSignedTLS = allowSelfSignedTLS
        profile.mode = mode
        profile.sshHost = sshHost
        profile.sshPort = Int(sshPort) ?? 22
        profile.sshUsername = sshUsername
        profile.sshAuthType = sshAuthType
        profile.sshKeyPath = sshKeyPath
        profile.sshUsePassphrase = sshUsePassphrase
        profile.bridgeURL = bridgeURL
        profile.bridgeUseHMAC = bridgeUseHMAC

        // Persistenza segreti: non vuoti → salva; vuoti → rimuovi.
        persist(secret: dbPassword, kind: .databasePassword, for: profile)
        persist(secret: sshPassword, kind: .sshPassword, for: profile)
        persist(secret: sshPassphrase, kind: .sshPassphrase, for: profile)
        persist(secret: bridgeToken, kind: .bridgeToken, for: profile)
        persist(secret: bridgeHMACSecret, kind: .bridgeHMACSecret, for: profile)

        onSave(profile)
    }

    private func persist(secret: String, kind: SecretKind, for profile: ConnectionProfile) {
        if secret.isEmpty {
            SecretStore.delete(profileID: profile.id, kind: kind)
        } else {
            SecretStore.save(secret, profileID: profile.id, kind: kind)
        }
    }
}
