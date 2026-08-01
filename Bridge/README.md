# Bridge HTTPS — `db_bridge.php`

Script remoto per la modalità **"Tunnel HTTPS (Bridge)"** di DB+.
Consente di gestire un database MySQL/MariaDB raggiungibile solo
attraverso un server web (es. hosting condiviso cPanel), eseguendo
le query **in locale sul server** e restituendo JSON all'app.

## Requisiti

- PHP **8.1+** con estensione **PDO MySQL** (`pdo_mysql`);
- accesso di rete dal server web al MySQL (di solito `127.0.0.1:3306`);
- **HTTPS** sul server web (obbligatorio: l'app rifiuta URL non HTTPS).

## Installazione

1. Copia `db_bridge.php` in una cartella pubblica
   (es. `public_html/db_bridge.php`).
2. Modifica le costanti in cima al file:

   ```php
   const BRIDGE_TOKEN       = '<token casuale>';        // es. bin2hex(random_bytes(32))
   const BRIDGE_HMAC_SECRET = '<segreto casuale>';      // es. bin2hex(random_bytes(32))
   const DB_HOST = '127.0.0.1';
   const DB_PORT = 3306;
   const DB_NAME = '<nome database>';                    // opzionale
   const DB_USER = '<utente mysql>';
   const DB_PASS = '<password mysql>';
   ```

   > Genera i segreti con: `php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"`
3. Verifica la sintassi: `php -l db_bridge.php`
4. Proteggi la cartella dai listati e limita l'accesso al file.

## Configurazione in DB+

1. Apri **Nuova connessione**.
2. Modalità → **Tunnel HTTPS (Bridge)**.
3. **URL dello script**: `https://tuoserver.it/db_bridge.php`
4. **Token Bearer** e **Segreto HMAC** (stessi valori dello script).
5. Imposta host/porta/utente del database (usati dal bridge).

## Sicurezza integrata

- Autenticazione **Bearer token** verificata con `hash_equals`.
- **HMAC-SHA256** su `timestamp:body` con finestra anti-replay (±300 s).
- **Rate limiting** per IP (token bucket, 120 req/min di default).
- **Prepared statement** (`PDO::ATTR_EMULATE_PREPARES = false`).
- **Multi-statement bloccato**; pattern pericolosi bloccati
  (`INTO OUTFILE`, `LOAD_FILE`, `INTO DUMPFILE`, `LOAD DATA`).
- Limite righe per risposta (`MAX_ROWS`, default 5000) e lunghezza body.
- Nessuna credenziale nei log o nelle risposte.

## Endpoint

| Azione | Body | Risposta |
|---|---|---|
| `ping` | `{"action":"ping"}` | `{ok, serverVersion, ms}` |
| `execute` | `{"action":"execute","sql":"…","params":[…],"rowLimit":N}` | `{ok, columns, rows, affectedRows, lastInsertID, ms, truncated}` |

## Troubleshooting

- **401** → token o firma non validi (controlla orologio del server e
  `BRIDGE_HMAC_SECRET`).
- **429** → rate limit raggiunto.
- **503** → credenziali database errate o MySQL non raggiungibile.
- **404** → azione non riconosciuta (script non aggiornato).
