# DB+ — Export Compliance for Cryptographic Software

**Version:** 1.0 — **Date:** 2026-08-01

This document defines the classification of DB+ with respect to cryptographic
software regulations and provides the statements required for distribution.

## 1. Subject

DB+ is a macOS/iOS (SwiftUI) application for managing MySQL/MariaDB databases.
It uses exclusively **standard cryptography** for transport/authentication
purposes:

| Function | Algorithm / Mechanism | Use |
|---|---|---|
| Direct connection | TLS 1.2/1.3 | Encryption of the channel to MySQL |
| SSH tunnel | SSH — OpenSSH (macOS) / Citadel in-process (iOS): RSA/Ed25519, AES-GCM/CTR, ChaCha20-Poly1305 | Encrypted port forwarding |
| HTTPS bridge | TLS 1.2/1.3 (ATS) | Transport of JSON requests |
| Bridge signing | HMAC-SHA256 | Message authentication (anti-tamper) |
| Secret storage | System Keychain (AES) | Local credentials |
| Anti-replay nonce | Timestamp + signature | HTTPS tunnel |

There is no proprietary cryptography, nor functionality to hide content from
the user. There are no "custom" features subject to the special categories of
the US Export Administration Regulations (EAR).

## 2. US Export Administration Regulations (EAR) classification

DB+ falls under category **5A002 / 5D002** (cryptographic goods) but satisfies
the requirements of the **"mass market" exemption** under **15 CFR 740.17(b)**
and the classification note for category 5:

- cryptography uses **standard public algorithms** (TLS, SSH, AES);
- cryptographic functions are **not controllable nor customizable** by the
  user beyond the documented settings;
- the application **cannot be used** to hide communications from third
  parties, nor for intelligence/surveillance purposes;
- interoperable with standard services (MySQL/MariaDB servers, SSH).

Consequently the product can be classified as **ENC – mass market / 5D992.c**
for EAR purposes (Commerce Control List), with default ECCN **5D992** and
**ENC** entry, without requiring an export license for the mass market.

> Note: this is a technical assessment provided for informational purposes.
> The official classification must be confirmed with your legal/export
> control office before commercial distribution.

## 3. App Store declaration (Apple)

Apple requires, when filling out the "App Store Connect" → **App Privacy /
Export Compliance** form, answers to these questions. For DB+:

1. **Does the app use cryptography?** Yes (TLS/SSH/HMAC as above).
2. **Is the cryptography registered for international standard?** Yes.
3. **Is the app compliant with category 5 exemptions?** Yes
   (standard algorithms, "mass market", 15 CFR 740.17).
4. **Does the app use a non-exempt export restriction?** No.

Therefore, the answer to select is **"Yes, in compliance with Category 5
exemptions"**, and the `ITSAppUsesNonExemptEncryption` flag must be **`false`**.

### 3.1 Info.plist verification

In the project the value is set both in the `Info.plist` file and via build
setting:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

### 3.2 Note for the future

If a future release added **non-exempt** cryptography (e.g. document
encryption with its own key, DRM, etc.), the application should:
1. set `ITSAppUsesNonExemptEncryption = true`;
2. request an updated product classification;
3. update this document and the App Store Connect form.

## 4. macOS compliance (notarization)

Product distribution is based on:
- **Hardened Runtime** enabled;
- **notarization** with Apple Developer ID;
- **App Sandbox disabled** for the tool: the SSH module launches
  `/usr/bin/ssh`, and a sandboxed app cannot spawn child processes.
  For a future sandboxed distribution the SSH module would need to be
  reworked (e.g. pure in-process SSH client).

### 4.1 iOS / iPadOS

On the iOS/iPadOS platform:
- **App Sandbox is always active** (imposed by the system);
- the **SSH tunnel uses an in-process client** (Citadel on SwiftNIO +
  swift-crypto) instead of `/usr/bin/ssh`: no child process, so the process
  restriction does not apply; private keys (imported or generated) are stored
  in `Documents/SSHKeys`, reachable from Finder via file sharing
  (`UIFileSharingEnabled`);
- the rest of the transport (direct, HTTPS bridge) operates within standard
  network permissions;
- for the **App Store** the same export declaration of section 3 applies
  (`ITSAppUsesNonExemptEncryption = false`): the cryptography used (TLS, SSH,
  HMAC-SHA256, Keychain AES) is exempt under category 5.

## 5.1 Firebase Crashlytics

The app integrates **Firebase Crashlytics** for crash reporting:

- communication with Google services happens over **HTTPS (TLS 1.2/1.3)** —
  standard cryptography, exempt under category 5;
- it does **not** introduce non-exempt cryptography: the
  `ITSAppUsesNonExemptEncryption` flag stays **`false`**;
- for **App Privacy** in App Store Connect, the collection of
  **diagnostics (crash data)** by the Firebase provider must be declared;
- collection can be disabled at runtime with
  `Crashlytics.setCrashlyticsCollectionEnabled(false)`.

## 5. Related security best practices

- Secrets stored **only** in the Keychain (`kSecAttrAccessible
  AfterFirstUnlockThisDeviceOnly`).
- Temporary `SSH_ASKPASS` helper (`0600`) removed at teardown.
- No credentials in logs or bridge responses.
- Systematic prepared statements for write operations.
- Rate limiting and HMAC on the remote bridge.
