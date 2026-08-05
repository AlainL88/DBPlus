# HTTPS Bridge — `db_bridge.php`

Remote script for DB+ **"HTTPS Tunnel (Bridge)"** mode. It lets you manage a
MySQL/MariaDB database that is only reachable through a web server (e.g.
shared cPanel hosting), by running the queries **locally on the server** and
returning JSON to the app.

## Requirements

- PHP **8.1+** with the **PDO MySQL** extension (`pdo_mysql`);
- network access from the web server to MySQL (usually `127.0.0.1:3306`);
- **HTTPS** on the web server (required: the app rejects non-HTTPS URLs).

## Installation

1. Copy `db_bridge.php` to a public folder (e.g. `public_html/db_bridge.php`).
2. Edit the constants at the top of the file:

   ```php
   const BRIDGE_TOKEN       = '<random token>';          // e.g. bin2hex(random_bytes(32))
   const BRIDGE_HMAC_SECRET = '<random secret>';         // e.g. bin2hex(random_bytes(32))
   const DB_HOST = '127.0.0.1';
   const DB_PORT = 3306;
   const DB_NAME = '<database name>';                    // optional
   const DB_USER = '<mysql user>';
   const DB_PASS = '<mysql password>';
   ```

   > Generate the secrets with: `php -r "echo bin2hex(random_bytes(32)), PHP_EOL;"`
3. Check the syntax: `php -l db_bridge.php`
4. Protect the folder from directory listing and restrict access to the file.

## Configuration in DB+

1. Open **New connection**.
2. Mode → **HTTPS Tunnel (Bridge)**.
3. **Script URL**: `https://yourserver.com/db_bridge.php`
4. **Bearer token** and **HMAC secret** (same values as the script).
5. Set the database host/port/user (used by the bridge).

## Built-in security

- **Bearer token** authentication verified with `hash_equals`.
- **HMAC-SHA256** over `timestamp:body` with anti-replay window (±300 s).
- **Rate limiting** per IP (token bucket, 120 req/min by default).
- **Prepared statements** (`PDO::ATTR_EMULATE_PREPARES = false`).
- **Multi-statement blocked**; dangerous patterns blocked
  (`INTO OUTFILE`, `LOAD_FILE`, `INTO DUMPFILE`, `LOAD DATA`).
- Row limit per response (`MAX_ROWS`, default 5000) and body length cap.
- No credentials in logs or responses.

## Endpoint

| Action | Body | Response |
|---|---|---|
| `ping` | `{"action":"ping"}` | `{ok, serverVersion, ms}` |
| `execute` | `{"action":"execute","sql":"…","params":[…],"rowLimit":N}` | `{ok, columns, rows, affectedRows, lastInsertID, ms, truncated}` |

## Troubleshooting

- **401** → invalid token or signature (check server clock and
  `BRIDGE_HMAC_SECRET`).
- **429** → rate limit reached.
- **503** → wrong database credentials or MySQL unreachable.
- **404** → unrecognized action (script not up to date).
