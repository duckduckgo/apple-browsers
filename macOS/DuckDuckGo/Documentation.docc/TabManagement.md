# Tab Management

The Tab is the core container for web content, managing WebKit views, navigation, and modular extensions.

## Overview

The ``Tab`` class is the fundamental unit of web browsing in the DuckDuckGo macOS browser. Each tab manages its own WKWebView instance, handles navigation events, maintains browsing state, and coordinates with a modular system of extensions that provide features like content blocking, autofill, privacy reporting, and more.

The tab architecture follows a composition pattern where core functionality is extended through ``TabExtension`` implementations. This design provides clear separation of concerns, making features testable and maintainable while avoiding a monolithic tab implementation.

## Architecture

### Core Components

```
Tab
├── WKWebView (WebKit integration)
├── NavigationDelegate (navigation coordination)
├── TabExtensions (feature composition)
│   ├── ContentBlockingTabExtension
│   ├── PrivacyDashboardTabExtension
│   ├── AutofillTabExtension
│   ├── DownloadsTabExtension
│   └── [15+ other extensions]
├── UserScripts (JavaScript injection)
└── TabDelegate (communication with MainViewController)
```

### Tab Lifecycle

1. **Creation**: Tab initialized with configuration and dependencies
2. **WebView Setup**: WKWebView created with user scripts and content rules
3. **Extension Registration**: TabExtensions instantiated and registered
4. **Navigation**: User navigates, extensions react to navigation events
5. **State Changes**: Extensions update based on page content and user actions
6. **Closure**: Tab cleaned up, webview deallocated, extensions torn down

### Extension System

The ``TabExtension`` protocol enables modular functionality. Each extension:
- Has a defined ``PublicProtocol`` interface
- Receives ``TabExtensionDependencies`` on initialization
- Can subscribe to tab events (navigation, page load, etc.)
- Exposes functionality through its public protocol

Extensions are resolved via `TabExtensions.resolve(_:)` and accessed through computed properties that maintain type safety while hiding implementation details.

## Key Components

### Core Tab Implementation

- **`Tab`** - Tab module
  - Main Tab class, WebView management, navigation coordination
  - Handles lifecycle, state, and coordination

- **`TabExtensions`** - Tab module
  - Extension protocol definitions and registration system
  - Extension resolution and dependency injection

- **`TabCollection`** - Tab module
  - Collection management for multiple tabs
  - Tab ordering, selection, and lifecycle coordination

### Extension Implementations

- **`ContentBlockingTabExtension`** - Content blocking per tab
- **`PrivacyDashboardTabExtension`** - Privacy reporting and dashboard
- **`AutofillTabExtension`** - Password and form autofill
- **`DownloadsTabExtension`** - File download coordination
- **`HistoryTabExtension`** - History tracking per tab
- **`NetworkProtectionControllerTabExtension`** - VPN exclusion rules
- **`AIChatTabExtension`** - AI chat integration

## Common Tasks

### Adding a New Tab Extension

To add a new tab extension:

1. Create your extension class conforming to `TabExtension` protocol
2. Define a public protocol for your extension's interface
3. Add an accessor in `TabExtensions` using `resolve(_:)`
4. Register the extension in `TabExtensions` initialization
5. Access from Tab using dynamic member lookup (e.g., `tab.myFeature`)

Reference existing implementations like `ContentBlockingTabExtension` or `HistoryTabExtension` for implementation patterns.

### Responding to Navigation Events

Extensions can subscribe to tab publishers like `navigationDidEndPublisher` using Combine. See the `Tab` class for available publishers and the `TabExtensions` class for integration patterns.

### Accessing Tab State

The ``Tab`` class exposes state through its public interface: `title`, `isLoading`, `canGoBack`, `canGoForward`, and other navigation flags as published properties. The current URL is read from the underlying web view (`tab.webView.url`) rather than as a direct stored property on Tab. Privacy-related state — such as the current ``PrivacyInfo`` — is exposed by the privacy dashboard extension and reached through dynamic member lookup on the Tab. Other per-feature state is similarly surfaced through extensions rather than stored directly on Tab itself.

## Patterns & Best Practices

### Extension Design Patterns

1. **Single Responsibility**: Each extension handles one feature domain
2. **Dependency Injection**: Extensions receive dependencies, don't create them
3. **Protocol-Based Access**: Public protocols hide implementation details
4. **Weak References**: Extensions hold weak references to Tab to avoid retain cycles
5. **Combine Integration**: Use publishers for event-driven communication

### Memory Management

- **Always use `weak self`** in closures capturing the extension
- **Store `AnyCancellable`** subscriptions in a Set for proper cleanup
- Extensions are deallocated when the tab closes

### Testing Extensions

Test extensions using mock `Tab` and `TabExtensionDependencies` implementations to verify extension behavior in isolation.

### Common Pitfalls

- **Don't access WKWebView directly** - Use Tab's public interface
- **Don't create strong reference cycles** - Always use `[weak self]` in closures
- **Don't perform heavy work synchronously** - Use async/await or background queues
- **Don't forget state restoration** - Implement `NSCodingExtension` if needed

## Related Topics

- <doc:UserScripts> - JavaScript injection framework used by tabs
- <doc:PrivacyFeatures> - Content blocking integrated via TabExtensions
- ``MainViewController`` - Tab coordination and UI integration
- ``TabCollection`` - Managing multiple tabs
- ``WKWebView`` - WebKit integration patterns

