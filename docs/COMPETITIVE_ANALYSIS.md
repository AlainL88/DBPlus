# DB+ — Analisi competitiva iOS (gap analysis)

**Data:** 2026-08-03

## 1. Scopo

Il "benchmarking" richiesto nel prompt iniziale prevedeva il confronto delle
core features di DB+ con le app di riferimento del settore su iOS. Questo
documento è quell'analisi: identifica le funzionalità che la concorrenza ha e
DB+ manca, per priorizzare gli interventi.

## 2. App di riferimento (iOS)

| App | Modello | Focus |
|---|---|---|
| TablePlus (iOS) | Freemium + sub. | Client multi-driver, editor dati con undo, export |
| Navicat for MySQL | ~$22.99 | Admin completo, cloud sync, autocompletamento SQL |
| Iodine MySQL | Freemium | UI curata, dump .sql/.csv, Face ID |
| SQLPro Studio | Freemium | Multi-DB, autocompletamento, SSH |
| MySQL Mobile Client (DB Compass) | Freemium | ER diagram, processlist, AI query |
| MySql Elite | Freemium | Backup/restore, routines, event scheduler |
| MySQL QueryDB | Freemium | Reti instabili, export CSV, Siri Shortcuts |

## 3. Core features comuni della concorrenza

1. **Autocompletamento SQL** (TablePlus, Navicat, SQLPro, Iodine) — suggerimenti
   su parole chiave, nomi di tabelle e colonne nell'editor query.
2. **Editing dati con undo / pending review** (TablePlus) — le modifiche stanno
   in stato "pending" finché non vengono committate; undo/redo (Cmd+Z).
3. **Export dati** (TablePlus via email/AirDrop; Iodine .sql/.csv; QueryDB CSV;
   DB Compass) — esportazione di risultati query e dati tabella.
4. **Import dati** da CSV/SQL.
5. **Lock biometrico / Master Password** (MySql Elite Face ID/Touch ID; Iodine
   Master Password + Touch ID) — protezione dell'accesso alle credenziali.
6. **Multiple connessioni / tab** (TablePlus multi-connection; Navicat tab view).
7. **Editor e esecuzione stored procedure/funzioni** (MySql Elite, Navicat,
   Iodine).
8. **Processlist / stato server / sessioni** (DB Compass).
9. **Backup e restore / dump** (MySql Elite).
10. **iCloud sync dei profili di connessione** (Iodine, DB Compass, QueryDB).
11. **SSL/TLS con certificato custom** (TablePlus).
12. **Filtri avanzati con storico** (TablePlus).

## 4. Cosa ha già DB+

- Connessioni Diretta / SSH / Bridge, keep-alive, test connessione.
- Browser schema: database, tabelle, viste; struttura (colonne, indici, FK,
  SHOW CREATE).
- Griglia dati con paginazione, ordinamento, filtro SQL, editing inline,
  inserimento ed eliminazione righe.
- Console query multi-statement, highlight SQL, guardia sulle operazioni
  distruttive, limite righe, tempi di esecuzione.
- Tunnel SSH in-process, TLS, bridge HTTPS con HMAC, credenziali in Keychain.
- Generatore chiavi SSH Ed25519, debug log, Crashlytics.

## 5. Gap analysis e priorità

### P1 — da implementare assolutamente

| Feature | App di riferimento | Note |
|---|---|---|
| Autocompletamento SQL nell'editor | TablePlus, Navicat, SQLPro | La feature più richiesta in assoluto |
| Export dati (CSV/SQL) | Tutte | Tabelle + risultati query |
| Lock biometrico (Face ID / Touch ID) | MySql Elite, Iodine | Protezione credenziali, credibilità del prodotto |
| Editing con undo / pending | TablePlus | Oggi le modifiche cella sono immediate e irreversibili |

### P2 — molto importante

- Import dati (CSV/SQL)
- Multiple connessioni contemporanee / tab
- Editor stored procedure/funzioni
- Processlist / stato server
- Storico filtri recenti

### P3 — nice to have

- iCloud sync dei profili
- ER diagram
- EXPLAIN / piano di esecuzione
- Certificato TLS custom

## 6. Raccomandazione

Partire da **autocompletamento SQL** e **export CSV** (impatto percepito
massimo a costo ragionevole) + **lock biometrico** (privacy, requisito di
credibilità per un client DB). L'**undo/pending dell'editor dati** è una
modifica architetturale più grossa: va progettata prima di estendere l'editing.
