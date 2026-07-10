<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9-orange" alt="Swift 5.9">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT License">
</p>

<h1 align="center">🔑 Brankas</h1>
<p align="center"><em>macOS menu bar password/secret vault — all data stays on your machine.</em></p>

Brankas (Indonesian for "vault") is a native macOS menu bar app for storing API tokens, passwords, SSH keys, certificates, and login accounts with TOTP two-factor codes.

**No cloud sync. No telemetry. No network access** (except optional NTP time sync for TOTP).

---

## Features

| Feature | Description |
|---------|-------------|
| 🗄️ **Encrypted vault** | AES-256-GCM encrypted JSON file on disk. PBKDF2 key derivation (100k iterations + random salt). |
| 🔑 **Two-factor codes** | TOTP (RFC 6238) generation from `otpauth://` URLs or base32 secrets. Auto-refreshing countdown timer. |
| 👤 **Login accounts** | Store usernames, passwords, service links, and expiry dates. Grouped by service. |
| 🏷️ **Categories & tags** | Organize secrets with colored categories and searchable tags. |
| 🖱️ **Menu bar access** | Quick-copy passwords, usernames, and TOTP codes without opening the main window. |
| 🔐 **Biometric unlock** | Optional Touch ID via macOS Keychain integration. |
| ⏰ **Expiry notifications** | macOS notifications at 7 and 3 days before items expire. |
| 📋 **Auto-clearing clipboard** | Passwords automatically clear from clipboard after 30s (configurable). |
| 📦 **Bulk import** | Import accounts from CSV or JSON files. |
| 💾 **Automatic backups** | Daily encrypted vault backups (keeps 30). Manual restore supported. |
| 🔄 **Export/Import** | Password-protected export of all secrets. |

---

## Screenshots

<p align="center">
  <img src="screenshots/Screenshot%202026-07-10%20at%2010.50.43.png" alt="Menu bar popover — accounts tab" width="360">
  <img src="screenshots/Screenshot%202026-07-10%20at%2010.51.02.png" alt="Menu bar popover — vault tab" width="360">
</p>
<p align="center">
  <img src="screenshots/Screenshot%202026-07-10%20at%2010.51.19.png" alt="Main window — accounts list" width="360">
  <img src="screenshots/Screenshot%202026-07-10%20at%2010.51.29.png" alt="Adding a new service" width="360">
</p>
<p align="center">
  <img src="screenshots/Screenshot%202026-07-10%20at%2010.54.53.png" alt="Searching vault items" width="360">
  <img src="screenshots/Screenshot%202026-07-10%20at%2010.55.19.png" alt="Settings window" width="360">
</p>

---

## Quick Start

**Requirements**: macOS 14+ (Sonoma), Xcode 15+.

### Release build

```bash
# Release: real authentication dialog, production data files
swift build -c release --product Brankas
./build-release.sh    # builds + signs + packages DMG
```

> **Note**: Release builds use ad-hoc signing. Your Mac may show a Gatekeeper warning. To bypass: `xattr -dr com.apple.quarantine /path/to/Brankas.app`

### Regenerate Xcode project (optional)

```bash
xcodegen generate
```

---

## Data Storage

All data stays on your machine at `~/Library/Application Support/`:

| Path | Purpose |
|------|---------|
| `brankas-vault.enc` | Encrypted vault (AES-256-GCM, PBKDF2-derived key) |
| `brankas-vault.salt` | Cryptographic salt for PBKDF2 (generated on first launch) |
| `brankas.store` | SwiftData mirror — read-only UI cache, rebuilt from vault on launch |
| `Brankas Backups/` | Automatic daily backups (keeps 30 most recent) |
| `com.rifqifadhlillah.brankas.vault` | Keychain item (optional, for biometric unlock) |

### Debug mode

When built in Debug configuration, all paths use `-debug` suffixed filenames and auto-auths with password `"debug"`. Isolated from production data.

---

## Security Architecture

```
┌──────────────────────────────────────────────────┐
│                   Master Password                │
│                        │                         │
│              PBKDF2-SHA256 (100k)                │
│                        │                         │
│              256-bit AES Key                     │
│                        │                         │
│          AES-256-GCM Encrypt/Decrypt             │
│                        │                         │
│              vault.enc (on disk)                 │
└──────────────────────────────────────────────────┘
```

- **Key derivation**: PBKDF2 with HMAC-SHA256, 100,000 iterations, 16-byte random salt (OWASP 2024 recommendation)
- **Encryption**: AES-256-GCM (authenticated encryption, provides integrity + confidentiality)
- **Salt storage**: Separate `.salt` file (not secret — prevents rainbow table attacks)
- **Password in memory**: Stored for session duration. `lock()` clears it. Auto-lock planned.
- **Keychain**: Optional biometric unlock stores password in macOS Keychain (accessible only via Touch ID)
- **No remote access**: App makes outbound HTTPS requests only for TOTP time synchronization (to `apple.com`, `google.com`, `github.com`, `cloudflare.com`) — no telemetry, no analytics.

---

## Key Bindings

| Shortcut | Action |
|----------|--------|
| `Cmd + N` | Add new secret / account |
| `Cmd + C` | Copy secret value |
| `Cmd + E` | Edit selected item |
| `Enter` | Confirm / Save (in forms) |
| `Escape` | Cancel / Close |

---

## Development

### Branch strategy

- `main` — release-ready, all checks passing
- Feature branches off `main`, squash-merge with conventional commit messages

### Coding standards

- Swift 5.9, no external dependencies (pure SwiftUI/AppKit/CryptoKit)
- `#if DEBUG` for debug-only paths (keep debug/release in sync)
- Static `VaultService` currently — instance refactor planned
- SwiftData is read-only UI mirror; encrypted vault file is source of truth

### Pre-submit checklist

1. Build both debug and release: `swift build` and `swift build -c release`
2. Check all `#if DEBUG` paths have matching release counterparts
3. Run `xcodegen generate` if `project.yml` changed
4. Update `NEXT_DEVELOPMENT.md` if adding new planned work

---

## FAQ

**Q: Can I sync my vault across devices?**  
A: No. Brankas is intentionally local-only. Copy `brankas-vault.enc` manually between machines if needed.

**Q: What if I forget my master password?**  
A: The vault cannot be recovered. Restore from a backup (kept in `~/Library/Application Support/Brankas Backups/`).

**Q: Why SwiftData + encrypted file instead of just Core Data?**  
A: The encrypted file is the source of truth — portable, auditable, and backup-friendly. SwiftData provides type-safe queries for the UI without exposing plaintext to the persistence layer.

**Q: How are TOTP secrets stored?**  
A: Under the key `totp-{id}` in the vault's secret dictionary. Stored as the raw `otpauth://` URL or base32 secret provided during setup.

---

## Contributing

1. File an issue for bugs or feature requests
2. For security issues, email directly (see commit history)
3. PRs welcome — follow the [development plan](NEXT_DEVELOPMENT.md) for priority items
4. Phase 1 (security) items should be discussed before implementation

---

## License

MIT License. See [LICENSE](LICENSE).

Copyright © 2026 Rifqi Fadhlillah
