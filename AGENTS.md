# Brankas — macOS password/secret vault (menu bar app)

## Build & Run

```bash
# Debug (auto-auth with password "debug", uses brankas-vault-debug.enc)
swift build --product Brankas

# Release (real auth, uses brankas-vault.enc)
swift build -c release --product Brankas

# Full app bundle + launch (debug)
./build-and-run.sh

# Full app bundle + DMG (release)
./build-release.sh
```

No test targets exist. No dependencies (pure Swift/SwiftUI/AppKit, macOS 14+ only).

## Architecture

- **`@main`**: `BrankasApp` in `TokenBookApp.swift` — only scene is `Settings`; AppDelegate handles everything else.
- **AppDelegate** (`AppDelegate.swift`): Creates menu bar icon, NSStatusItem popover, manages auth lifecycle.
- **Two persistence layers** (source of truth = encrypted file; SwiftData = read-only UI mirror):
  1. **Encrypted vault** (`~/Library/Application Support/brankas-vault[-debug].enc`) — AES-256-GCM, password-derived key via SHA256 (no salt), all state in `VaultService` static vars
  2. **SwiftData store** (`~/Library/Application Support/brankas[-debug].store`) — deleted and re-populated from vault on every launch via `VaultSyncService.syncAll()`
- **`#if DEBUG`** controls separate paths for vault, store, backups key, and auth bypass. **Keep them in sync** — any new persistent resource needs a debug variant.

## Data locations

| What | Path |
|------|------|
| Debug vault | `~/Library/Application Support/brankas-vault-debug.enc` |
| Release vault | `~/Library/Application Support/brankas-vault.enc` |
| Debug SwiftData | `~/Library/Application Support/brankas-debug.store` |
| Release SwiftData | `~/Library/Application Support/brankas.store` |
| Backups | `~/Library/Application Support/Brankas Backups/` (keeps 30) |
| Keychain | `com.rifqifadhlillah.brankas.vault` / `vault-password` |
| UserDefaults | `schemaVersion`, `biometricUnlock`, `clipboardAutoClearDuration`, `lastVaultBackupDate[-debug]` |

## Debug mode behavior

In Debug (`#if DEBUG`):
- Auto-authenticates with hardcoded password `"debug"` — no dialog
- Uses `brankas-vault-debug.enc` and `brankas-debug.store` (isolated from release)
- `VaultBackupService` uses `lastVaultBackupDate-debug` key

## Vault operations (all static, on `VaultService`)

- Every mutation calls `persist()` which re-encrypts the entire vault and writes atomically.
- Mutations also sync to SwiftData via inline `syncItem`/`syncAccount` calls.
- When in doubt, read `VaultService.swift` — the service methods directly mirror the CRUD operations.

## Xcode project

- Source of truth: `project.yml` (XcodeGen). Regenerate with `xcodegen generate`.
- `*.xcodeproj` is gitignored (generated).
- `SWIFT_ACTIVE_COMPILATION_CONDITIONS` must only carry `DEBUG` in Debug config — verified in `project.yml:configs:`.

## Schema migrations

- `currentSchemaVersion = 4` in `AppDelegate.swift`.
- On version mismatch: backs up old `.store`, `.store-wal`, `.store-shm` to `~/Desktop/Brankas-backup-v{old}-{timestamp}/`, then deletes originals.

## Known quirks / pitfalls

- **No test target** exists. Don't look for tests.
- **Static state**: `VaultService` uses all static properties. Changes must account for this.
- **Vault file ≠ working for both configs**: Debug and Release vaults are separate files. Opening data from one won't show in the other.
- **Search-disclosure interaction**: `AccountContentView` expands all `DisclosureGroup`s when search is active.
- **TOTP storage**: `totp-{id}` key in vault secrets. Currently stores raw base32 or `otpauth://` URL (not structured).
- **Clipboard auto-clear**: Uses `Timer` + `UserDefaults` for 30s default; `ClipboardService` is passed via environment.
- **Backup restore**: `VaultBackupService.restore(from:)` deletes current vault and copies backup in place — no snapshot.
