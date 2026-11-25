# Qestak backup format (.qbk), version 1

A `.qbk` file is UTF-8 JSON. It is identical on Android and iOS.

| Field | Meaning |
|---|---|
| app | `com.qestak.app` |
| format | backup format version (1) |
| schemaVersion | database schema version of the data inside |
| createdAt | ISO-8601 UTC |
| kdf / iterations / salt | PBKDF2-HMAC-SHA256, 100,000 iterations, 16-byte random salt (base64) |
| cipher / nonce | AES-256-GCM, 12-byte random nonce (base64) |
| ciphertext / mac | encrypted payload and 16-byte GCM tag (base64) |

Authenticated data (AAD) = `app|format|schemaVersion|createdAt`, so editing any header field makes decryption fail.

Decrypted payload (JSON): `{ counts: {table: n}, data: {table: [row, ...]} }` for all 14 tables. Rows use drift's `toJson` (DateTime = epoch milliseconds, money = integer piastres).

Restore checklist (implemented in `BackupService`): app id, format <= supported, schemaVersion <= app's, password + GCM tag, per-table counts, parent/child references, then a single transaction (delete all, insert all, integrity check). Any failure rolls back and keeps the existing data.

Not included: customer photos/attachment files (not implemented yet). If the password is lost the file cannot be opened.
