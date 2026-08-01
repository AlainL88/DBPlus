# DB+ — Architettura e Selezione dello Stack

**Versione:** 1.0 — **Data:** 2026-08-01
**Piattaforma target:** macOS (SwiftUI), deployment target macOS 26.5

## 1. Sintesi

DB+ è un gestore MySQL/MariaDB nativo per macOS con tre modalità di
connessione (diretta, tunnel SSH, tunnel HTTPS via script bridge),
inspector della struttura, data grid con editing CRUD, console SQL
multi-statement, modulo di benchmarking e conformità all'export di
software crittografico.

L'architettura è **transport-agnostica**: un unico protocollo
`DatabaseTransport` isola tutta la logica applicativa (inspector, data
grid, query runner, benchmark) dalle tre implementazioni di rete.

```
┌─────────────────────────────── UI (SwiftUI) ───────────────────────────────┐
│  ConnectionList │ SchemaNavigator │ DataGrid │ QueryConsole │ Benchmark    │
└───────────────────────────────┬────────────────────────────────────────────┘
                                ▼
                   ┌───────── Services ─────────┐
                   │ SchemaInspector │ DataGrid │ QueryRunner │ Benchmark   │
                   │     Service     │ Service  │             │ Service     │
                   └───────────────┬────────────┘
                                   ▼
                          protocol DatabaseTransport
            ┌──────────────────────┬────────────────────────┐
            ▼                      ▼                        ▼
   DirectTransport          SSHTransport            BridgeTransport
   (MySQLNIO, TLS)     (Process ssh -L + MySQLNIO)  (URLSession + HMAC)
            │                      │                        │
        MySQL/MariaDB          SSH gateway             HTTPS → db_bridge.php
```

## 2. Selezione delle librerie (FASE 1)

| Esigenza | Opzioni valutate | Scelta | Motivazione |
|---|---|---|---|
| Client MySQL | MySQLNIO · Fluent/MySQLKit · libmysqlclient C · client obsoleti | **MySQLNIO** | Pure Swift, async/await, prepared statements server-side, streaming delle righe (impronta di memoria), TLS integrato, manutenzione attiva (Vapor). Un ORM non è adatto a un tool che esegue SQL arbitrario. |
| Tunnel SSH | SwiftSH (libssh2) · libssh2 C · **OpenSSH di sistema** | **OpenSSH** via `Process` | SwiftSH non implementa il port forwarding e imbarca binari OpenSSL/libssh2 precompilati (rischio supply-chain). OpenSSH di Apple: zero dipendenze, Ed25519/RSA nativi, keep-alive robusto, password/chiave+passphrase via `SSH_ASKPASS` (helper temporaneo `0600`, rimosso subito). |
| Bridge HTTPS | URLSession + ATS | **URLSession** | Nativo, HTTPS/TLS, streaming, misura della latenza. |
| Credenziali | Keychain · file cifrato · UserDefaults | **Keychain** (`kSecClassGenericPassword`) | Cifratura nativa del sistema, segreti mai su disco in chiaro. |
| Stato UI | @ObservableObject · @Observable | **@Observable** (Observation) | Sintassi moderna, coerente con macOS 26. |
| Editor SQL | HighlightedTextEditor · custom | **NSTextView custom** + tokenizer regex | Nessuna dipendenza extra, evidenziazione controllata. |
| Crittografia | CryptoKit | **HMAC-SHA256 (CryptoKit)** | API nativa per la firma del bridge. |

Dipendenza SPM unica: **MySQLNIO** (+ SwiftNIO, importato transitivamente
via `@_exported import NIO`).

### 2.1 Perché MySQLNIO
- `query(_:_:onRow:)` esegue **prepared statement** con parametri tipizzati
  (`MySQLData`) → difesa sistematica da SQL injection.
- `onRow` consente lo **streaming**: i dataset grandi non vengono mai
  caricati interamente in RAM (vedi Benchmarking).
- `tlsConfiguration` espone il controllo completo su TLS (incluso il caso
  self-signed per test).

### 2.2 Perché OpenSSH di sistema
- Un'app macOS può lanciare `/usr/bin/ssh` senza bundlare librerie C.
- Supporto completo e aggiornato di **Ed25519/RSA** e passphrase.
- `ServerAliveInterval=15` + `ExitOnForwardFailure` per la resilienza.
- I segreti transitori vivono in una directory temporanea `DBplus-<uuid>`
  (`chmod 600/700`) eliminata al teardown: **nessun segreto persistito**.

## 3. Architettura delle connessioni (FASE 2)

### 3.1 Connessione Diretta
`DirectTransport` → `MySQLConnection.connect(to:username:database:
password:tlsConfiguration:on:)`. TLS abilitato di default; l'utente può
accettare certificati self-signed (config `allowSelfSignedTLS`).

### 3.2 Tunnel SSH
`SSHTransport`:
1. apre il tunnel con `SSHProcessTunnel` (porta locale casuale,
   autenticazione password o chiave `-i`, askpass per segreti);
2. attende che la porta locale accetti connessioni (poll su socket);
3. delega a un `DirectTransport` verso `127.0.0.1:portaLocale`.

Il teardown rilascia processo e file temporanei (SIGTERM → SIGKILL).

### 3.3 Tunnel HTTPS (Bridge)
`BridgeTransport` invia richieste JSON a `db_bridge.php`:
- autenticazione **Bearer token** (`X-DBPlus-Token`);
- firma **HMAC-SHA256** su `timestamp:body` (`X-DBPlus-Signature`,
  `X-DBPlus-Timestamp`) con finestra di tolleranza anti-replay;
- il server applica **rate limiting** per IP, **prepared statement**,
  blocco dei multi-statement e pattern pericolosi, cap delle righe.

### 3.4 Script bridge `db_bridge.php`
PHP 8.1+, `pdo_mysql`, zero dipendenze. Protocollo:
- `POST {action:"ping"}` → versione server + latenza.
- `POST {action:"execute", sql, params?, rowLimit}` → risultati.

## 4. Funzionalità core (FASE 3)

- **Gestione connessioni:** profili in UserDefaults (solo metadati),
  segreti nel Keychain, "Test connessione" con latenza e versione.
- **Inspector:** albero schemi → tabelle/viste/routine; struttura via
  `information_schema` (colonne, indici, FK, collation, `SHOW CREATE`).
- **Data Grid:** paginazione `LIMIT/OFFSET`, ordinamento, filtro SQL,
  editing inline, generazione trasparente di `INSERT/UPDATE/DELETE`
  basata sulla chiave primaria (prepared statement).
- **Workbench:** editor evidenziato, esecuzione multi-statement
  (splitter rispettoso di stringhe/commenti/backtick), risultati con
  tempo in ms e righe restituite/modificate.

## 5. Benchmarking (FASE 4)

Modulo in-app che misura: latenza handshake/ping, throughput su dataset
sintetici (1k/10k/50k), impronta di memoria via `task_info` durante lo
streaming, resilienza (10 ping, keep-alive, teardown). Dettagli in
[`BENCHMARKING.md`](BENCHMARKING.md).

## 6. Sicurezza (FASE 5)

- **Guardia operazioni distruttive:** conferma per `DROP`, `TRUNCATE`,
  `DELETE`/`UPDATE` senza `WHERE`, `ALTER`, `RENAME`.
- **Prepared statements** per ogni scrittura generata.
- **Keychain** per password/passphrase/token; helper askpass temporaneo.
- **Bridge:** token + HMAC + rate limit + sanificazione.

## 7. Struttura dei moduli

```
DB+/
  DB+/Models/          ConnectionProfile, CellValue, QueryTypes, SchemaModels
  DB+/Core/            DatabaseTransport, DirectTransport, SSHTransport,
                       SSHProcessTunnel, BridgeTransport, SQLSplitter,
                       SQLGuard, SQLHighlighter, DBError
  DB+/Security/        SecretStore (Keychain)
  DB+/Services/        ConnectionStore, ConnectionSession, SchemaInspector,
                       DataGridService, QueryRunner, BenchmarkService
  DB+/UI/              MainWindow, Connection* , SchemaNavigator, TableDetail,
                       DataGrid, RowEditor, QueryConsole, QueryResult,
                       SQLTextEditor, Benchmark
  Bridge/              db_bridge.php + README di deploy
  docs/                ARCHITECTURE, EXPORT_COMPLIANCE, BENCHMARKING
```
