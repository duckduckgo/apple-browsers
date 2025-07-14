---
alwaysApply: true
title: "Privacy & Security Guidelines"
description: "Privacy and security guidelines for DuckDuckGo browser development with privacy-by-design principles"
keywords: ["privacy", "security", "keychain", "data protection", "HTTPS", "authentication", "content blocking", "cookies"]
---

# Privacy & Security Guidelines

## Core Principles

### Privacy by Design
- Never collect or transmit user data without explicit consent
- All features must have privacy implications documented
- Default to the most private option
- Implement data minimization - only collect what's absolutely necessary

### Secure Storage
```swift
// Use Keychain for sensitive data
let keychainService = KeychainService()
try keychainService.store(password, for: account)

// Use encrypted Core Data for sensitive persistent data
let container = NSPersistentContainer(name: "SecureData")
container.persistentStoreDescriptions.forEach { storeDescription in
    storeDescription.setOption(true as NSNumber, forKey: NSPersistentHistoryTrackingKey)
    storeDescription.setOption(FileProtectionType.complete as NSObject, forKey: NSPersistentStoreFileProtectionKey)
}
```

## Data Handling

### User Data Classification
1. **Sensitive Data**: Passwords, credentials, personal information
   - Must use Keychain or encrypted storage
   - Never log or transmit in plain text
   - Clear on app logout/uninstall

2. **Private Data**: Browsing history, bookmarks, settings
   - Store locally only
   - Implement proper data clearing
   - Respect fireproofing settings

3. **Anonymous Data**: Crash reports, usage statistics
   - Only collect with user consent
   - Strip all identifying information
   - Use differential privacy where applicable

### Network Security
```swift
// Always use HTTPS
guard url.scheme == "https" else {
    throw NetworkError.insecureConnection
}

// Implement certificate pinning for critical endpoints
let pinnedCertificates = [
    "duckduckgo.com": "SHA256:XXXXXXXXXX"
]

// Validate all external inputs
func validateInput(_ input: String) -> Bool {
    // Implement proper validation
    return input.matches(allowedPattern)
}
```

## Content Blocking

### Tracker Protection
```swift
// Use TrackerRadarKit for blocking
let trackerDataSet = TrackerDataSet(data: trackerData)
let contentBlocker = ContentBlocker(trackerDataSet: trackerDataSet)

// Apply blocking rules
webView.configuration.userContentController.add(contentBlocker.makeBlockingRules())
```

### Cookie Management
```swift
// Clear cookies on demand
HTTPCookieStorage.shared.removeCookies(since: Date.distantPast)
WKWebsiteDataStore.default().removeData(ofTypes: [WKWebsiteDataTypeCookies], 
                                       modifiedSince: Date.distantPast)

// Implement fireproofing
let fireproofedDomains = FireproofingManager.shared.fireproofedDomains
// Preserve cookies only for fireproofed domains
```

## Authentication & Authorization

### Biometric Authentication
```swift
// Use LocalAuthentication for sensitive operations
let context = LAContext()
context.evaluatePolicy(.deviceOwnerAuthentication, 
                      localizedReason: "Authenticate to access your passwords") { success, error in
    if success {
        // Grant access
    } else {
        // Handle authentication failure
    }
}
```

### Credential Management
```swift
// Never store passwords in plain text
// Use AutofillCredentialProvider for password management
let credential = ASPasswordCredential(user: username, password: password)
ASCredentialIdentityStore.shared.saveCredentialIdentities([credential])
```

## Error Handling

### Secure Error Messages
```swift
// Don't expose sensitive information in errors
// Bad
throw NetworkError.authenticationFailed(username: user.email)

// Good
throw NetworkError.authenticationFailed

// Log securely
Logger.log(.error, "Authentication failed for user", 
          parameters: ["userId": user.anonymizedId])
```

## Code Security

### Input Validation
```swift
extension String {
    var sanitizedForWeb: String {
        // Remove potentially dangerous characters
        return self.replacingOccurrences(of: "<", with: "&lt;")
                   .replacingOccurrences(of: ">", with: "&gt;")
                   .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
```

### Secure Defaults
```swift
struct PrivacySettings {
    var blockTrackers = true  // Default to blocking
    var httpsEverywhere = true  // Default to HTTPS
    var sendDiagnostics = false  // Default to no data collection
    var saveHistory = false  // Default to no history
}
```

## Testing Security

### Security Test Cases
```swift
func testSensitiveDataNotLogged() {
    let password = "secret123"
    authenticator.login(password: password)
    
    XCTAssertFalse(logOutput.contains(password))
}

func testDataEncryption() {
    let sensitiveData = "user information"
    let encrypted = encryptor.encrypt(sensitiveData)
    
    XCTAssertNotEqual(encrypted, sensitiveData)
    XCTAssertEqual(encryptor.decrypt(encrypted), sensitiveData)
}
```

## Review Checklist

Before committing code, ensure:
- [ ] No hardcoded secrets or API keys
- [ ] All user data is properly classified and protected
- [ ] Network requests use HTTPS
- [ ] Input validation is implemented
- [ ] Error messages don't leak sensitive information
- [ ] Logging doesn't include PII
- [ ] Data clearing mechanisms are tested
- [ ] Privacy impact has been assessed