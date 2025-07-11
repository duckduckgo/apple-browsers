---
title: "Project Structure & Organization"
description: "DuckDuckGo browser project structure, dependencies, build configuration, and development setup for iOS and macOS"
keywords: ["project structure", "dependencies", "build configuration", "iOS", "macOS", "Xcode", "Swift Package Manager", "workspace"]
alwaysApply: false
---

# Project Structure & Organization

## Workspace Structure

### Root Level
```
DuckDuckGo.xcworkspace/          # Main workspace (ALWAYS open this)
├── iOS/                         # iOS app target
├── macOS/                       # macOS app target
├── SharedPackages/              # Cross-platform Swift packages
├── doc-bot/                     # Development documentation
├── fastlane/                    # CI/CD automation
└── README.md                    # Main project documentation
```

### iOS App Structure
```
iOS/
├── DuckDuckGo/                  # Main iOS app
│   ├── AppDelegate.swift        # App lifecycle
│   ├── MainViewController.swift # Primary browser interface
│   ├── BrowserTab.swift        # Tab state and WebKit integration
│   ├── AIChat/                 # AI chat integration
│   ├── AppLifecycle/           # App lifecycle management
│   ├── Autofill/               # Form autofill features
│   ├── Bookmarks/              # Bookmark management
│   ├── BrowsingMenu/           # Browser menu UI
│   ├── Configuration/          # App configuration
│   ├── DataImport/             # Data import utilities
│   ├── HealthKitReporting/     # Health data reporting
│   ├── MainWindow/             # Main window controllers
│   ├── Subscription/           # Premium features
│   ├── SyncPrompt/             # Sync feature prompts
│   ├── TabSwitcher/            # Tab switching UI
│   └── WebView/                # Web view management
├── Core/                       # iOS-specific shared utilities
├── AutofillCredentialProvider/ # Password autofill extension
├── PacketTunnelProvider/       # VPN network extension
├── OpenAction/                 # Share sheet integration
├── Widgets/                    # Home screen widgets
└── Configuration/              # Build configurations
```

### macOS App Structure
```
macOS/
├── DuckDuckGo/                 # Main macOS app
│   ├── AppDelegate.swift       # App lifecycle
│   ├── MainWindow.swift        # Primary window controller
│   ├── BrowserTabViewController.swift # Web view management
│   ├── AIChat/                 # AI chat integration
│   ├── Autofill/               # Form autofill features
│   ├── Bookmarks/              # Bookmark management UI
│   ├── Downloads/              # Download handling
│   ├── NavigationBar/          # URL bar and navigation
│   ├── NetworkProtection/      # VPN integration
│   ├── Preferences/            # Settings and preferences
│   ├── Subscription/           # Premium features
│   ├── SyncPrompt/             # Sync feature prompts
│   ├── TabBar/                 # Tab management UI
│   └── WebView/                # Web view management
├── DuckDuckGoVPN/              # Standalone VPN app
├── NetworkProtectionSystemExtension/ # System-level VPN
├── DuckDuckGoDBPBackgroundAgent/ # Data Broker Protection
├── DuckDuckGoNotifications/    # System notifications
└── Configuration/              # Build configurations
```

## Dependencies and Packages

### Primary Dependency: BrowserServicesKit
```swift
// ✅ CORRECT - Always use BrowserServicesKit for shared functionality
import BrowserServicesKit

// Features provided by BrowserServicesKit:
// - Content blocking and privacy protection
// - Bookmarks and history management
// - Secure credential storage
// - Autofill functionality
// - Navigation handling
// - User script injection
// - Privacy configuration
// - Sync functionality
```

### Shared Packages
```
SharedPackages/
├── AIChat/                     # AI chat functionality
├── BrowserServicesKit/         # Core browser services
├── DataBrokerProtectionCore/   # Data broker protection
├── DesignResourcesKitIcons/    # Shared icon resources
├── Onboarding/                 # User onboarding experience
├── UIComponents/               # Reusable UI components
└── VPN/                        # VPN functionality
```

### Package Dependencies
```swift
// ✅ CORRECT - Use shared packages for cross-platform features
import DesignResourcesKitIcons
import UIComponents
import BrowserServicesKit

// ❌ INCORRECT - Don't duplicate functionality across platforms
// Keep platform-specific code in iOS/ and macOS/ directories only
```

## Build Configuration

### Xcode Workspace Setup
```swift
// ✅ CORRECT - Always open workspace, not individual projects
// Open: DuckDuckGo.xcworkspace
// Don't open: iOS/DuckDuckGo-iOS.xcodeproj or macOS/DuckDuckGo-macOS.xcodeproj
```

### Build Requirements
```
iOS:
- Xcode 15.0 or later
- Swift 5.9 or later
- iOS 15.0+ deployment target
- Valid Apple Developer account
- Provisioning profiles for extensions

macOS:
- Xcode 15.0 or later
- Swift 5.9 or later
- macOS 11.4+ deployment target
- Developer ID certificate (for notarization)
- System extension entitlements
```

### Configuration Files
```
iOS/Configuration/
├── Configuration.xcconfig         # Base configuration
├── Configuration-Alpha.xcconfig   # Alpha build settings
├── Configuration-Debug.xcconfig   # Debug build settings
└── BuildNumber.xcconfig          # Build number management

macOS/Configuration/
├── Base.xcconfig                 # Base configuration
├── Debug.xcconfig                # Debug build settings
├── Release.xcconfig              # Release build settings
└── AppStore.xcconfig             # App Store specific
```

## Development Setup

### Initial Setup
```bash
# ✅ CORRECT - Development setup steps
# 1. Open workspace at root level
open DuckDuckGo.xcworkspace

# 2. Install Ruby dependencies (for Fastlane)
bundle install

# 3. Ensure all certificates and provisioning profiles are installed
# 4. SwiftLint is enforced - run before committing
```

### Key Technologies
```swift
// iOS Stack
// - Language: Swift 5.9+
// - UI: UIKit with SwiftUI components
// - Architecture: MVVM with AppDependencyProvider
// - Web Engine: WebKit with privacy enhancements

// macOS Stack
// - Language: Swift 5.9+
// - UI: AppKit with SwiftUI components
// - Architecture: MVVM with Combine
// - Web Engine: WebKit with privacy enhancements
// - System Integration: Native macOS features
```

## App Extensions and System Integration

### iOS Extensions
```swift
// ✅ CORRECT - iOS extension organization
// AutofillCredentialProvider/ - Password autofill
// PacketTunnelProvider/ - VPN network extension
// OpenAction/ - Share sheet integration
// Widgets/ - Home screen widgets
```

### macOS Extensions
```swift
// ✅ CORRECT - macOS extension organization
// NetworkProtectionSystemExtension/ - System-level VPN
// DuckDuckGoDBPBackgroundAgent/ - Background data protection
// DuckDuckGoNotifications/ - System notifications
// VPNProxyExtension/ - VPN proxy functionality
```

## Testing Structure

### iOS Testing
```
iOS/
├── DuckDuckGoTests/            # Unit tests
├── IntegrationTests/           # Integration tests
├── PerformanceTests/           # Performance benchmarks
├── UITests/                    # UI automation tests
├── SharedTestUtils/            # Shared test utilities
└── WebViewUnitTests/           # WebKit-specific tests
```

### macOS Testing
```
macOS/
├── UnitTests/                  # Unit test suite
├── IntegrationTests/           # Integration testing
├── UITests/                    # UI automation tests
└── SyncE2EUITests/             # End-to-end sync tests
```

## Important Files and Entry Points

### iOS Key Files
```swift
// Core Application Files
AppDelegate.swift                    # App lifecycle and initialization
MainViewController.swift             # Primary browser interface
BrowserTab.swift                     # Tab state management
TabsBarViewController.swift          # Tab bar UI (iPad)
BookmarksViewController.swift        # Bookmarks management
PrivacyDashboardViewController.swift # Privacy protection UI
```

### macOS Key Files
```swift
// Core Application Files
AppDelegate.swift                    # App lifecycle management
MainWindow.swift                     # Primary window controller
BrowserTabViewController.swift       # Web view management
NavigationBarViewController.swift    # URL bar and controls
PreferencesViewController.swift      # Settings interface
BookmarksBarViewController.swift     # Bookmarks toolbar
```

## Common Development Tasks

### Running the Apps
```swift
// ✅ CORRECT - Running applications
// iOS: Select "iOS Browser" scheme and simulator/device
// macOS: Select "DuckDuckGo" scheme and click Run
```

### Adding New Features
```swift
// ✅ CORRECT - Feature development flow
// 1. Determine if feature belongs in:
//    - BrowserServicesKit (shared functionality)
//    - Platform-specific code (iOS/ or macOS/)
// 2. Use appropriate dependency injection patterns
// 3. Follow existing architecture patterns
// 4. Write comprehensive tests
```

### Debugging and Testing
```swift
// ✅ CORRECT - Testing and debugging
// - Run tests: Cmd+U or Test navigator
// - Use Safari Web Inspector for web content debugging
// - Enable verbose logging in Debug builds
// - Use Instruments for performance profiling
```

## Build Schemes and Configurations

### iOS Build Schemes
```
- DuckDuckGo (iOS) - Main app
- iOS Browser - Browser-specific build
- Alpha - Alpha testing build
- Debug - Development build
```

### macOS Build Schemes
```
- DuckDuckGo - Main app
- Debug - Development build
- Release - Release build
- Review - Review build
```

## Platform-Specific Considerations

### iOS-Specific Features
```swift
// iOS-specific implementations
// - iPad-specific UI adaptations
// - iPhone-specific layouts
// - iOS system integration
// - App Store requirements
```

### macOS-Specific Features
```swift
// macOS-specific implementations
// - Menu bar integration
// - Touch Bar support (MacBook Pro)
// - Dock integration
// - System extensions
// - Universal Binary (Intel + Apple Silicon)
// - Notarization requirements
```

## Development Best Practices

### Code Organization
```swift
// ✅ CORRECT - Follow established patterns
// - Use dependency injection via AppDependencyProvider
// - Keep platform-specific code in appropriate directories
// - Share common functionality through BrowserServicesKit
// - Follow MVVM architecture patterns
```

### Performance Considerations
```swift
// ✅ CORRECT - Performance optimization
// - Native Apple Silicon support
// - Efficient memory management
// - Hardware acceleration
// - Optimized content blocking
```

This structure ensures maintainable, testable code while providing comprehensive browser functionality across both iOS and macOS platforms. 