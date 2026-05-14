# ``DuckDuckGo_Privacy_Browser``

@Metadata {
    @TechnologyRoot
}

Privacy-focused web browser for macOS with advanced tracking protection and privacy features.

## Overview

DuckDuckGo for macOS is a native browser built on WebKit, providing comprehensive privacy protection without compromising browsing experience. The browser is architected around privacy-first principles, with features like tracker blocking, cookie protection, email protection, and VPN built directly into the core browsing experience.

## Architecture Principles

### Privacy by Default

Privacy features are enabled by default and deeply integrated into the browser architecture rather than bolted on as extensions. Content blocking, cookie protection, and HTTPS upgrading happen at the platform level.

### Native Performance

Built entirely in Swift and SwiftUI for macOS, the browser leverages platform capabilities for performance and integration with macOS features like system extensions, iCloud Keychain, and Universal Clipboard.

### Modular Design

Core functionality is organized into focused packages and modules:
- **SharedPackages**: Cross-platform packages shared with iOS
- **LocalPackages**: macOS-specific local packages
- **Tab Architecture**: Extension-based tab functionality
- **Feature Coordination**: MVVM + Coordinators pattern

## Essential Guides

Essential guides for understanding and working with the macOS browser:

- <doc:FireButton> - Data clearing and fireproofing
- <doc:TabManagement> - Tab lifecycle, extensions, and WebView management
- <doc:VPNNetworkProtection> - VPN system extension architecture and IPC communication

### User Interface

- <doc:MenuSystem> - macOS menu bar and menu item management
- <doc:NavigationBar> - Address bar, suggestions, and navigation controls

## Package Documentation

For reusable package APIs, see the respective package documentation:

- **VPN Package** - `TunnelController` protocol for VPN control
- **Other Shared Packages** - See package-specific documentation

## Getting Started

### Project Structure

```
macOS/
├── DuckDuckGo/              # Main application target
│   ├── Tab/                 # Tab architecture
│   ├── MainWindow/          # Main window and view controllers
│   ├── Preferences/         # Settings UI
│   ├── Bookmarks/           # Bookmarks management
│   ├── History/             # History UI
│   ├── NetworkProtection/   # VPN integration
│   └── ...
├── DuckDuckGoVPN/           # VPN agent application
├── LocalPackages/           # macOS-specific packages
│   ├── AppLauncher/
│   ├── SystemExtensionManager/
│   └── ...
└── Configuration/           # Build configuration

SharedPackages/              # Cross-platform packages
├── BrowserServicesKit/      # Core browser services
├── VPN/                     # VPN package
├── Bookmarks/               # Bookmark data models
└── ...
```

### Build Requirements

- Xcode 15+
- macOS 14+ (Sonoma) for development
- Swift 5.9+

### Key Dependencies

- **WebKit**: Core web rendering engine
- **SwiftUI + AppKit**: UI framework (hybrid approach)
- **Core Data**: Local persistence (bookmarks, history)
- **Combine**: Reactive programming
- **Network Extension**: VPN functionality

## Development Patterns

### Dependency Injection

Components receive dependencies through initializers rather than accessing globals, enabling better testability and modular design.

### MVVM + Coordinators

UI follows Model-View-ViewModel pattern with Coordinators managing navigation and flow:

- **Models**: Data structures and business logic
- **ViewModels**: UI state and presentation logic
- **Views**: SwiftUI/AppKit UI components
- **Coordinators**: Navigation and feature orchestration

### Feature Flags

New features are protected behind feature flags using `FeatureFlagger`. See `FeatureFlagger.swift` for implementation.

### Testing Strategy

- **Unit Tests**: Test business logic and view models
- **Integration Tests**: Test component interaction
- **UI Tests**: Test end-to-end user flows

## Common Tasks

### Adding a New Feature

1. Plan the feature architecture (where does it fit?)
2. Create necessary models and business logic
3. Implement UI (SwiftUI or AppKit)
4. Add feature flag if experimental
5. Integrate with existing systems (tabs, preferences, etc.)
6. Add tests
7. Update documentation

### Debugging

- **Console Logging**: Use `os.log` with appropriate subsystems
- **Breakpoints**: Xcode breakpoints work well with Swift
- **View Debugging**: Xcode's view hierarchy debugger
- **Network Inspector**: Safari Web Inspector for WKWebView
- **VPN Debugging**: System extension logs in Console.app

### Performance Profiling

- **Instruments**: Time Profiler, Allocations, Leaks
- **PixelKit**: Custom performance metrics
- **WebKit Inspector**: JavaScript profiling

## Privacy Features

The browser includes comprehensive privacy protection:

- **Tracker Blocking**: Block third-party trackers using Tracker Radar
- **Cookie Protection**: Prevent cross-site tracking via cookies
- **HTTPS Upgrading**: Automatically upgrade to HTTPS when available
- **Email Protection**: Hide email addresses with @duck.com aliases
- **VPN**: System-wide VPN for IP hiding and privacy protection
- **Fire Button**: Quickly clear browsing data
- **Private Search**: DuckDuckGo Search by default
