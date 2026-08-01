<?php
/**
 * db_bridge.php — Bridge HTTPS per DB+ (gestore MySQL/MariaDB).
 *
 * Da posizionare su un server web con PHP 8.1+ e l'estensione pdo_mysql,
 * idealmente dietro HTTPS/TLS. Tutte le richieste sono autenticate con:
 *   - Bearer token (header: X-DBPlus-Token)
 *   - firma HMAC-SHA256 su "timestamp:body" (header: X-DBPlus-Signature /
 *     X-DBPlus-Timestamp) se BRIDGE_HMAC_SECRET è configurato
 *
 * Sicurezza implementata:
 *   - prepared statements (PDO::ATTR_EMULATE_PREPARES = false)
 *   - rate limiting per IP (token bucket su file, senza dipendenze)
 *   - controllo finestra temporale anti-replay
 *   - singola istruzione per richiesta (niente multi-statement)
 *   - blocco di pattern pericolosi (INTO OUTFILE / LOAD_FILE / ...)
 *   - limite massimo di righe e dimensione del body
 *   - nessuna credenziale nel log o nella risposta
 *
 * ─────────────────────────────────────────────────────────────────────
 *  CONFIGURAZIONE RAPIDA
 *  1. Copia questo file sul server web (es. /var/www/html/db_bridge.php).
 *  2. Edita le costanti qui sotto (genera i segreti con:
 *     php -r "echo bin2hex(random_bytes(32)), PHP_EOL;")
 *  3. Verifica:  php -l db_bridge.php
 *  4. Nell'app DB+ crea una connessione "Tunnel HTTPS (Bridge)" con
 *     l'URL dello script, il token e il segreto HMAC.
 * ─────────────────────────────────────────────────────────────────────
 */

declare(strict_types=1);

error_reporting(E_ALL);
ini_set('display_errors', '0');
ini_set('log_errors', '1');

header('Content-Type: application/json; charset=utf-8');
header('Cache-Control: no-store, no-cache, must-revalidate');
header('X-Content-Type-Options: nosniff');

/* ═══════════════════════ CONFIGURAZIONE ═══════════════════════ */

const BRIDGE_TOKEN       = 'CHANGE_ME_genera_un_token_lungo'; // token Bearer
const BRIDGE_HMAC_SECRET = 'CHANGE_ME_genera_un_segreto_hmac'; // se vuoto: solo token
const TIME_WINDOW_TOLERANCE = 300;                             // secondi (anti-replay)

const DB_HOST    = '127.0.0.1';
const DB_PORT    = 3306;
const DB_NAME    = '';      // schema predefinito (opzionale)
const DB_USER    = 'dbuser';
const DB_PASS    = 'dbpass';
const DB_CHARSET = 'utf8mb4';

const MAX_QUERY_SECONDS  = 30;       // timeout esecuzione query
const MAX_ROWS           = 5000;     // cap righe restituite per richiesta
const MAX_SQL_LENGTH     = 1_000_000;
const MAX_BODY_LENGTH    = 2_000_000;
const RATE_LIMIT_PER_MIN = 120;      // richieste al minuto per IP
const ALLOW_DANGEROUS    = false;    // true = consenti INTO OUTFILE / LOAD_FILE ...

/* ═════════════════════════ HELPERS ═════════════════════════ */

function json_out(array $payload, int $code = 200): void {
    http_response_code($code);
    echo json_encode($payload, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
    exit;
}

function fail(string $message, int $code = 400): void {
    json_out(['ok' => false, 'error' => $message], $code);
}

function client_ip(): string {
    if (!empty($_SERVER['REMOTE_ADDR'])) return $_SERVER['REMOTE_ADDR'];
    return 'unknown';
}

function hmac_valid(string $secret, string $timestamp, string $body, string $signature): bool {
    if ($secret === '' || $signature === '') return false;
    if (!is_numeric($timestamp)) return false;
    if (abs(time() - (int)$timestamp) > TIME_WINDOW_TOLERANCE) return false;
    $expected = hash_hmac('sha256', $timestamp . ':' . $body, $secret);
    return hash_equals($expected, $signature);
}

function rate_limited(): bool {
    $file = sys_get_temp_dir() . '/dbplus_rl_' . md5(client_ip());
    $now  = time();
    $data = @file_get_contents($file);
    $entry = $data ? json_decode($data, true) : null;
    if (!is_array($entry) || ($now - ($entry['start'] ?? 0)) >= 60) {
        $entry = ['start' => $now, 'count' => 0];
    }
    $entry['count']++;
    @file_put_contents($file, json_encode($entry), LOCK_EX);
    return $entry['count'] > RATE_LIMIT_PER_MIN;
}

/** Restituisce true se il testo contiene un punto e virgola a livello top-level. */
function has_top_level_semicolon(string $sql): bool {
    $len = strlen($sql);
    $inSingle = $inDouble = $inBacktick = $inLineComment = $inBlockComment = false;
    for ($i = 0; $i < $len; $i++) {
        $c = $sql[$i];
        $n = $i + 1 < $len ? $sql[$i + 1] : '';
        if ($inLineComment) {
            if ($c === "\n") $inLineComment = false;
        } elseif ($inBlockComment) {
            if ($c === '*' && $n === '/') { $inBlockComment = false; $i++; }
        } elseif ($inSingle) {
            if ($c === '\\') { $i++; }
            elseif ($c === "'") { if ($n === "'") { $i++; } else { $inSingle = false; } }
        } elseif ($inDouble) {
            if ($c === '\\') { $i++; }
            elseif ($c === '"') { if ($n === '"') { $i++; } else { $inDouble = false; } }
        } elseif ($inBacktick) {
            if ($c === '`') { if ($n === '`') { $i++; } else { $inBacktick = false; } }
        } else {
            if ($c === "'")       $inSingle = true;
            elseif ($c === '"')   $inDouble = true;
            elseif ($c === '`')   $inBacktick = true;
            elseif ($c === '-' && $n === '-') $inLineComment = true;
            elseif ($c === '#')   $inLineComment = true;
            elseif ($c === '/' && $n === '*') { $inBlockComment = true; $i++; }
            elseif ($c === ';')   return true;
        }
    }
    return false;
}

function contains_dangerous_pattern(string $sql): bool {
    $u = strtoupper(preg_replace('/\s+/', ' ', $sql));
    $patterns = [
        'INTO OUTFILE', 'INTO DUMPFILE', 'INTO INFILE',
        'LOAD_FILE(', 'LOAD DATA', 'SELECT ... INTO',
    ];
    foreach ($patterns as $p) {
        if (strpos($u, $p) !== false) return true;
    }
    return false;
}

/* ═════════════════════ AUTH & RATE LIMIT ═════════════════════ */

$rawBody = file_get_contents('php://input');
if ($rawBody === false || strlen($rawBody) > MAX_BODY_LENGTH) {
    fail('Body non valido o troppo grande.', 413);
}

$token = $_SERVER['HTTP_X_DBPLUS_TOKEN'] ?? '';
if ($token === '' || !hash_equals(BRIDGE_TOKEN, $token)) {
    json_out(['ok' => false, 'error' => 'Autenticazione non valida.'], 401);
}

if (BRIDGE_HMAC_SECRET !== '') {
    $signature  = $_SERVER['HTTP_X_DBPLUS_SIGNATURE'] ?? '';
    $timestamp  = $_SERVER['HTTP_X_DBPLUS_TIMESTAMP'] ?? '';
    if (!hmac_valid(BRIDGE_HMAC_SECRET, $timestamp, $rawBody, $signature)) {
        json_out(['ok' => false, 'error' => 'Firma HMAC non valida o scaduta.'], 401);
    }
}

if (rate_limited()) {
    json_out(['ok' => false, 'error' => 'Troppe richieste. Riprova più tardi.'], 429);
}

/* ═════════════════════ DECODIFICA BODY ═════════════════════ */

$request = json_decode($rawBody, true);
if (!is_array($request)) {
    fail('JSON non valido.');
}
$action = strtolower((string)($request['action'] ?? ''));

/* ═════════════════════ DATABASE ═════════════════════ */

try {
    $dsn = sprintf(
        'mysql:host=%s;port=%d;dbname=%s;charset=%s',
        DB_HOST, DB_PORT, DB_NAME, DB_CHARSET
    );
    $pdo = new PDO($dsn, DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE            => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_NUM,
        PDO::ATTR_EMULATE_PREPARES   => false,
        PDO::ATTR_TIMEOUT            => MAX_QUERY_SECONDS,
    ]);
} catch (Throwable $e) {
    error_log('[db_bridge] DB connection error: ' . $e->getMessage());
    json_out(['ok' => false, 'error' => 'Impossibile connettersi al database.'], 503);
}

$serverVersion = (string)$pdo->query('SELECT VERSION()')->fetchColumn();

/* ══════════════════════ AZIONI ══════════════════════ */

if ($action === 'ping') {
    json_out([
        'ok'            => true,
        'serverVersion' => $serverVersion,
        'ms'            => round((microtime(true) - $_SERVER['REQUEST_TIME_FLOAT']) * 1000, 2),
    ]);
}

if ($action === 'execute') {
    $sql = $request['sql'] ?? '';
    if (!is_string($sql) || trim($sql) === '') {
        fail('Campo sql mancante.');
    }
    if (strlen($sql) > MAX_SQL_LENGTH) {
        fail('Query troppo lunga.');
    }
    if (has_top_level_semicolon(trim($sql, " \t\n\r\0\x0B;"))) {
        fail('Multi-statement non consentito.');
    }
    if (!ALLOW_DANGEROUS && contains_dangerous_pattern($sql)) {
        fail('Pattern SQL non consentito dal bridge.');
    }

    $params = $request['params'] ?? [];
    if (!is_array($params)) $params = [];

    $rowLimit = isset($request['rowLimit']) ? max(1, (int)$request['rowLimit']) : MAX_ROWS;
    $rowLimit = min($rowLimit, MAX_ROWS);

    $start = microtime(true);
    try {
        $pdo->exec('SET SESSION time_zone = @@global.time_zone');

        if (count($params) > 0) {
            $stmt = $pdo->prepare($sql);
            $stmt->execute($params);
        } else {
            $stmt = $pdo->query($sql);
        }

        $isSelect = $stmt->columnCount() > 0;
        $truncated = false;

        if ($isSelect) {
            $columns = [];
            for ($i = 0; $i < $stmt->columnCount(); $i++) {
                $meta = $stmt->getColumnMeta($i);
                $columns[] = [
                    'name'    => (string)($meta['name'] ?? "col$i"),
                    'type'    => (string)($meta['native_type'] ?? 'string'),
                    'unsigned' => strpos((string)($meta['flags'] ?? ''), 'unsigned') !== false,
                ];
            }
            $rows = [];
            while (($row = $stmt->fetch(PDO::FETCH_NUM)) !== false) {
                $rows[] = array_map(
                    fn($v) => $v === null ? null : (is_resource($v) ? bin2hex(stream_get_contents($v)) : (string)$v),
                    $row
                );
                if (count($rows) >= $rowLimit) {
                    $truncated = true;
                    break;
                }
            }
            json_out([
                'ok'            => true,
                'columns'       => $columns,
                'rows'          => $rows,
                'affectedRows'  => 0,
                'lastInsertID'  => null,
                'ms'            => round((microtime(true) - $start) * 1000, 2),
                'truncated'     => $truncated,
                'serverVersion' => $serverVersion,
            ]);
        } else {
            $affected = $stmt->rowCount();
            $lastID   = $pdo->lastInsertId() ?: null;
            json_out([
                'ok'            => true,
                'columns'       => null,
                'rows'          => null,
                'affectedRows'  => $affected,
                'lastInsertID'  => $lastID !== null ? (string)$lastID : null,
                'ms'            => round((microtime(true) - $start) * 1000, 2),
                'truncated'     => false,
                'serverVersion' => $serverVersion,
            ]);
        }
    } catch (Throwable $e) {
        error_log('[db_bridge] execute error: ' . $e->getMessage());
        json_out(['ok' => false, 'error' => $e->getMessage()], 400);
    }
}

fail('Azione non riconosciuta.', 404);
