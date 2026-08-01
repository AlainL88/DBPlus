# DB+ — Benchmarking: metriche e report

**Versione:** 1.0 — **Data:** 2026-08-01

## 1. Obiettivo

Misurare e confrontare le prestazioni delle tre modalità di
connessione (Diretta / SSH / HTTPS Bridge) e profilare l'impatto
sulla memoria dell'app.

## 2. Metriche implementate (`BenchmarkService`)

| Categoria | Metrica | Come viene misurata |
|---|---|---|
| Latenza | Ping (round-trip) | `pingLatency()` → tempo di `SELECT 1` |
| Latenza | Handshake + connessione | Tempo del `connect()` del trasporto |
| Dataset N | Inserimento N record | INSERT in batch da 100 righe, tempo totale + rec/s |
| Dataset N | SELECT * con parsing | Esecuzione + costruzione celle/colonne |
| Dataset N | Streaming righe | `stream()` riga per riga + **footprint** prima/dopo |
| Dataset N | Query aggregata | COUNT / AVG / MAX |
| Resilienza | 10 ping consecutivi | media e massimo |
| Resilienza | Riconnessione / teardown | verifica chiusura socket/SSH |

**Footprint:** `task_info(TASK_VM_INFO)` → `phys_footprint`; il Δ tra
prima e dopo lo streaming stima la memoria richiesta dal risultato.

## 3. Protocollo di test

Il benchmark crea la tabella temporanea **`__dbplus_bench`** nello
schema scelto, la popola con i dataset richiesti (1.000 / 10.000 /
50.000 righe), esegue le metriche e **rimuove** la tabella al termine.
Richiede i permessi `CREATE`/`DROP`/`INSERT`/`DELETE`/`SELECT` sullo
schema di test (si consiglia uno schema dedicato).

## 4. Confronto dei tre trasporti

Per confrontare le modalità:
1. creare tre connessioni allo stesso server (stesso host/utente);
2. eseguire il benchmark su ciascuna (stesso schema);
3. confrontare le righe "Latenza / Handshake" e le metriche del dataset.

Attese:
- **Diretta**: latenza minima; streaming con footprint contenuto.
- **SSH**: + handshake SSH; throughput leggermente inferiore.
- **Bridge**: + round-trip HTTP/HMAC/rate-limit; footprint dipendente
  dalla dimensione del payload JSON (limitato da `MAX_ROWS`).

## 5. Suggerimenti per la lettura

- La **latenza handshake** misura l'esperienza di apertura: domina la
  modalità di connessione (soprattutto SSH/HTTPS).
- Il **throughput** (rec/s) è la metrica di produttività sulle query.
- Il **Δ footprint** evidenzia l'efficacia dello streaming: valori
  bassi indicano che l'app non carica l'intero dataset in RAM.
- I **ping consecutivi** intercettano degradazioni/keep-alive: con SSH
  `ServerAliveInterval=15` mantiene il tunnel; con il bridge il timeout
  di URLSession governa la riconnessione.

## 6. Esportazione

La vista Benchmark esporta un report in testo semplice
(`DBplus_benchmark_<data>.txt`) con categorie, valori e note, utile
per confronti nel tempo e regressi.
