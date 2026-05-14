# Sync

Cross-device end-to-end encrypted data synchronization for bookmarks, credentials, settings, and more.

## Overview

Sync enables users to securely synchronize their browsing data across multiple devices using end-to-end encryption. All synced data is encrypted on the device before transmission, ensuring that only the user's devices can decrypt and access the information. The server never has access to unencrypted data.

**Supported Data Types:**
- Bookmarks (including folder structure and favicons)
- Credentials (passwords and usernames)
- Credit Cards (feature-flagged)
- Identities (autofill profiles, feature-flagged)
- Settings (user preferences)

**Key Features:**
- End-to-end encryption with no server access to unencrypted data
- Device pairing via QR codes or manual codes
- Recovery codes for account restoration
- Automatic conflict resolution
- Background synchronization

## Architecture

### Encryption Model

Sync uses a dual-key end-to-end encryption architecture:

```
Device Setup:
    Generate userId + deviceId
        ↓
    Generate primaryKey (for account)
        ↓
    Derive secretKey (for data encryption)
        ↓
    Store keys in Keychain
        ↓
    Encrypt data with secretKey
        ↓
    Transmit encrypted data to server
```

**Primary Key**: Used for account authentication and device pairing. Combined with `userId` forms the recovery code that allows restoring sync on new devices.

**Secret Key**: Derived from primary key, used for actual data encryption/decryption. Never leaves the device in unencrypted form.

**Server Role**: Only stores encrypted data and manages device authentication. Cannot decrypt any synced content.

### Package Architecture

```
App Layer (Sync feature module)
    ↓
DDGSync Package (core engine)
    ├── Account Management
    ├── Encryption (DDGSyncCrypto)
    ├── Device Pairing
    └── Sync Operations
    ↓
SyncDataProviders Package (data type implementations)
    ├── BookmarksProvider
    ├── CredentialsProvider
    ├── CreditCardsProvider
    ├── IdentitiesProvider
    └── SettingsProvider
    ↓
Local Storage
    ├── Core Data (bookmarks)
    ├── Secure Vault (credentials)
    └── SyncMetadataDatabase (sync state)
```

## Key Components

### Core Engine

- **`DDGSync`** - DDGSync package (BrowserServicesKit)
  - Main sync service protocol
  - Account creation and authentication
  - Device registration and management
  - Encryption and decryption operations
  - Sync scheduling and execution

- **`Crypting`** - DDGSync package
  - Protocol for encryption operations
  - Primary key and secret key management
  - Base64 encoding/decoding with encryption
  - Keychain storage integration

### App Integration

- **`DeviceSyncCoordinator`** - Sync module
  - Coordinates sync UI flows
  - Presents sync management dialog
  - Handles device pairing workflows
  - Manages sheet presentation

- **`SyncDataProvidersSource`** - Sync module
  - Aggregates all sync data providers
  - Initializes metadata database
  - Sets up individual data type adapters
  - Feature flag integration for optional data types

### Data Adapters

- **`SyncBookmarksAdapter`** - Sync module
  - Bridges bookmark manager and BookmarksProvider
  - Configures favicons fetching post-sync
  - Handles bookmark-specific error reporting
  - Triggers bookmark reload after sync

- **`SyncCredentialsAdapter`** - Sync module
  - Connects SecureVault with CredentialsProvider
  - Manages credential cleanup on errors
  - Handles autofill integration

- **`SyncSettingsAdapter`** - Sync module
  - Syncs user preferences across devices
  - Handles settings-specific sync handlers
  - Coordinates preference updates

- **`SyncCreditCardsAdapter`** / **`SyncIdentitiesAdapter`** - Sync module
  - Feature-flagged autofill data synchronization
  - SecureVault integration for encrypted storage

### Metadata Management

- **`SyncMetadataDatabase`** - Sync module
  - Core Data database for sync state
  - Tracks timestamps per data type
  - Stores sync operation metadata
  - Manages conflict resolution data

## Device Pairing Flows

### Connect Flow (Pairing Two Devices)

**Scenario**: User wants to connect a new device to existing sync account.

**Steps**:
1. **Initiating Device** (already syncing):
   - Generates connect code
   - Displays QR code or manual code
   - Waits for new device to scan/enter code

2. **New Device**:
   - Scans QR code or enters manual code
   - Extracts encrypted recovery key from code
   - Decrypts recovery key using code's secret
   - Creates account locally with recovered keys
   - Registers device with server
   - Begins initial sync

**Security**: Connect codes are one-time use and expire after short period. Keys are encrypted during transmission.

### Recovery Flow (Restoring Sync)

**Scenario**: User wants to restore sync on a device using recovery code.

**Steps**:
1. User enters recovery code (base64-encoded JSON containing `userId` + `primaryKey`)
2. App decodes recovery code to extract keys
3. Device registers with server using extracted keys
4. Secret key is derived from primary key
5. Device downloads and decrypts existing sync data
6. Initial sync populates local data stores

**Recovery Code Format**: Base64-encoded JSON containing `userId` and `primaryKey`. This allows complete account restoration without requiring access to other devices.

## Sync Data Types

### Bookmarks

**Provider**: `BookmarksProvider` - SyncDataProviders package

**Storage**: Core Data database with `BookmarkEntity` objects

**Sync Scope**:
- Bookmark URLs, titles, folders
- Folder hierarchy and nesting
- Favorites flag and display order
- Created/modified timestamps

**Post-Sync Operations**:
- Favicons fetching for new/modified bookmarks
- Bookmark list reload in UI
- Favorites bar updates

### Credentials

**Provider**: `CredentialsProvider` - SyncDataProviders package

**Storage**: SecureVault with encrypted storage

**Sync Scope**:
- Website URLs and domains
- Usernames and passwords (encrypted)
- Notes and custom fields
- Last used timestamps

**Error Handling**: Cleanup operations for failed credential sync to maintain data integrity.

### Settings

**Provider**: `SettingsProvider` - SyncDataProviders package

**Storage**: UserDefaults and app-specific storage

**Sync Scope**:
- User preferences (e.g., favorites display mode)
- Feature settings
- UI customization options

**Sync Handlers**: Individual setting types implement `SettingSyncHandler` protocol for custom sync logic.

### Credit Cards (Feature-Flagged)

**Provider**: `CreditCardsProvider` - SyncDataProviders package

**Enabled**: When `syncCreditCards` feature flag is on

**Storage**: SecureVault with encrypted storage

**Sync Scope**: Credit card information for autofill

### Identities (Feature-Flagged)

**Provider**: `IdentitiesProvider` - SyncDataProviders package

**Enabled**: When `syncIdentities` feature flag is on

**Storage**: SecureVault with encrypted storage

**Sync Scope**: Autofill identity profiles (names, addresses, etc.)

## Integration Points

### Preferences

The Settings > Sync section provides:

- **Setup Flows**: Initial device pairing (Connect or Recovery)
- **Device Management**: View connected devices, remove devices
- **Sync Status**: Shows last sync time and sync state
- **Recovery Code**: Display recovery code for backup
- **Sync Settings**: Turn sync on/off, manage synced data types

Dialog presentation managed by `DeviceSyncCoordinator` and `SyncManagementDialogViewController`.

### Data Provider Integration

Each syncable data type requires:
1. **Data Provider**: Implements `DataProviding` protocol from DDGSync
2. **Adapter**: Bridges app-specific storage with provider
3. **Metadata Store**: Tracks sync state for the data type
4. **Callbacks**: `syncDidUpdateData` and `syncDidFinish` for post-sync actions

Providers are instantiated by `SyncDataProvidersSource.makeDataProviders()` when sync account is active.

### Sync Scheduling

**Automatic Triggers**:
- App launch and foreground events
- Data modifications (bookmarks saved, credentials added)
- Periodic background sync
- After error recovery

**Manual Triggers**:
- User taps "Sync Now" in preferences
- After device pairing completes
- Recovery from sync errors

Scheduling coordinated through `DDGSync.scheduler` using `Scheduling` protocol.

### Error Handling

**Error Types**:
- Network errors (offline, server unavailable)
- Authentication errors (invalid token, device removed)
- Encryption errors (key mismatch, corrupted data)
- Conflict errors (concurrent modifications)
- Validation errors (invalid data format)

**Error Handlers**: `SyncErrorHandler` and data type-specific handlers (`CredentialsCleanupErrorHandling`, etc.) handle errors and present appropriate UI.

**User Alerts**: `SyncAlertsPresenter` displays error messages and recovery actions to users.

## Common Tasks

### Testing Sync

**Debug Menu**: Access via internal builds for:
- Force sync operations
- Clear sync metadata
- View sync state and timestamps
- Inspect registered devices
- Test pairing flows

**Integration Testing**: Use multiple devices or simulators with same account to verify data synchronization.

### Debugging Sync Issues

**Check Sync State**:
- Verify `authState` is `.active`
- Check `isSyncInProgress` for ongoing operations
- Inspect `syncDailyStats` for error patterns

**Metadata Inspection**:
- Query `SyncMetadataDatabase` for sync timestamps
- Check for stale or missing metadata
- Verify last sync times per data type

**Logs**: Filter Console.app for "DDGSync" subsystem to see sync operations, errors, and data flow.

### Handling Sync Conflicts

Sync uses last-write-wins strategy with timestamps for conflict resolution:
- Each object has `modifiedAt` timestamp
- During sync, newer timestamp wins
- Metadata store tracks last successful sync per data type
- Conflicts are resolved automatically without user intervention

## Privacy and Security

### Encryption Guarantees

- All data encrypted on device before transmission
- Encryption keys never transmitted to server
- Server stores only encrypted blobs
- Only user's devices can decrypt synced data

### Key Storage

- Primary key and secret key stored in macOS Keychain
- Keychain items protected by device passcode/biometrics
- Keys never logged or exposed in debugging

### Recovery Code Security

- Recovery code contains primary key (sensitive)
- Users should store recovery code securely
- Recovery code allows full account restoration
- Lost recovery code requires creating new sync account

### Device Management

- Users can view all connected devices
- Can remove devices remotely (invalidates device token)
- Removed devices lose access to synced data
- Device removal propagates on next sync

## Related Topics

- <doc:BookmarksAndHistory> - Bookmark data structure and storage
- <doc:Preferences> - Settings UI and sync preferences
- Secure Vault - Credential and payment information encryption

