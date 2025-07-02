# DuckDuckGo iOS Browser

## Overview
The DuckDuckGo iOS browser provides privacy-focused web browsing on iPhone and iPad devices with a native iOS experience.

## Project Structure

### Main Application
- **Location**: `iOS/DuckDuckGo/`
- **Main Target**: DuckDuckGo-iOS
- **Minimum iOS Version**: 15.0

### Key Components

#### Core Features
- **Web Browsing**: Privacy-focused browser with content blocking
- **Search**: DuckDuckGo search integration
- **Privacy Dashboard**: Visual representation of blocked trackers
- **Fire Button**: Quick data clearing functionality
- **Bookmarks & History**: Local storage of user data
- **Subscription Features**: Premium features including VPN, Personal Information Removal, and Identity Theft Restoration
  - @DuckDuckGo/Subscription/CLAUDE.md

#### App Extensions
- `AutofillCredentialProvider/` - Password and credential autofill
- `OpenAction/` - Share sheet integration
- `PacketTunnelProvider/` - VPN network extension
- `Widgets/` - Home screen widgets

#### Core Framework
- `Core/` - Shared utilities and extensions used throughout the iOS app

### Dependencies

#### Primary Dependency: BrowserServicesKit
The iOS app heavily relies on [BrowserServicesKit](../SharedPackages/BrowserServicesKit/CLAUDE.md), which provides:
- Content blocking and privacy protection
- Bookmarks and history management
- Secure credential storage
- Autofill functionality
- Navigation handling
- User script injection
- Privacy configuration

#### Other Shared Packages
- `AIChat` - AI chat integration
- `DesignResourcesKitIcons` - Shared icon resources
- `Onboarding` - User onboarding flows
- `UIComponents` - Reusable UI components
- `VPN` - VPN functionality

### Testing
- `DuckDuckGoTests/` - Unit tests
- `IntegrationTests/` - Integration tests
- `PerformanceTests/` - Performance benchmarks
- `UITests/` - UI automation tests

### Build & Configuration
- **Build System**: Xcode with Swift Package Manager
- **Configuration Files**: `iOS/Configuration/`
- **Schemes**: Multiple build schemes for different configurations
- **CI/CD**: Fastlane integration

### Key Technologies
- **Language**: Swift
- **UI Framework**: UIKit with some SwiftUI components
- **Architecture**: MVVM pattern
- **Dependency Management**: Swift Package Manager

### Development Tips
1. Open `DuckDuckGo.xcworkspace` at the root level, not the individual project file
2. Ensure all required certificates and provisioning profiles are installed
3. Run `bundle install` for Ruby dependencies (Fastlane)
4. SwiftLint is enforced - run before committing

### Common Tasks
- **Running the app**: Select the DuckDuckGo scheme and a simulator/device
- **Running tests**: Cmd+U or use the Test navigator
- **Adding features**: Consider if functionality should be in BrowserServicesKit for sharing with macOS
- **Debugging**: Enable verbose logging in Debug builds

### Important Files
- `AppDelegate.swift` - Application lifecycle and initialization
- `MainViewController.swift` - Primary browser interface and tab management
- `BrowserTab.swift` - Individual tab state and WebKit integration
- `BookmarksViewController.swift` - Bookmarks UI and management
- `PrivacyDashboardViewController.swift` - Tracker blocking visualization
- `SubscriptionFlowViewModel.swift` - Subscription purchase flows
- `TabsBarViewController.swift` - Tab bar UI for iPad

### Privacy & Security
- All user data is stored locally
- No tracking or analytics without explicit consent
- Content blocking enabled by default
- Secure credential storage using iOS Keychain

### Build Requirements
- Xcode 15.0 or later
- Swift 5.9 or later
- iOS 15.0+ deployment target
- Valid Apple Developer account for device testing
- Provisioning profiles for app extensions

### Related Documentation
- [BrowserServicesKit Documentation](../SharedPackages/BrowserServicesKit/CLAUDE.md)
- [Main Repository README](../README.md)
- [Contributing Guidelines](../CONTRIBUTING.md)