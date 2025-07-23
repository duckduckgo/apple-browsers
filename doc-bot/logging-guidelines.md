---
alwaysApply: false
title: "Logging Guidelines & Telemetry Capture"
description: "Logging guidelines for DuckDuckGo browser using Apple's Unified Logging System including Logger setup, subsystems, categories, log levels, privacy settings, and best practices"
keywords: ["logging", "telemetry", "Unified Logging System", "Logger", "subsystem", "category", "privacy", "debugging", "Console.app", "Sysdiagnose", "macOS Debug menu"]
---

# Logging Guidelines & Telemetry Capture

## Overview

The DuckDuckGo browser apps for iOS and macOS leverage **Apple's Unified Logging System** for capturing telemetry and debugging information. This system enables efficient tracking of app behavior, issue diagnosis, and performance monitoring in a structured and privacy-conscious manner.

**Key Benefits**:
- **Privacy-first**: Built-in privacy controls for sensitive data
- **Performance**: Optimized for minimal overhead
- **Integration**: Native Apple ecosystem support
- **Debugging**: Rich contextual information and filtering

## How to Log

### Using the Logger Class

We utilize the `Logger` class from Apple's `os` framework for all logging activities:

```swift
import os

// Basic logging examples
Logger.yourFeatureName.debug("Something to log, with info: \(infoVar)")
Logger.anotherFeatureName.error("Some error happened: \(error.localizedDescription, privacy: .public)")
Logger.networking.info("API request completed for endpoint: \(endpoint, privacy: .public)")
Logger.performance.debug("Operation took \(duration)ms to complete")
```

### Creating Custom Loggers

#### Single Feature Logger

For new features, create a dedicated logger file named `Logger+YourFeatureName.swift`:

```swift
import os

public extension Logger {
    static var yourFeatureName: Logger = { 
        Logger(subsystem: "Your Feature Name", category: "") 
    }()
    
    static var anotherFeatureName: Logger = { 
        Logger(subsystem: "Another feature name", category: "Subsystem in the feature") 
    }()
}
```

#### Multiple Feature Loggers

For related features, add to existing logger extensions (e.g., `Logger+Multiple.swift`):

```swift
import os

public extension Logger {
    // Networking loggers
    static var networking: Logger = { 
        Logger(subsystem: "Networking", category: "API") 
    }()
    
    static var cache: Logger = { 
        Logger(subsystem: "Networking", category: "Cache") 
    }()
    
    // UI loggers  
    static var tabManagement: Logger = { 
        Logger(subsystem: "UI", category: "Tab Management") 
    }()
    
    static var bookmarks: Logger = { 
        Logger(subsystem: "UI", category: "Bookmarks") 
    }()
}
```

### Logger Placement Strategy

**Framework/Package Level**: For shared functionality across iOS and macOS
```swift
// In BrowserServicesKit
public extension Logger {
    static var secureVault: Logger = { 
        Logger(subsystem: "BrowserServicesKit", category: "SecureVault") 
    }()
    
    static var sync: Logger = { 
        Logger(subsystem: "BrowserServicesKit", category: "Sync") 
    }()
}
```

**App Level**: For platform-specific features
```swift
// In iOS app
public extension Logger {
    static var widgets: Logger = { 
        Logger(subsystem: "iOS App", category: "Widgets") 
    }()
}

// In macOS app  
public extension Logger {
    static var windowManagement: Logger = { 
        Logger(subsystem: "macOS App", category: "Window Management") 
    }()
}
```

## Subsystem and Category Guidelines

### Subsystem Naming

**Purpose**: Corresponds to large functional areas of your app

**Examples**:
- `"Networking"` - All network-related functionality
- `"UI"` - User interface components
- `"Data Storage"` - Database and persistence
- `"Security"` - Authentication and encryption
- `"Performance"` - Performance monitoring and optimization

### Category Naming

**Purpose**: Specific components or features within subsystems

**Examples**:
```swift
// Networking subsystem categories
Logger(subsystem: "Networking", category: "API Calls")
Logger(subsystem: "Networking", category: "Cache Management")
Logger(subsystem: "Networking", category: "Request Retry")

// UI subsystem categories  
Logger(subsystem: "UI", category: "Tab Management")
Logger(subsystem: "UI", category: "Settings")
Logger(subsystem: "UI", category: "Bookmarks")

// Data Storage subsystem categories
Logger(subsystem: "Data Storage", category: "SecureVault")
Logger(subsystem: "Data Storage", category: "Core Data")
Logger(subsystem: "Data Storage", category: "User Defaults")
```

## Log Levels and Privacy

### Choosing Log Levels

#### `debug` - Development and Troubleshooting
- **Purpose**: Verbose output for development debugging
- **Retention**: Short-lived in memory
- **Use cases**: Variable values, execution flow, temporary debugging

```swift
Logger.networking.debug("Request headers: \(headers)")
Logger.ui.debug("User tapped button at coordinates: \(point)")
Logger.performance.debug("Cache hit for key: \(key)")
```

#### `info` - Important Events
- **Purpose**: Interesting or important information
- **Retention**: Longer than debug, available for analysis
- **Use cases**: User actions, system state changes, feature usage

```swift
Logger.auth.info("User successfully authenticated")
Logger.sync.info("Sync operation completed with \(itemCount) items")
Logger.features.info("Feature flag \(flagName, privacy: .public) enabled")
```

#### `error` - Handled Errors
- **Purpose**: Something went wrong but was handled gracefully
- **Retention**: Available for longer-term analysis
- **Requirements**: Always include `error.localizedDescription`

```swift
Logger.networking.error("API request failed: \(error.localizedDescription, privacy: .public)")
Logger.database.error("Failed to save context: \(error.localizedDescription, privacy: .public)")
Logger.auth.error("Keychain access denied: \(error.localizedDescription, privacy: .public)")
```

#### `fault` - Critical Issues
- **Purpose**: Critical issues preventing normal app function
- **Retention**: Highest priority, always preserved
- **Requirements**: Include error description when available

```swift
Logger.database.fault("Database corruption detected: \(error.localizedDescription, privacy: .public)")
Logger.security.fault("Critical security violation: \(details, privacy: .public)")
Logger.system.fault("App unable to initialize required services")
```

### Privacy Settings

#### Default Privacy Behavior

**All interpolated values are `.private` by default** - only visible in debug builds:

```swift
// These values are private by default
Logger.auth.info("User \(username) logged in")  // username is private
Logger.network.debug("Response time: \(responseTime)ms")  // responseTime is private
```

#### Public Information

Mark non-sensitive information as `.public` for visibility in release builds:

```swift
// Error descriptions should typically be public
Logger.network.error("Connection failed: \(error.localizedDescription, privacy: .public)")

// System information can be public
Logger.performance.info("App launched in \(launchTime, privacy: .public)ms")

// Feature flags and settings (non-PII) can be public
Logger.features.info("Dark mode: \(isDarkMode, privacy: .public)")
```

#### Privacy Decision Matrix

| Data Type | Privacy Level | Example |
|-----------|---------------|---------|
| **User PII** | `.private` (default) | Email, username, personal data |
| **Error descriptions** | `.public` | `error.localizedDescription` |
| **System metrics** | `.public` | Performance timings, counts |
| **Feature states** | `.public` | Feature flags, app settings |
| **Debug values** | `.private` (default) | Variable contents, internal state |

## Best Practices

### ✅ DO

#### Direct Logging
```swift
// ✅ CORRECT: Log directly where events occur
func authenticateUser() {
    Logger.auth.info("Starting user authentication")
    
    do {
        let result = try performAuthentication()
        Logger.auth.info("Authentication successful")
    } catch {
        Logger.auth.error("Authentication failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

#### Meaningful Context
```swift
// ✅ CORRECT: Include relevant context
Logger.sync.info("Sync completed: \(syncedItems, privacy: .public) items, \(conflicts, privacy: .public) conflicts")
Logger.network.debug("Cache hit for URL: \(url.absoluteString, privacy: .public)")
Logger.ui.debug("View controller \(type(of: self)) appeared")
```

#### Consistent Logger Usage
```swift
// ✅ CORRECT: Use established loggers consistently
extension BookmarkManager {
    func addBookmark(_ bookmark: Bookmark) {
        Logger.bookmarks.info("Adding bookmark: \(bookmark.title ?? "Untitled")")
        // Implementation
    }
    
    func deleteBookmark(_ bookmark: Bookmark) {
        Logger.bookmarks.info("Deleting bookmark: \(bookmark.title ?? "Untitled")")
        // Implementation
    }
}
```

### ❌ DON'T

#### Wrapper Functions
```swift
// ❌ AVOID: Wrapper functions obscure context
func logError(_ message: String) {
    Logger.general.error("\(message)")  // Loses class, line number context
}

// Use direct logging instead
Logger.networking.error("Connection timeout: \(error.localizedDescription, privacy: .public)")
```

#### Logger Injection
```swift
// ❌ AVOID: Injecting loggers
class NetworkManager {
    private let logger: Logger
    
    init(logger: Logger) {  // Unnecessary complexity
        self.logger = logger
    }
}

// ✅ CORRECT: Use global logger extensions
class NetworkManager {
    func performRequest() {
        Logger.networking.info("Starting network request")
    }
}
```

#### Overly Verbose Debug Logging
```swift
// ❌ AVOID: Too much debug noise
func processItems(_ items: [Item]) {
    Logger.processing.debug("Starting to process items")
    for item in items {
        Logger.processing.debug("Processing item: \(item.id)")
        Logger.processing.debug("Item name: \(item.name)")
        Logger.processing.debug("Item processed successfully")
    }
    Logger.processing.debug("Finished processing all items")
}

// ✅ CORRECT: Focused, meaningful debug logs
func processItems(_ items: [Item]) {
    Logger.processing.debug("Processing \(items.count) items")
    // Process items...
    Logger.processing.debug("Item processing completed")
}
```

## Reading and Filtering Logs

### 1. Xcode Console

**Best for**: App-specific debugging during development

#### Setup for Optimal Readability

1. **Add columns**: Type, Library, Subsystem, Category
2. **Filter by process**: Your app name
3. **Use contextual menu**: Show/Hide specific log types

#### Console Filtering

```
// Filter by subsystem
subsystem:com.yourapp.Networking

// Filter by category  
category:API

// Hide system noise
subsystem:com.apple. (!contains)

// Show only errors and faults
type:error OR type:fault
```

### 2. Console.app

**Best for**: System-wide debugging and cross-app analysis

#### Recommended Filters for DuckDuckGo

```
// Focus on DuckDuckGo process
process:duckduckgo (contains)

// Hide system noise
subsystem:com.apple. (!contains)
subsystem:PrototypeTools (!contains)
library:Security (!contains)
library:TextInput (!contains)

// Show specific subsystems
subsystem:Networking (contains)
subsystem:UI (contains)
```

#### Advanced Filtering Examples

```
// Errors in the last hour
type:error AND time:>-1h

// Specific feature debugging
subsystem:BrowserServicesKit AND category:SecureVault

// Performance monitoring
message:performance (contains) AND type:info
```

### 3. Command Line Tool

**Best for**: Scripting and automated analysis

#### Basic Usage

```bash
# Show logs for specific subsystem
log show --predicate 'subsystem == "com.duckduckgo.Networking"' --info

# Show recent errors
log show --predicate 'messageType == "Error"' --last 1h

# Export logs to file
log show --predicate 'process == "DuckDuckGo"' --start '2024-01-01 00:00:00' > app_logs.txt

# Real-time streaming
log stream --predicate 'subsystem == "com.duckduckgo.UI"'
```

#### Advanced Command Examples

```bash
# Debugging specific feature
log show --predicate 'subsystem == "BrowserServicesKit" AND category == "SecureVault"' --debug

# Performance analysis
log show --predicate 'message CONTAINS "performance"' --info --last 24h

# Error analysis with context
log show --predicate 'messageType >= "Error"' --info --start '2024-01-01'

# Multiple conditions
log show --predicate 'subsystem BEGINSWITH "com.duckduckgo" AND messageType == "Error"' --last 2h
```

### 4. Sysdiagnose

**Best for**: Remote debugging and Apple DTS submissions

#### What's Included
- Complete system snapshot
- All system and app logs
- Memory usage data
- Kernel information
- Crash reports
- Network status
- Performance data

#### Usage
```bash
# Generate sysdiagnose
sudo sysdiagnose

# The generated file can be analyzed with Console.app
# Located in /var/tmp/ or Desktop
```

## Log Export for Internal Users

### macOS Debug Menu Export

**Available to**: Internal users only  
**Platform**: macOS only

#### How to Export

1. Open **Debug menu**
2. Navigate to **Logging** > **Export logs**
3. Logs are exported as a ZIP file to Desktop
4. Includes filtered logs based on app subsystems

#### Export Contents

The exported ZIP contains:
- App-specific logs filtered by subsystem
- Recent system logs relevant to the app
- Crash reports if available
- Basic system information

## Logging Patterns by Feature

### Authentication & Security

```swift
public extension Logger {
    static var auth: Logger = { Logger(subsystem: "Security", category: "Authentication") }()
    static var keychain: Logger = { Logger(subsystem: "Security", category: "Keychain") }()
    static var encryption: Logger = { Logger(subsystem: "Security", category: "Encryption") }()
}

// Usage examples
Logger.auth.info("User authentication attempt")
Logger.keychain.error("Keychain access failed: \(error.localizedDescription, privacy: .public)")
Logger.encryption.debug("Encrypting data with algorithm: \(algorithm, privacy: .public)")
```

### Networking & API

```swift
public extension Logger {
    static var networking: Logger = { Logger(subsystem: "Networking", category: "HTTP") }()
    static var api: Logger = { Logger(subsystem: "Networking", category: "API") }()
    static var cache: Logger = { Logger(subsystem: "Networking", category: "Cache") }()
}

// Usage examples
Logger.networking.info("HTTP request to \(endpoint, privacy: .public)")
Logger.api.error("API call failed: \(error.localizedDescription, privacy: .public)")
Logger.cache.debug("Cache hit for key: \(cacheKey)")
```

### Data & Storage

```swift
public extension Logger {
    static var database: Logger = { Logger(subsystem: "Data Storage", category: "Core Data") }()
    static var secureVault: Logger = { Logger(subsystem: "Data Storage", category: "SecureVault") }()
    static var sync: Logger = { Logger(subsystem: "Data Storage", category: "Sync") }()
}

// Usage examples
Logger.database.info("Core Data migration completed")
Logger.secureVault.error("SecureVault operation failed: \(error.localizedDescription, privacy: .public)")
Logger.sync.info("Sync completed: \(itemCount, privacy: .public) items")
```

### Performance Monitoring

```swift
public extension Logger {
    static var performance: Logger = { Logger(subsystem: "Performance", category: "Metrics") }()
    static var memory: Logger = { Logger(subsystem: "Performance", category: "Memory") }()
    static var startup: Logger = { Logger(subsystem: "Performance", category: "Startup") }()
}

// Usage examples
Logger.performance.info("Operation completed in \(duration, privacy: .public)ms")
Logger.memory.debug("Memory usage: \(memoryUsage, privacy: .public)MB")
Logger.startup.info("App launch completed in \(launchTime, privacy: .public)ms")
```

## Integration with App Lifecycle

### State Machine Logging

```swift
// In app lifecycle state machine
class Launching {
    func init() {
        Logger.lifecycle.info("App entering Launching state")
        // Initialization logic
        Logger.lifecycle.info("Launching state completed")
    }
}

class Foreground {
    func onTransition() {
        Logger.lifecycle.info("App transitioning to Foreground")
    }
    
    func didReturn() {
        Logger.lifecycle.info("App returned to Foreground state")
    }
}
```

### Service Lifecycle Logging

```swift
class MyService {
    func start() {
        Logger.services.info("Starting \(type(of: self)) service")
        // Service startup logic
    }
    
    func stop() {
        Logger.services.info("Stopping \(type(of: self)) service")
        // Service cleanup logic
    }
}
```

---

Following these logging guidelines ensures consistent, privacy-conscious, and effective telemetry capture across the DuckDuckGo browser ecosystem, enabling better debugging, monitoring, and user experience optimization. 