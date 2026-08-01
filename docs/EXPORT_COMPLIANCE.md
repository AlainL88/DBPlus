# DB+ — Conformità all'Esportazione di Software Crittografico

**Versione:** 1.0 — **Data:** 2026-08-01

Questo documento definisce la classificazione di DB+ rispetto alle
regolamentazioni sul software crittografico e fornisce le dichiarazioni
richieste per la distribuzione.

## 1. Oggetto

DB+ è un'applicazione desktop macOS per la gestione di database
MySQL/MariaDB. Utilizza esclusivamente **crittografia standard** a
scopi di trasporto/autenticazione:

| Funzione | Algoritmo / Meccanismo | Uso |
|---|---|---|
| Connessione diretta | TLS 1.2/1.3 | Cifratura del canale verso MySQL |
| Tunnel SSH | SSH (OpenSSH), RSA/Ed25519, AES-CTR/GCM | Port forwarding cifrato |
| Bridge HTTPS | TLS 1.2/1.3 (ATS) | Trasporto delle richieste JSON |
| Firma del bridge | HMAC-SHA256 | Autenticazione messaggi (anti-tamper) |
| Archiviazione segreti | Keychain di sistema (AES) | Credenziali locali |
| Nonce anti-replay | Timestamp + firma | Tunnel HTTPS |

Non è presente crittografia proprietaria, né funzioni per nascondere
il contenuto all'utente. Non sono presenti funzionalità "custom"
soggette alle categorie speciali dell'Export Administration
Regulations (EAR) degli Stati Uniti.

## 2. Classificazione US Export Administration Regulations (EAR)

DB+ rientra nella categoria **5A002 / 5D002** (merce crittografica)
ma soddisfa i requisiti di **esenzione "mass market"** ai sensi di
**15 CFR 740.17(b)** e della nota di classificazione alla categoria 5:

- la crittografia usa **algoritmi standard pubblici** (TLS, SSH, AES);
- le funzioni crittografiche **non sono controllabili né customizzabili**
  dall'utente oltre le impostazioni documentate;
- l'applicazione **non può essere utilizzata** per nascondere
  comunicazioni a terzi né per finalità di intelligence/surveillance;
- interoperabile con servizi standard (server MySQL/MariaDB, SSH).

Di conseguenza il prodotto può essere classificato come
**ENC – mass market / 5D992.c** ai fini EAR (Commerce Control List),
con ECCN di default **5D992** e scheda **ENC**, senza richiedere
licenza di esportazione per il mercato di massa.

> Nota: questa è una valutazione tecnica fornita a scopo informativo.
> La classificazione ufficiale va confermata con il proprio ufficio
> legale/export control prima della distribuzione commerciale.

## 3. Dichiarazione per l'App Store (Apple)

Apple richiede, durante la compilazione della scheda "App Store
Connect" → **App Privacy/Export Compliance**, la risposta a queste
domande. Per DB+:

1. **L'app usa crittografia?** Sì (TLS/SSH/HMAC come sopra).
2. **La crittografia è registrata per lo standard internazionale?** Sì.
3. **L'app è conforme alle esenzioni della categoria 5?** Sì
   (algoritmi standard, "mass market", 15 CFR 740.17).
4. **L'app usa una restrizione di esportazione non esente?** No.

Pertanto, la risposta da selezionare è **"Sì, in conformità con le
esenzioni della Categoria 5"** e il flag `ITSAppUsesNonExemptEncryption`
deve essere **`false`**.

### 3.1 Verifica dell'Info.plist

Nel progetto il valore è impostato sia nel file `Info.plist` sia via
build setting:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

### 3.2 Nota per il futuro

Se in una release futura si aggiungesse crittografia **non esente**
(es. cifratura documenti con propria chiave, DRM, ecc.),
l'applicazione dovrebbe:
1. impostare `ITSAppUsesNonExemptEncryption = true`;
2. richiedere la classificazione aggiornata del prodotto;
3. aggiornare questo documento e la scheda App Store Connect.

## 4. Conformità macOS (notarizzazione)

La distribuzione del prodotto si basa su:
- **Hardened Runtime** abilitato;
- **notarizzazione** con Apple Developer ID;
- **App Sandbox** disattivata per il tool: il modulo SSH lancia
  `/usr/bin/ssh` e un'app sandboxata non può generare processi figli.
  Per una futura distribuzione sandboxata andrebbe rivisto il modulo
  SSH (es. client SSH puro in-process).

## 5. Best practice di sicurezza correlate

- Segreti conservati **solo** nel Keychain (`kSecAttrAccessible
  AfterFirstUnlockThisDeviceOnly`).
- Helper `SSH_ASKPASS` temporaneo (`0600`) eliminato al teardown.
- Nessuna credenziale nei log o nelle risposte del bridge.
- Prepared statement sistematici nelle operazioni scritte.
- Rate limiting e HMAC sul bridge remoto.
