# ``DuckDuckGo_Privacy_Browser``

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

## Development Patterns

### Feature Flags

New features are protected behind feature flags using `FeatureFlagger`. See `FeatureFlagger.swift` for implementation.

## Privacy Features

The browser includes comprehensive privacy protection:

- **Tracker Blocking**: Block third-party trackers using Tracker Radar
- **Cookie Protection**: Prevent cross-site tracking via cookies
- **HTTPS Upgrading**: Automatically upgrade to HTTPS when available
- **Email Protection**: Hide email addresses with @duck.com aliases
- **VPN**: System-wide VPN for IP hiding and privacy protection
- **Fire Button**: Quickly clear browsing data
- **Private Search**: DuckDuckGo Search by default

## Topics

### Essentials

- <doc:FireButton>
- <doc:TabManagement>
- <doc:VPNNetworkProtection>

### User Interface

- <doc:MenuSystem>
- <doc:NavigationBar>
