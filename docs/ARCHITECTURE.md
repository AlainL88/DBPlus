# DB+ — Architecture and Stack Selection

**Version:** 1.3 — **Date:** 2026-08-05
**Target platforms:** macOS (26.5) + iOS/iPadOS (26.5) — SwiftUI, shared codebase

## 1. Summary

DB+ is a native MySQL/MariaDB client for macOS, iPhone and iPad, with three
connection modes (direct, SSH tunnel, HTTPS tunnel via bridge script), a schema
inspector, a data grid with CRUD editing, a multi-statement SQL console, and
export-compliance for cryptographic software.

The architecture is **transport-agnostic**: a single `DatabaseTransport`
protocol isolates all app logic (inspector, data grid, query runner) from the
three network implementations.

```
┌─────────────────────────────── UI (SwiftUI) ───────────────────────────────┐
│  ConnectionList │ SchemaNavigator │ DataGrid │ QueryConsole │ Settings     │
└───────────────────────────────┬────────────────────────────────────────────┘
                                ▼
                    ┌────────── Services ──────────┐
                    │ SchemaInspector │ DataGrid │ QueryRunner                │
                    │     Service     │ Service  │  Service                   │
                    └───────────────┬────────────┘
                                    ▼
                           protocol DatabaseTransport
             ┌──────────────────────┬────────────────────────┐
             ▼                      ▼                        ▼
    DirectTransport          SSHTransport            BridgeTransport
    (MySQLNIO, TLS)     (SSH tunnel + MySQLNIO)      (URLSession + HMAC)
             │                      │                        │
         MySQL/MariaDB          SSH gateway             HTTPS → db_bridge.php
```

## 2. Library selection (PHASE 1)

| Need | Options evaluated | Choice | Rationale |
|---|---|---|---|
| MySQL client | MySQLNIO · Fluent/MySQLKit · libmysqlclient C · legacy clients | **MySQLNIO** | Pure Swift, async/await, server-side prepared statements, row streaming (low memory footprint), built-in TLS, actively maintained (Vapor). An ORM is not suited to a tool that runs arbitrary SQL. |
| SSH tunnel (macOS) | SwiftSH (libssh2) · libssh2 C · **system OpenSSH** | **OpenSSH** via `Process` | SwiftSH does not implement port forwarding and bundles prebuilt OpenSSL/libssh2 binaries (supply-chain risk). Apple's OpenSSH: zero dependencies, native Ed25519/RSA, robust keep-alive, password/key+passphrase via `SSH_ASKPASS` (temporary `0600` helper, removed immediately). |
| SSH tunnel (iOS) | SwiftSH · libssh2/OpenSSL XCFramework · **Citadel** | **Citadel** (SwiftNIO + swift-crypto) | iOS has no `/usr/bin/ssh` and the sandbox forbids child processes: an **in-process** SSH client is required. Citadel (MIT, SPM, no prebuilt binaries) supports password, RSA, Ed25519, passphrase and **direct-tcpip** channels on the same SwiftNIO stack MySQLNIO uses. Requires iOS 17+/macOS 14+. |
| HTTPS bridge | URLSession + ATS | **URLSession** | Native, HTTPS/TLS, streaming, latency measurement. |
| Credentials | Keychain · encrypted file · UserDefaults | **Keychain** (`kSecClassGenericPassword`) | System-native encryption, secrets never stored in clear on disk. |
| UI state | @ObservableObject · @Observable | **@Observable** (Observation) | Modern syntax, consistent with macOS 26. |
| SQL editor | HighlightedTextEditor · custom | **Custom NSTextView** + regex tokenizer | No extra dependency, controlled highlighting. |
| Cryptography | CryptoKit | **HMAC-SHA256 (CryptoKit)** | Native API for bridge signing. |

The only direct SPM dependency is **MySQLNIO** (+ SwiftNIO, imported
transitively via `@_exported import NIO`); Citadel and firebase-ios-sdk
(Crashlytics) are also resolved through Swift Package Manager.

### 2.1 Why MySQLNIO
- `query(_:_:onRow:)` runs **prepared statements** with typed parameters
  (`MySQLData`) → systematic defense against SQL injection.
- `onRow` enables **streaming**: large datasets are never loaded entirely
  into RAM.
- `tlsConfiguration` exposes full control over TLS (including self-signed
  for testing).

### 2.2 Why system OpenSSH
- A macOS app can launch `/usr/bin/ssh` without bundling C libraries.
- Full, up-to-date support for **Ed25519/RSA** and passphrases.
- `ServerAliveInterval=15` + `ExitOnForwardFailure` for resilience.
- Transient secrets live in a temporary `DBplus-<uuid>` directory
  (`chmod 600/700`) removed at teardown: **no secrets persisted**.

## 3. Connection architecture (PHASE 2)

### 3.1 Direct connection
`DirectTransport` → `MySQLConnection.connect(to:username:database:
password:tlsConfiguration:on:)`. TLS enabled by default; the user can accept
self-signed certificates (config `allowSelfSignedTLS`).

### 3.2 SSH tunnel
`SSHTransport`:
1. opens the tunnel with `SSHProcessTunnel` (random local port, password or
   key `-i` auth, askpass for secrets);
2. waits until the local port accepts connections (socket poll);
3. delegates to a `DirectTransport` towards `127.0.0.1:localPort`.

Teardown releases process and temporary files (SIGTERM → SIGKILL).

> **Cross-platform:** on macOS the tunnel uses the system OpenSSH
> (`/usr/bin/ssh`, `SSHProcessTunnel`). On iOS/iPadOS — where `/usr/bin/ssh`
> does not exist and the sandbox forbids child processes — an **in-process**
> SSH client is used (`SSHInProcessTunnel`, library **Citadel**): it opens a
> TCP listener on `127.0.0.1` and routes every connection over a SSH
> **direct-tcpip** channel to the MySQL server. Both implementations share
> the `SSHTunnel` contract and support password or RSA/Ed25519 key (also
> passphrase-protected, `openssh-key-v1` format). On iOS, reads from the
> local channel are suspended until the SSH channel is ready, so the first
> byte of the MySQL handshake is never lost.

### 3.3 HTTPS tunnel (bridge)
`BridgeTransport` sends JSON requests to `db_bridge.php`:
- **Bearer token** authentication (`X-DBPlus-Token`);
- **HMAC-SHA256** signature over `timestamp:body` (`X-DBPlus-Signature`,
  `X-DBPlus-Timestamp`) with anti-replay tolerance window;
- the server applies **rate limiting** per IP, **prepared statements**, blocks
  multi-statement and dangerous patterns, and caps returned rows.

### 3.4 Bridge script `db_bridge.php`
PHP 8.1+, `pdo_mysql`, zero dependencies. Protocol:
- `POST {action:"ping"}` → server version + latency.
- `POST {action:"execute", sql, params?, rowLimit}` → results.

## 4. Core features (PHASE 3)

- **Connection management:** profiles stored in UserDefaults (metadata only),
  secrets in the Keychain, connection cards with "Test connection" (latency and
  version), per-profile keep-alive.
- **Inspector:** schema tree → tables/views/routines; structure via
  `information_schema` (columns, indexes, FKs, collation, `SHOW CREATE`).
- **Data Grid:** `LIMIT/OFFSET` pagination (configurable rows per page, or
  unlimited), sorting, SQL filter, inline editing, transparent
  `INSERT/UPDATE/DELETE` generation based on the primary key (prepared
  statements), type-aware cell editor (date/numeric/text, NULL toggle).
- **Query console:** highlighted editor, multi-statement execution (splitter
  respecting strings/comments/backticks), schema-aware autocomplete, results
  with time in ms and rows returned/modified.
- **CSV export** for query results and tables.
- **Biometric lock** (Face ID / Touch ID) on saved connection profiles.

## 5. Security (PHASE 4)

- **Destructive-operation guard:** confirmation for `DROP`, `TRUNCATE`,
  `DELETE`/`UPDATE` without `WHERE`, `ALTER`, `RENAME`.
- **Prepared statements** for every generated write.
- **Keychain** for passwords/passphrases/tokens; temporary askpass helper.
- **Bridge:** token + HMAC + rate limit + sanitization.

## 6. iOS / iPadOS adaptation

Code is shared across platforms via `#if os(macOS)` guards:

| Component | macOS | iOS/iPadOS |
|---|---|---|
| MySQL client (MySQLNIO) | ✅ | ✅ |
| HTTPS bridge | ✅ | ✅ |
| Keychain (`SecretStore`) | ✅ | ✅ |
| Data grid / CRUD | ✅ | ✅ |
| SSH tunnel | ✅ system OpenSSH | ✅ in-process client (Citadel) |
| SQL editor | `NSTextView` + syntax highlighting | `TextEditor` (SwiftUI) + autocomplete chip bar |
| Autocomplete | native NSTextView completions | suggestion chips |
| Colors | `Color(nsColor:)` | `Color(uiColor:)` (helper `PlatformColor`) |
| File picker | `NSOpenPanel` | `.fileImporter` (SwiftUI) |

## 7. Module structure

```
DB+/
  DB+/Models/          ConnectionProfile, CellValue, QueryTypes, SchemaModels
  DB+/Core/            DatabaseTransport, DirectTransport, SSHTransport,
                       SSHTunnel, SSHProcessTunnel, SSHInProcessTunnel,
                       BridgeTransport, SQLSplitter, SQLGuard, SQLHighlighter,
                       DebugLog, Timeout, DBError
  DB+/Security/        SecretStore (Keychain)
  DB+/Services/        ConnectionStore, ConnectionSession, SchemaInspector,
                       DataGridService, QueryRunner, CSVExporter,
                       SSHKeyGenerator, AppSettings
  DB+/UI/              MainWindow, Connection*, SchemaNavigator, TableDetail,
                       DataGrid, RowEditor, QueryConsole, QueryResult,
                       SQLTextEditor, CellEditorPanel, Settings
  Bridge/              db_bridge.php + deploy README
  docs/                ARCHITECTURE, EXPORT_COMPLIANCE
```

## SSH key generation

The app generates Ed25519 key pairs in-app (swift-crypto generates, Citadel
serializes to the OpenSSH `openssh-key-v1` format). The private key is NOT
encrypted and lives in `Documents/SSHKeys/` — reachable on iOS via file
sharing (`UIFileSharingEnabled`), and on macOS under `~/Documents/SSHKeys`.
The public key must be installed in the server's `authorized_keys` file.
