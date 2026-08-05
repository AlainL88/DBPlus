# DB+

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
[![Platform: macOS](https://img.shields.io/badge/macOS-26.5+-brightgreen)](#requirements)
[![Platform: iOS](https://img.shields.io/badge/iOS%20%2F%20iPadOS-26.5+-blue)](#requirements)
[![Language: Swift](https://img.shields.io/badge/Swift-6-orange)](https://www.swift.org)
[![App Store](https://img.shields.io/badge/App%20Store-0D96F6?logo=app-store&logoColor=white)](https://apps.apple.com/app/id6797038461)

A native **MySQL & MariaDB client** for macOS, iPhone and iPad. Open source, built with SwiftUI.

DB+ is a modern database manager that runs natively on Apple platforms — no Electron, no subscriptions, no telemetry. Connect to your MySQL or MariaDB servers directly or through an SSH tunnel, browse schemas, write and run SQL, and edit rows right from your Mac or phone.

## Features

- **Native & cross-platform** — one SwiftUI codebase for macOS, iPhone and iPad.
- **Direct, SSH and HTTPS bridge connections** — plain TCP with TLS, SSH tunneling (system OpenSSH on macOS, in-process [Citadel](https://github.com/grdschomberg/citadel) client on iOS), or an HTTPS bridge to a `db_bridge.php` endpoint for restricted networks.
- **Credential security** — connection secrets stored in the Keychain, never on disk in plain text.
- **Biometric lock** — optional Face ID / Touch ID gate on your saved connection profiles.
- **SQL console** — multi-statement queries, schema-aware autocomplete and syntax highlighting.
- **Schema inspector** — browse tables, views and columns in a navigable outline.
- **Data grid with CRUD** — type-aware cell editor (date, numeric, text), NULL toggle and a full row editor.
- **CSV export** — export query results and tables in one tap.
- **Configurable pagination** — set rows per page, or show all rows without a limit.

## Screenshots

_Coming soon — screenshots of the workspace, SQL console and data grid._

## Requirements

- macOS 26.5+, or iOS / iPadOS 26.5+
- Xcode 26.5+
- Swift 6

## Dependencies

| Package | Purpose |
|---|---|
| [MySQLNIO](https://github.com/vapor/mysql-nio) | Async MySQL client — prepared statements, streaming rows, TLS |
| [Citadel](https://github.com/grdschomberg/citadel) | In-process SSH client for iOS (SwiftNIO + swift-crypto) |
| [firebase-ios-sdk](https://github.com/firebase/firebase-ios-sdk) | Crashlytics crash reporting |

## Build

1. Clone the repository:
   ```bash
   git clone https://github.com/AlainL88/DBPlus.git
   ```
2. Open `DB+.xcodeproj` in Xcode.
3. Select the **DB+** scheme and your target device.
4. Build & run (⌘R).

> **Firebase / Crashlytics:** the app configures Crashlytics at launch, which requires a valid `GoogleService-Info.plist` in the **DB+** target. Add your own Firebase configuration to build and run, or remove the Crashlytics calls if you don't need crash reporting. On Xcode Cloud, the file is restored from a base64 secret by `ci_scripts/ci_post_clone.sh`.

## Architecture

DB+ is transport-agnostic: a single `DatabaseTransport` protocol isolates all app logic (schema inspector, data grid, query runner) from the concrete network implementations (direct, SSH, bridge).

See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for the full design.

## Security

- Passwords and SSH keys are stored in the **Keychain**.
- All SQL is executed through **prepared statements** (MySQLNIO), guarding against SQL injection.
- Optional **biometric lock** protects saved connection profiles.
- No analytics beyond Crashlytics crash reporting, and no data ever leaves your device except to the servers you configure.

## Compliance

DB+ uses only standard cryptography (TLS, SSH, HMAC-SHA256) and is classified as mass-market / exempt for export purposes. See [docs/EXPORT_COMPLIANCE.md](docs/EXPORT_COMPLIANCE.md) for the full assessment.

## Support the project ☕

DB+ is free, open source, and will stay that way. Building a polished app for three platforms takes evenings and weekends — if DB+ saves you time at work, a coffee keeps the project alive and the next feature shipping sooner.

[![Buy Me a Coffee](https://img.shields.io/badge/Buy%20Me%20a%20Coffee-FFDD00?logo=buy-me-a-coffee&logoColor=000)](https://buymeacoffee.com/alainl)

Supporting the project doesn't unlock features — it just keeps it funded and free for everyone.

## License

[MIT](LICENSE) © 2026 Alain Lima
