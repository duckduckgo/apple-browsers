# DuckDuckGo macOS Browser

## Overview
The DuckDuckGo macOS browser is a native desktop application providing privacy-focused web browsing with deep macOS system integration and professional features.

## Project Structure

### Main Application
- **Location**: `macOS/DuckDuckGo/`
- **Main Target**: DuckDuckGo-macOS
- **Minimum macOS Version**: 11.4

### Key Components

#### Core Features
- **Web Browsing**: Full-featured desktop browser with privacy protection
- **Tab Management**: Advanced tab organization and management
- **Downloads**: Integrated download manager
- **Bookmarks Bar**: Visual bookmark management
- **Privacy Dashboard**: Detailed tracker blocking information
- **Fire Button**: Instant data clearing
- **AI Chat**: Integrated AI assistant functionality
- **Subscription Features**: Premium features including VPN, Personal Information Removal, and Identity Theft Restoration
  - @DuckDuckGo/Subscription/CLAUDE.md

#### Feature Organization
The macOS app is organized into feature-specific directories:
- `AIChat/` - AI chat integration
- `Autofill/` - Password and form autofill
- `Bookmarks/` - Bookmark management UI
- `Downloads/` - Download handling
- `NavigationBar/` - URL bar and navigation controls
- `NetworkProtection/` - VPN integration
- `Preferences/` - Settings and preferences
- `TabBar/` - Tab management UI

#### App Extensions
- `DuckDuckGoDBPBackgroundAgent/` - Data Broker Protection background service
- `DuckDuckGoVPN/` - Standalone VPN app
- `NetworkProtectionAppExtension/` - Network protection app extension
- `NetworkProtectionSystemExtension/` - System-level VPN extension
- `VPNProxyExtension/` - VPN proxy functionality

### Dependencies

#### Primary Dependency: BrowserServicesKit
The macOS app extensively uses [BrowserServicesKit](../SharedPackages/BrowserServicesKit/CLAUDE.md), which provides:
- Content blocking and privacy protection
- Bookmarks and history management
- Secure credential storage
- Autofill functionality
- Navigation handling
- User script injection
- Privacy configuration
- Sync functionality

#### Other Shared Packages
- `AIChat` - AI chat functionality
- `DataBrokerProtectionCore` - Data broker protection logic
- `DesignResourcesKitIcons` - Shared icon resources
- `Onboarding` - User onboarding experience
- `UIComponents` - Reusable UI components
- `VPN` - VPN functionality

### Testing
- `UnitTests/` - Comprehensive unit test suite
- `IntegrationTests/` - Integration testing
- `UITests/` - UI automation tests

### Build & Configuration
- **Build System**: Xcode with Swift Package Manager
- **Configuration Files**: `macOS/Configuration/`
- **Schemes**: Multiple build schemes (Debug, Release, Review)
- **CI/CD**: Fastlane integration
- **Notarization**: Required for distribution

### Key Technologies
- **Language**: Swift 5.9+
- **UI Framework**: AppKit (primary) with SwiftUI components
- **Architecture**: MVVM pattern with Combine framework
- **Dependency Management**: Swift Package Manager
- **Web Engine**: WebKit with custom privacy enhancements
- **Concurrency**: Swift async/await and GCD

### Development Tips
1. Open `DuckDuckGo.xcworkspace` at the root level
2. Ensure Developer ID certificates are configured for notarization
3. Use the appropriate build scheme for your needs
4. SwiftLint is enforced - check before committing
5. Test on multiple macOS versions for compatibility

### Common Tasks
- **Running the app**: Select the DuckDuckGo scheme and click Run
- **Testing VPN**: Requires system extension entitlements
- **Debugging web content**: Use Safari Web Inspector
- **Performance profiling**: Use Instruments

### Important Files
- `AppDelegate.swift` - Application lifecycle management
- `MainWindow.swift` - Primary window controller
- `BrowserTabViewController.swift` - Web view management
- `NavigationBarViewController.swift` - URL bar and controls
- `PreferencesViewController.swift` - Settings interface
- `BookmarksBarViewController.swift` - Bookmarks toolbar

### macOS-Specific Features
- **Menu Bar**: Full menu bar integration with keyboard shortcuts
- **Touch Bar**: Support for MacBook Pro Touch Bar
- **Dock Integration**: Progress indicators and badges
- **System Extensions**: VPN and network protection
- **Universal Binary**: Supports both Intel and Apple Silicon

### Privacy & Security
- Local-only data storage by default
- No user tracking or analytics
- Hardened runtime enabled
- App sandboxing (where applicable)
- Notarization for Gatekeeper compliance

### Performance Considerations
- Native Apple Silicon support
- Efficient memory management for multiple tabs
- Hardware acceleration for video playback
- Optimized content blocking

### Build Requirements
- Xcode 15.0 or later
- macOS 11.4+ deployment target
- Developer ID certificate for notarization
- Admin privileges for system extension installation

### Related Documentation
- [BrowserServicesKit Documentation](../SharedPackages/BrowserServicesKit/CLAUDE.md)
- [Main Repository README](../README.md)
- [Contributing Guidelines](../CONTRIBUTING.md)