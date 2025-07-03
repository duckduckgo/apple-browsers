# BrowserServicesKit

## Overview
BrowserServicesKit is the core shared library that provides essential browser functionality to both the iOS and macOS DuckDuckGo applications. It encapsulates privacy features, data management, and browser-specific utilities in a platform-agnostic way.

## Purpose
This package serves as the foundation for DuckDuckGo's browser applications, ensuring consistent behavior and code reuse across platforms while maintaining privacy as the primary focus.


## Key Components

### Privacy & Protection
- **ContentBlocking** (`Sources/ContentBlocking/`)
  - Tracker blocking rules and implementation
  - Ad blocking functionality
  - Cookie management
  - Request filtering

- **PrivacyConfig** (`Sources/PrivacyConfig/`)
  - Remote configuration for privacy features
  - Feature flags and experiments
  - Privacy protection settings

- **MaliciousSiteProtection** (`Sources/MaliciousSiteProtection/`)
  - Phishing site detection
  - Malware site blocking
  - Safe browsing implementation

- **PrivacyDashboard** (`Sources/PrivacyDashboard/`)
  - UI components for displaying privacy information
  - Tracker visualization
  - Protection status indicators

### Data Management
- **Bookmarks** (`Sources/Bookmarks/`)
  - Bookmark storage and retrieval
  - Folder management
  - Import/export functionality
  - Favorites support

- **History** (`Sources/History/`)
  - Browsing history storage
  - History search and filtering
  - Privacy-conscious history management

- **SecureVault** (`Sources/SecureVault/`)
  - Encrypted credential storage
  - Password management
  - Secure notes functionality
  - Keychain integration

- **DDGSync** (`Sources/DDGSync/`)
  - End-to-end encrypted sync
  - Device pairing
  - Data conflict resolution
  - Sync status management

### Browser Functionality
- **Navigation** (`Sources/Navigation/`)
  - URL handling and validation
  - Navigation state management
  - Redirect handling
  - Deep link support

- **UserScript** (`Sources/UserScript/`)
  - JavaScript injection framework
  - Content script management
  - Message passing between native and web
  - Script sandboxing

- **Autofill** (`Sources/Autofill/`)
  - Form detection and filling
  - Credit card autofill
  - Identity autofill
  - Password generation

### Utilities
- **Common** (`Sources/Common/`)
  - Shared extensions and utilities
  - Error handling
  - Logging framework
  - Common data structures

- **Persistence** (`Sources/Persistence/`)
  - Core Data utilities
  - Database management
  - Migration support
  - Data model definitions

- **Networking** (`Sources/Networking/`)
  - HTTP client utilities
  - API communication
  - Certificate pinning
  - Network monitoring

- **Configuration** (`Sources/Configuration/`)
  - App configuration management
  - Environment settings
  - Build configuration support

### Special Features
- **RemoteMessaging** (`Sources/RemoteMessaging/`)
  - In-app messaging system
  - User notifications
  - Feature announcements

- **SpecialErrorPages** (`Sources/SpecialErrorPages/`)
  - Custom error page generation
  - SSL error handling
  - Network error pages

- **Subscription** (`Sources/Subscription/`)
  - Subscription management
  - Purchase validation
  - Feature gating
  - @Sources/Subscription/CLAUDE.md

## Architecture

### Design Principles
1. **Privacy First**: All features designed with user privacy as the primary concern
2. **Platform Agnostic**: Core logic independent of iOS/macOS specifics
3. **Modular**: Each component can be used independently
4. **Testable**: Comprehensive test coverage with dependency injection
5. **Performance**: Optimized for mobile and desktop constraints

### Dependencies
- **Swift Package Manager**: Package definition in `Package.swift`
- **External Dependencies**: Minimal, privacy-reviewed third-party dependencies
- **Platform Dependencies**: Abstracted through protocols and adapters

## Usage in Client Apps

### iOS Integration
The iOS app uses BrowserServicesKit for:
- Web view content blocking
- Bookmark and history management
- Autofill in web forms
- Privacy dashboard displays
- Secure credential storage

Reference: [iOS Documentation](../../iOS/CLAUDE.md)

### macOS Integration
The macOS app uses BrowserServicesKit for:
- Advanced content blocking
- Multi-window bookmark management
- System-wide autofill
- Detailed privacy reporting
- Cross-device sync

Reference: [macOS Documentation](../../macOS/CLAUDE.md)

## Development Guidelines

### Adding New Features
1. Determine if the feature belongs in BrowserServicesKit (shared) or platform-specific code
2. Create a new module in the appropriate directory
3. Define platform-agnostic interfaces
4. Implement with privacy considerations
5. Add comprehensive tests

### Testing
- Unit tests for each module
- Integration tests for cross-module functionality
- Mock implementations for platform-specific features
- Privacy-focused test scenarios

### Code Organization
```
Sources/
├── ModuleName/
│   ├── Public/           # Public API
│   ├── Internal/         # Internal implementation
│   ├── Models/          # Data models
│   └── Extensions/      # Type extensions
Tests/
└── ModuleNameTests/     # Test files
```

### Best Practices
1. Keep platform-specific code out of BrowserServicesKit
2. Use dependency injection for testability
3. Document public APIs thoroughly
4. Consider privacy implications for all features
5. Maintain backward compatibility
6. Write comprehensive unit tests for new features
7. Follow existing code patterns and conventions

## Key APIs

### ContentBlocking
```swift
ContentBlockingManager.shared.enable(rules: ...)
ContentBlockingManager.shared.exceptions(for: domain)
```

### Bookmarks
```swift
BookmarksManager.shared.save(bookmark: ...)
BookmarksManager.shared.getAllBookmarks()
```

### SecureVault
```swift
SecureVault.shared.storeCredentials(...)
SecureVault.shared.retrieveCredentials(for: domain)
```

### Privacy Dashboard
```swift
PrivacyDashboardController.show(for: pageData)
```

## Performance Considerations
- Lazy loading of resources
- Efficient content blocking rule compilation
- Optimized database queries
- Memory-conscious caching strategies

## Privacy & Security
- No user data leaves the device without encryption
- All storage is encrypted at rest
- No third-party analytics or tracking
- Regular security audits
- Privacy-preserving crash reporting

## Future Considerations
- Continued modularization of existing features
- Enhanced sync capabilities with improved conflict resolution
- Additional privacy features for emerging threats
- Performance optimizations for resource-constrained devices
- Extended platform support for new operating systems
- Improved testing infrastructure and coverage