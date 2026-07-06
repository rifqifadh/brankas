# Brankas Security Architecture

## Overview

Brankas is a local-only macOS password vault. All data is encrypted with **AES-256-GCM**, key derived via **PBKDF2-HMAC-SHA256** with a random salt. No cloud sync, no telemetry, no network access (except opt-in NTP time sync for TOTP codes).

---

## 1. Why Two Files? `.enc` + `.salt`

### The Chicken-and-Egg Problem

To decrypt the vault, we need the AES key. To derive the AES key (PBKDF2), we need the salt.

```
Decrypt vault.enc → need AES key → need salt → need to decrypt vault.enc ✗
```

The salt must be available **before** decryption. Salt is **not a secret** — it prevents rainbow table attacks and ensures different vaults get different keys even with the same password. Storing it unencrypted is standard practice (same as Linux `/etc/shadow` storing salt alongside password hashes).

### Why Not Embed Salt in `.enc`?

That's what the export format does (see section 5). For the vault, we chose separate files because:

| Reason | Detail |
|--------|--------|
| **Migration** | Original code used raw SHA256 (no salt). Adding a `.salt` file was the simplest migration path — no vault format change needed. |
| **Clean read path** | `AES.GCM.SealedBox(combined:)` reads directly from file contents. Prepend salt means manual wrapping/unwrapping. |
| **Backward compat** | Salt file missing on load → try SHA256 fallback for legacy vaults. If salt were embedded, we'd need version flags and format parsers. |

### File Layout

```
~/Library/Application Support/
├── brankas-vault.enc       ← AES-256-GCM encrypted blob (nonce + ciphertext + tag)
├── brankas-vault.salt      ← 16 random bytes (plaintext, not secret)
└── Brankas Backups/        ← Daily copies of both files
```

In debug mode:

```
~/Library/Application Support/
├── brankas-vault-debug.enc
├── brankas-vault-debug.salt
└── ...
```

---

## 2. Threat Model

### Assumptions

- Attacker has **read access to disk** (`~/Library/Application Support/`)
- Attacker does **NOT** have the master password
- App runs on a **trusted device** (macOS 14+ with hardware security)

### Protected Against

| Attack | Mitigation |
|--------|-----------|
| Offline dictionary attack on vault file | PBKDF2 (100k iterations) slows brute force |
| Rainbow table attack | 16-byte random salt makes precomputation infeasible |
| Clipboard snooping | Auto-clear after 30s (configurable) |
| Tampered ciphertext | AES-GCM authentication tag — fails decryption |
| Unauthorized local access | Optional biometric unlock via macOS Keychain |

### Not Protected Against (Conscious Tradeoffs)

- **Keylogging** / memory inspection while app is unlocked
- **Physical device compromise** with vault already decrypted
- **Side-channel attacks**

---

## 3. Key Derivation

```
Master Password (user-chosen)
        │
        ▼
PBKDF2-HMAC-SHA256
  Iterations: 100,000
  Salt: 16 random bytes (SecRandomCopyBytes)
  Key length: 32 bytes (256 bits)
        │
        ▼
AES-256 SymmetricKey (CryptoKit)
```

### PBKDF2 Parameters

| Parameter | Value | Why |
|-----------|-------|-----|
| Algorithm | `kCCPBKDF2` | NIST SP 800-132 standard |
| PRF | `kCCPRFHmacAlgSHA256` | HMAC-SHA256 (fast on Apple Silicon) |
| Iterations | **100,000** | OWASP 2024 minimum recommendation for SHA256 |
| Salt length | **16 bytes** (128 bits) | Sufficient to defeat rainbow tables |
| Key length | **32 bytes** (256 bits) | AES-256 requires 256-bit key |

### Code Path

```swift
// CommonCrypto CCReyDerivationPBKDF is the system implementation
// Used instead of writing our own — always use platform crypto, never roll your own

let status = CCKeyDerivationPBKDF(
    CCPBKDFAlgorithm(kCCPBKDF2),           // algorithm
    passwordBytes,                          // password
    passwordData.count,                     // password length
    saltBytes,                              // salt
    salt.count,                             // salt length
    CCPseudoRandomAlgorithm(kCCPRFHmacAlgSHA256),  // PRF
    100_000,                                // iterations
    &derivedKey,                            // output buffer
    derivedKey.count                        // output length (32)
)
```

### Why PBKDF2 and not...

| Alternative | Status | Reason |
|-------------|--------|--------|
| **scrypt** | Not used | macOS has no built-in scrypt API without third-party dependency |
| **Argon2** | Not used | Same — no system library, would require bundling |
| **HKDF** | Not enough | Key-based KDF, not password-based (no iteration count) |
| **Raw SHA256** | ✅ **Replaced** | Was the original implementation — no salt, no iterations, fast to brute force |

> PBKDF2 with 100k iterations takes ~50ms on Apple Silicon. Argon2 would take same time with better GPU resistance. Future upgrade path if Apple adds native Argon2 support.

### Migration from SHA256 (Legacy)

```
VaultService.load(password)
        │
        ▼
Does salt file exist?
├── YES → PBKDF2(key, salt)
└── NO  → Try SHA256(key)
              │
              ▼
          Success?
          ├── YES → Generate salt, re-encrypt with PBKDF2 → save salt file
          │         (transparent to user, happens on next persist)
          └── NO  → Wrong password → 3 attempts → quit
```

---

## 4. Encryption

```
JSON plaintext
    │
    ▼
AES-256-GCM Encryption
├── Generates random 12-byte nonce
├── Encrypts plaintext
├── Computes 16-byte authentication tag
└── Outputs: nonce + ciphertext + tag = "combined" SealedBox
    │
    ▼
vault.enc (atomic write)
```

### AES-GCM Details

| Property | Value |
|----------|-------|
| Algorithm | AES-256 in Galois/Counter Mode |
| Key size | 256 bits |
| Nonce | 12 bytes (random, generated by CryptoKit) |
| Tag | 16 bytes (integrity verification) |
| Implementation | Apple CryptoKit (`AES.GCM`) |
| Write mode | `.atomic` — file replaced atomically, no partial writes |

### Why AES-GCM?

- **Authenticated encryption**: ciphertext + integrity check in one operation. If someone modifies the vault file, decryption fails with an error.
- **Hardware acceleration**: Apple Silicon has dedicated AES instructions. Encryption of a typical vault (<1MB) takes <1ms.
- **No padding**: GCM is a stream cipher mode — ciphertext is exactly plaintext length + 16 bytes tag.

### What Gets Encrypted

The entire `VaultData` struct is serialized to JSON, then encrypted:

```json
{
  "version": 2,
  "createdAt": "2026-01-01T00:00:00Z",
  "updatedAt": "2026-07-06T12:00:00Z",
  "secrets": {
    "<uuid>": "<password-value>",
    "totp-<uuid>": "otpauth://...",
    ...
  },
  "items": [
    { "id": "<uuid>", "name": "API Key", "typeRawValue": "token", ... }
  ],
  "accounts": [
    { "id": "<uuid>", "identifier": "user@example.com", "serviceId": "<uuid>", ... }
  ],
  "services": [ ... ],
  "categories": [ ... ],
  "tags": [ ... ]
}
```

Both secret values AND metadata (names, tags, expiry dates) are encrypted together in the same blob.

---

## 5. Export Encryption

Same scheme, but salt is **embedded** in the export file (single file):

```
┌──────────────────────────────────────┐
│ Salt (16 bytes, random per export)   │ ← Plaintext
├──────────────────────────────────────┤
│ AES-GCM SealedBox                    │
│  ┌────────────────────────────────┐  │
│  │ Nonce (12 bytes)               │  │
│  ├────────────────────────────────┤  │
│  │ Ciphertext ([ExportEntry...])  │  │
│  ├────────────────────────────────┤  │
│  │ Auth Tag (16 bytes)            │  │
│  └────────────────────────────────┘  │
└──────────────────────────────────────┘
```

- Each export generates a **new random salt** (independent of vault salt)
- Encrypted with user-chosen export password (can differ from master password)
- Decrypt: read first 16 bytes → salt → PBKDF2 → key → decrypt rest

---

## 6. Data Lifecycle

### First Launch

```
1. User enters master password
2. No vault file exists → this is a new user
3. Generate 16-byte random salt → write to .salt file
4. PBKDF2(password, salt, 100k) → 256-bit key
5. Create empty VaultData struct
6. JSON encode → AES-256-GCM seal → write to vault.enc
```

### Normal Load

```
1. User enters master password
2. Read .salt file (16 bytes)
3. PBKDF2(password, salt, 100k) → 256-bit key
4. Read vault.enc → AES.GCM.SealedBox(combined:)
5. AES.GCM.open(sealedBox, using: key)
   - Fails if password wrong → "Invalid password"
   - Fails if file tampered → authentication tag mismatch → "Decryption failed"
6. JSON decode → VaultData → in-memory
```

### Persist (Every Write)

```
1. Modify in-memory VaultData (add/edit/delete)
2. Read salt from .salt file (unchanged within session)
3. JSON encode VaultData
4. PBKDF2(password, salt, 100k) → 256-bit key
5. AES-256-GCM seal → combined data
6. Atomic write to vault.enc
```

### Lock

```
VaultService.lock()
├── password = ""           ← Clear from memory
├── isLoaded = false        ← Block further reads
└── vaultData = .empty()    ← Clear cached data
```

### In-Memory Lifetime

| Data | Location | How long |
|------|----------|----------|
| Master password (String) | `VaultService.password` | Until `lock()` or app quit |
| Decrypted vault | `VaultService.vaultData` | Until `lock()` or app quit |
| SwiftData mirror | `brankas.store` (file) | Rebuilt on every launch |
| Keychain-stored password | macOS Keychain | Until user disables biometric unlock |
| Clipboard secrets | `NSPasteboard.general` | 30 seconds (configurable) |

> **Auto-lock**: Planned but not yet implemented. Currently, secrets stay in memory until app quits or `lock()` is called.

---

## 7. Biometric Unlock (Optional)

```
User enables "Unlock with Touch ID"
    │
    ▼
Master password → Keychain.save()
  Service: com.rifqifadhlillah.brankas.vault
  Accessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly
  Access control: biometryCurrentSet (requires Touch ID to read)
    │
    ▼
On next launch:
  Keychain.read() → LAContext.evaluatePolicy(.biometrics)
    │
    ├── Success → password → VaultService.load()
    └── Failed  → fall back to manual password dialog
                    (3 wrong attempts → app quits)
```

### Keychain Security

- `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` — item is encrypted at rest, only readable when device is unlocked, and does NOT migrate to backups/MDM
- `SecAccessControlCreateWithFlags` with `biometryCurrentSet` — requires Touch ID for every read
- **If biometrics change** (finger added/removed) → keychain item becomes invalid → fallback to password

### Current Limitation

`KeychainService.readVaultPassword()` uses a `DispatchSemaphore` to wait for the biometric dialog — this blocks the main thread. Planned fix: convert to `async/await`.

---

## 8. Time Sync (TOTP Only)

```
TOTP view loads
    │
    ▼
TimeSyncService.sync()   ← throttled to once per 5 minutes
    │
    ▼
HEAD requests to:
  ├── https://www.apple.com
  ├── https://www.google.com
  ├── https://api.github.com
  └── https://www.cloudflare.com
    │
    ▼
Parse HTTP Date header → compute offset = serverTime - systemTime
    │
    ▼
TOTPService.timeOffset = offset
    │
    ▼
TOTP code = HMAC-SHA1(counter + offset)   ← adjusted for clock skew
```

### Security Note

- Only outbound traffic the app makes
- **HEAD requests** — no body, no cookies, no custom headers
- **No data sent** — pure clock read
- Falls back to system clock if all endpoints unreachable
- Offset refreshes only on first TOTP view or every 5 minutes

---

## 9. Backups

```
VaultBackupService.createBackup()
    │
    ▼
Copy vault.enc → Brankas Backups/brankas-vault-2026-07-06-120000.enc
Copy vault.salt → Brankas Backups/brankas-vault-2026-07-06-120000.salt
    │
    ▼
Prune: keep 30 most recent, delete older
    │
    ▼
Restore: copy both files back, overwrite live vault
         (requires restart to rebuild SwiftData)
```

- Backups are **encrypted** with the same key as the live vault — no plaintext exposure
- Salt file included because it's required for PBKDF2 derivation
- Stored in `~/Library/Application Support/Brankas Backups/`

---

## 10. Common Questions

### Q: Why not just use the macOS Keychain instead of a custom vault?

The Keychain is designed for small items (individual passwords). Brankas stores hundreds of items + metadata + TOTP configs + custom categories/tags. A single encrypted JSON file is more portable, backup-friendly, and auditable. The Keychain is used **only** for optional biometric unlock (storing the master password).

### Q: Can I share my vault file between Macs?

Copy `vault.enc` + `vault.salt` manually. Both files are required. Brankas has no sync mechanism.

### Q: What if I lose my salt file?

The vault is unrecoverable — the salt is required for PBKDF2 key derivation. Restore from backup or accept data loss. This is why backup creates copies of both files.

### Q: Why 100,000 iterations? Isn't more better?

100k is the OWASP 2024 recommended minimum for PBKDF2-HMAC-SHA256. Higher iterations increase brute-force cost linearly, but also increase legit decryption time. On Apple Silicon M-series, 100k takes ~50ms — acceptable for a password manager unlock. 1M iterations would take ~500ms (too slow for UX).

### Q: Is the SwiftData store secure?

No. SwiftData store (`brankas.store`) is unencrypted on disk. However, it only stores **metadata** (names, types, tags) — never secret values. The actual passwords/tokens live only in the encrypted vault. The store is deleted and rebuilt from the vault on every launch.

---

## References

- [PBKDF2 (RFC 2898)](https://datatracker.ietf.org/doc/html/rfc2898)
- [AES-GCM (NIST SP 800-38D)](https://csrc.nist.gov/publications/detail/sp/800-38d/final)
- [TOTP (RFC 6238)](https://datatracker.ietf.org/doc/html/rfc6238)
- [OWASP Password Storage Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Password_Storage_Cheat_Sheet.html)
- [Apple CryptoKit Documentation](https://developer.apple.com/documentation/cryptokit)
- [Apple CommonCrypto Documentation](https://developer.apple.com/documentation/commons/cckeyderivationpbkdf)
