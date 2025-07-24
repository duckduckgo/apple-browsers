---
alwaysApply: false
title: "SecureVault Implementation Guidelines"
description: "Guidelines for using SecureVault, DuckDuckGo's secure storage system built on GRDB with SQLCipher encryption, including database setup, AppGroup sharing, and performance considerations"
keywords: ["SecureVault", "GRDB", "SQLCipher", "secure storage", "database", "AppGroup", "encryption", "BackgroundTask", "ExpiringActivity", "iOS", "macOS"]
---

# SecureVault Implementation Guidelines

## Introduction

These guidelines encapsulate vital information for using SecureVault in our application. SecureVault is our secure storage system built on GRDB with SQLCipher encryption, providing a layered security approach for sensitive data.

For general GRDB knowledge, refer to [GRDB documentation](https://github.com/groue/GRDB.swift). This guide covers DuckDuckGo-specific patterns and requirements.

## Essential Knowledge

### SecureVault Architecture Overview

SecureVault is a protocol-based system that provides:

- **L0**: Not encrypted (currently unused)
- **L1**: Secret key encrypted (usernames, domains, duck addresses)
- **L2**: User password encrypted with time-based access (user passwords)
- **L3**: User password required at request time (future: credit cards, sensitive data)

```swift
// Core SecureVault protocol pattern
public protocol SecureVault {
    associatedtype DatabaseProvider: SecureStorageDatabaseProvider
    init(providers: SecureStorageProviders<DatabaseProvider>)
}

// Example: AutofillSecureVault implementation
public protocol AutofillSecureVault: SecureVault {
    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64
    func websiteCredentialsFor(domain: String) throws -> [SecureVaultModels.WebsiteCredentials]
    // ... other autofill-specific methods
}
```

## Database Location and Setup

### Choosing the Database Location

**Important Note**: If you need to share the Database through AppGroup, please refer to [Sharing Database through AppGroup](#sharing-database-through-appgroup) section below.

For typical single-app usage:
- Create a dedicated folder for the database file
- This helps separate it from other files and makes file coordination easier
- Makes future migration simpler if needed

```swift
// Example database location setup
let databaseDirectory = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("SecureVault")

try FileManager.default.createDirectory(at: databaseDirectory, 
                                       withIntermediateDirectories: true)

let databaseURL = databaseDirectory.appendingPathComponent("vault.sqlite")
```

### Database Configuration

The simplest and best (future-proof) way to setup database is to use the following configuration:

```swift
var config = Configuration()
config.prepareDatabase { database in
    try database.usePassphrase(key)
    try database.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
}
```

**Why the PRAGMA statement?**
- This PRAGMA enables sharing databases across App Groups
- It has no negative impact when used for single-app scenarios
- Setting it upfront makes future AppGroup sharing easier
- For details, see [iOS] Requirements to store Vault in AppGroup Container

### Choosing DatabaseWriter

GRDB operates with two possible writers:

#### DatabaseQueue
- **Single writer, single reader**
- Simpler configuration
- Suitable for single-threaded access

#### DatabasePool  
- **Single writer, multiple readers**
- Enables WAL mode on SQLite file
- Better performance for multi-threaded access

```swift
// DatabaseQueue example
let queue = try DatabaseQueue(path: databaseURL.path, configuration: config)

// DatabasePool example  
let pool = try DatabasePool(path: databaseURL.path, configuration: config)
```

**Decision criteria:**
- Single thread access (e.g., UserScripts only): Either option works
- Multi-threaded access: Use `DatabasePool` for better performance

## SecureVault Instance Management

### ✅ CORRECT: Single Instance Pattern

> GRDB documentation is extremely clear on the topic:
> "Open one single DatabaseQueue or DatabasePool per database file, for the whole duration of your use of the database. Not for the duration of each database access, but really for the duration of all database accesses to this file."

**Follow DuckDuckGo patterns**: Combine this with [✓ Approved] Avoiding static vars and singletons:

```swift
// ✅ CORRECT: Factory pattern with dependency injection
public let AutofillSecureVaultFactory: AutofillVaultFactory = SecureVaultFactory<DefaultAutofillSecureVault>(
    makeCryptoProvider: {
        return AutofillCryptoProvider()
    }, 
    makeKeyStoreProvider: { reporter in
        return AutofillKeyStoreProvider(reporter: reporter)
    }, 
    makeDatabaseProvider: { key, _ in
        return try DefaultAutofillDatabaseProvider(key: key)
    }
)

// Usage in ViewModels via dependency injection
final class MyFeatureViewModel: ObservableObject {
    private let vault: any AutofillSecureVault
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.vault = dependencies.autofillSecureVault
    }
}
```

### ❌ AVOID: Multiple Instances

```swift
// ❌ DON'T DO THIS - creates multiple instances
func someMethod() {
    let vault1 = try AutofillSecureVaultFactory.makeVault(reporter: nil)
    // ... later in another method
    let vault2 = try AutofillSecureVaultFactory.makeVault(reporter: nil)
    // This can cause database corruption and performance issues
}
```

## Sharing Database through AppGroup

Since we've started sharing SecureVault (GRDB) in AppGroup with the intention of using system-wide extensions to access it, there are important considerations and requirements.

### Side Effects and Challenges

When sharing across App Groups, you must handle:

1. **File-access constraints**: Multiple processes accessing simultaneously
2. **System file lock constraints**: OS monitors SQLite access locks
3. **WAL mode performance**: Proper setup for read/write performance  
4. **Persistent WAL**: Correct read-only access between processes

### Critical Setup Requirements

#### 1. Database Configuration for AppGroup

```swift
var config = Configuration()
config.prepareDatabase { database in
    try database.usePassphrase(key)
    // MANDATORY for AppGroup sharing
    try database.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
    // Additional AppGroup optimizations
    try database.execute(sql: "PRAGMA wal_checkpoint = TRUNCATE")
}

// Use DatabasePool for AppGroup scenarios
let pool = try DatabasePool(path: sharedDatabaseURL.path, configuration: config)
```

#### 2. Background Task Management

**Critical**: Extend host app lifecycle to prevent 0xdead10cc crashes:

```swift
// ✅ REQUIRED: Use BackgroundTask during database operations
func performDatabaseOperation() async {
    let backgroundTask = await UIApplication.shared.beginBackgroundTask(withName: "SecureVault Operation") {
        // Cleanup if needed
    }
    
    defer {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }
    
    // Perform your database operations here
    try await vault.performOperation()
}
```

#### 3. Using ExpiringActivity (Alternative)

For more sophisticated background management:

```swift
import ActivityKit

func performDatabaseOperationWithActivity() async {
    let activity = try? Activity<DatabaseActivityAttributes>.request(
        attributes: DatabaseActivityAttributes(),
        content: .init(state: .active),
        pushToken: nil
    )
    
    defer {
        Task {
            await activity?.end()
        }
    }
    
    // Database operations
    try await vault.performOperation()
}
```

### Crash Prevention: 0xdead10cc

**Problem**: App crashes with `Termination Reason: RUNNINGBOARD 0xdead10cc` when:
- App transitions from Background to Suspended state
- Database locks are still held
- Extensions need database access

**Solution**: Always use background tasks or expiring activities during database operations in AppGroup scenarios.

## Performance Optimization

### WAL Mode Optimization

```swift
// Optimize WAL checkpoints for AppGroup usage
config.prepareDatabase { database in
    try database.usePassphrase(key)
    try database.execute(sql: "PRAGMA cipher_plaintext_header_size = 32")
    
    // Performance optimizations
    try database.execute(sql: "PRAGMA journal_mode = WAL")
    try database.execute(sql: "PRAGMA synchronous = NORMAL") 
    try database.execute(sql: "PRAGMA cache_size = -16384") // 16MB cache
    try database.execute(sql: "PRAGMA temp_store = MEMORY")
}
```

### Efficient Database Operations

```swift
// ✅ GOOD: Batch operations
try vault.inDatabaseTransaction { database in
    for credential in credentials {
        try vault.storeWebsiteCredentials(credential, in: database)
    }
}

// ❌ AVOID: Individual transactions
for credential in credentials {
    try vault.storeWebsiteCredentials(credential) // Creates separate transaction each time
}
```

## Encryption and Security

### Multi-Layer Encryption Implementation

```swift
public class DefaultAutofillSecureVault<T: AutofillDatabaseProvider>: AutofillSecureVault {
    
    // L1: Secret key encryption (stored in Keychain)
    private func l1Encrypt(data: Data) throws -> Data {
        let l1Key = try providers.keystore.l1Key()
        return try providers.crypto.encrypt(data, withKey: l1Key)
    }
    
    // L2: User password encryption (with expiring access)
    private func l2Encrypt(data: Data, using l2Key: Data? = nil) throws -> Data {
        let key: Data = try {
            if let l2Key {
                return l2Key
            }
            let password = try passwordInUse()
            return try l2KeyFrom(password: password)
        }()
        return try providers.crypto.encrypt(data, withKey: key)
    }
    
    // Password-based access with expiration
    public func authWith(password: Data) throws -> any AutofillSecureVault {
        lock.lock()
        defer { lock.unlock() }
        
        do {
            _ = try self.l2KeyFrom(password: password) // Validates password
            self.expiringPassword.value = password
            return self
        } catch {
            let error = error as? SecureStorageError ?? .authError(cause: error)
            throw error
        }
    }
}
```

### Password Management

```swift
// Secure password reset
public func resetL2Password(oldPassword: Data?, newPassword: Data) throws {
    lock.lock()
    defer { lock.unlock() }
    
    // Force re-auth on future calls
    self.expiringPassword.value = nil
    
    do {
        // Use provided old password or stored generated password
        let generatedPassword = try self.providers.keystore.generatedPassword()
        guard let oldPassword = oldPassword ?? generatedPassword else {
            throw SecureStorageError.invalidPassword
        }
        
        // Get decrypted L2 key using old password
        let l2Key = try self.l2KeyFrom(password: oldPassword)
        
        // Derive new encryption key
        let newEncryptionKey = try self.providers.crypto.deriveKeyFromPassword(newPassword)
        
        // Encrypt L2 key with new encryption key
        let encryptedKey = try self.providers.crypto.encrypt(l2Key, withKey: newEncryptionKey)
        
        // Store encrypted L2 key
        try self.providers.keystore.storeEncryptedL2Key(encryptedKey)
        
        // Clear generated password
        try self.providers.keystore.clearGeneratedPassword()
    } catch {
        if let error = error as? SecureStorageError {
            throw error
        } else {
            throw SecureStorageError.databaseError(cause: error)
        }
    }
}
```

## Testing Patterns

### Mock SecureVault Implementation

```swift
// ✅ FOLLOW: Use existing mock patterns
typealias MockVaultFactory = SecureVaultFactory<MockSecureVault<MockDatabaseProvider>>

let MockSecureVaultFactory = SecureVaultFactory<MockSecureVault>(
    makeCryptoProvider: {
        let provider = MockCryptoProvider()
        provider._derivedKey = "derived".data(using: .utf8)
        return provider
    }, 
    makeKeyStoreProvider: { _ in
        let provider = MockKeyStoreProvider()
        provider._l1Key = "key".data(using: .utf8)
        return provider
    }, 
    makeDatabaseProvider: { key, _ in
        return try MockDatabaseProvider(key: key)
    }
)

// Usage in tests
final class MockSecureVault<T: AutofillDatabaseProvider>: AutofillSecureVault {
    var storedAccounts: [SecureVaultModels.WebsiteAccount] = []
    var storedCredentials: [Int64: SecureVaultModels.WebsiteCredentials] = [:]
    
    // Simplified implementations for testing
    func encrypt(_ data: Data, using key: Data) throws -> Data { data }
    func decrypt(_ data: Data, using key: Data) throws -> Data { data }
    
    // Test-specific storage
    func storeWebsiteCredentials(_ credentials: SecureVaultModels.WebsiteCredentials) throws -> Int64 {
        let id = Int64(storedCredentials.count + 1)
        storedCredentials[id] = credentials
        if let account = credentials.account {
            storedAccounts.append(account)
        }
        return id
    }
}
```

### Testing Database Operations

```swift
func testSecureVaultStorage() async throws {
    let vault = try MockSecureVaultFactory.makeVault(reporter: nil)
    
    let account = SecureVaultModels.WebsiteAccount(
        title: "Test Site",
        username: "testuser",
        domain: "example.com"
    )
    
    let credentials = SecureVaultModels.WebsiteCredentials(
        account: account,
        password: "testpassword".data(using: .utf8)
    )
    
    // Test storage
    let storedId = try vault.storeWebsiteCredentials(credentials)
    XCTAssertGreaterThan(storedId, 0)
    
    // Test retrieval
    let retrievedCredentials = try vault.websiteCredentialsFor(domain: "example.com")
    XCTAssertEqual(retrievedCredentials.count, 1)
    XCTAssertEqual(retrievedCredentials.first?.account?.username, "testuser")
}
```

## Updating GRDB

Instead of using GRDB directly as source code, we package it into an XCFramework to speed up compilation time.

### Update Process

1. **Check the fork**: Go to our [GRDB fork](https://github.com/duckduckgo/GRDB.swift)
2. **Follow instructions**: Run the provided script to create a new release
3. **If script fails**: 
   - The script patches GRDB code that may change between releases
   - Create a task in **Apple Developer Infrastructure (CI, Releases, DevEx)** 
   - Request script fixes and new release creation

### GRDB Version Considerations

```swift
// Check current GRDB version compatibility
import GRDB

// Ensure new features/APIs are available
#if compiler(>=5.9) && canImport(GRDB, _version: 6.0)
    // Use newer GRDB features
#else
    // Fallback to older patterns
#endif
```

## Error Handling Patterns

### SecureVault-Specific Errors

```swift
// Handle authentication errors gracefully
func handleSecureVaultOperation() async {
    do {
        let data = try await vault.getSensitiveData()
        processData(data)
    } catch SecureStorageError.authRequired {
        // Prompt user for password
        await requestUserAuthentication()
    } catch SecureStorageError.invalidPassword {
        // Show password error message
        showPasswordError()
    } catch SecureStorageError.databaseError(let cause) {
        // Handle database-specific errors
        Logger.secureStorage.error("Database error: \(cause)")
        showGenericError()
    } catch {
        // Handle other errors
        Logger.secureStorage.error("Unexpected error: \(error)")
        showGenericError()
    }
}
```

### Background Access Error Handling

```swift
// Handle AppGroup background access gracefully
func performBackgroundVaultOperation() async {
    let backgroundTask = await UIApplication.shared.beginBackgroundTask(withName: "Vault Access")
    
    defer {
        if backgroundTask != .invalid {
            UIApplication.shared.endBackgroundTask(backgroundTask)
        }
    }
    
    do {
        try await vault.performOperation()
    } catch {
        // If we're in background and get access errors, defer operation
        if UIApplication.shared.applicationState == .background {
            queueOperationForForeground()
        } else {
            throw error
        }
    }
}
```

## Best Practices Summary

### ✅ DO

- Use the factory pattern with dependency injection
- Set up database configuration with AppGroup PRAGMA upfront
- Use background tasks for AppGroup database operations
- Implement proper error handling for authentication states
- Follow the single instance pattern for database writers
- Use DatabasePool for multi-threaded access
- Batch database operations when possible
- Use existing mock patterns for testing

### ❌ DON'T

- Create multiple SecureVault instances for the same database
- Perform database operations without background tasks in AppGroup scenarios
- Ignore authentication required errors
- Use force unwrapping with SecureVault operations
- Mix DatabaseQueue and DatabasePool for the same database file
- Perform individual transactions for batch operations
- Skip error handling for background access scenarios

### 🔒 Security Reminders

- Never log decrypted password data
- Always validate user passwords before storing
- Use appropriate encryption layers (L1/L2/L3) for data sensitivity
- Implement proper cleanup for background tasks
- Handle device lock scenarios gracefully
- Clear sensitive data from memory when appropriate

---

This documentation ensures secure, performant, and maintainable SecureVault implementation across the DuckDuckGo browser ecosystem. 