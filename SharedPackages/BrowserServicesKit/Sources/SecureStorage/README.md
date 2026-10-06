# SecureStorage

Encrypted SQLite storage (SQLCipher through GRDB) for vaults. The Autofill vault in
`../BrowserServicesKit/SecureVault/` is its main user, and the doc comment in
`AutofillSecureVault.swift` defines the L0–L3 encryption levels.

- **Keys.** The L1 key lives in the Keychain and is the SQLCipher database passphrase. The L2 key is
  stored encrypted with the user's password, or with a password generated on first run. After the
  vault is unlocked it keeps that password for 3 days, so L2 data stays readable without asking
  again.
- **One factory per vault type.** `SecureVaultFactory.makeVault` builds the vault once and returns
  the same instance on later calls. Call it as often as you need through the shared factory, such as
  `AutofillSecureVaultFactory`, rather than creating another factory.
- **Corruption recovery.** When opening the database fails with `SQLITE_NOTADB` or `SQLITE_CORRUPT`,
  `SecureStorageDatabaseProvider` moves the file aside as a `.bak`, creates an empty database in its
  place, and calls `onDatabaseRecreation`.
- **Location.** On iOS the Autofill database moves into the `<app group prefix>.vault` App Group at
  `Vault/Vault.db`, and stays at its old path if the move fails. On macOS it stays in the app's
  sandbox. Both platforms open it with a `DatabaseQueue`.
- **GRDB** comes from the `duckduckgo/GRDB.swift` fork as a prebuilt xcframework, pinned by URL and
  checksum in `SharedPackages/BrowserServicesKit/Package.swift`. Updating it means publishing a new
  release of the fork, then bumping both values.
