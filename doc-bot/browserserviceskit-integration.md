---
title: "BrowserServicesKit Integration Guide"
description: "Guidelines for integrating with BrowserServicesKit, the core shared library providing browser functionality to iOS and macOS apps"
keywords: ["BrowserServicesKit", "shared library", "content blocking", "privacy", "bookmarks", "autofill", "navigation", "cross-platform"]
alwaysApply: false
---

# BrowserServicesKit Integration Guide

## Overview
BrowserServicesKit is the core shared library providing essential browser functionality to both iOS and macOS DuckDuckGo applications. It ensures consistent behavior and code reuse across platforms while maintaining privacy as the primary focus.

## Core Modules and Usage

### Privacy & Protection
Always use BrowserServicesKit for privacy-related functionality:

```swift
// ✅ CORRECT - Content blocking integration
import BrowserServicesKit
import ContentBlocking

final class PrivacyManager {
    private let contentBlockingManager = ContentBlockingManager.shared
    
    func enableContentBlocking(for webView: WKWebView) {
        contentBlockingManager.enable(for: webView)
    }
    
    func updateBlockingRules() async {
        await contentBlockingManager.updateRules()
    }
}

// ✅ CORRECT - Privacy configuration
import PrivacyConfig

final class PrivacyFeatureManager {
    private let privacyConfig = PrivacyConfiguration.shared
    
    func isFeatureEnabled(_ feature: PrivacyFeature) -> Bool {
        return privacyConfig.isEnabled(feature)
    }
}
```

### Data Management
Use BrowserServicesKit for all data persistence:

```swift
// ✅ CORRECT - Bookmarks management
import Bookmarks

final class BookmarkService {
    private let bookmarkManager = BookmarkManager.shared
    
    func saveBookmark(_ bookmark: Bookmark) async {
        await bookmarkManager.save(bookmark)
    }
    
    func fetchBookmarks() async -> [Bookmark] {
        return await bookmarkManager.fetchAll()
    }
}

// ✅ CORRECT - Secure credential storage
import SecureVault

final class CredentialManager {
    private let secureVault = SecureVault.shared
    
    func storeCredential(_ credential: WebsiteCredential) async throws {
        try await secureVault.store(credential)
    }
    
    func retrieveCredentials(for domain: String) async throws -> [WebsiteCredential] {
        return try await secureVault.credentials(for: domain)
    }
}
```

### Navigation and URL Handling
Use BrowserServicesKit for navigation logic:

```swift
// ✅ CORRECT - Navigation handling
import Navigation

final class NavigationManager {
    private let navigationController = NavigationController()
    
    func navigate(to url: URL) {
        let request = NavigationRequest(url: url)
        navigationController.navigate(request)
    }
    
    func canGoBack() -> Bool {
        return navigationController.canGoBack
    }
}
```

### User Scripts and Content Injection
Use BrowserServicesKit for JavaScript injection:

```swift
// ✅ CORRECT - User script management
import UserScript

final class ContentScriptManager {
    private let userScriptManager = UserScriptManager()
    
    func injectPrivacyScripts(into webView: WKWebView) {
        let scripts = userScriptManager.privacyScripts
        scripts.forEach { script in
            webView.configuration.userContentController.addUserScript(script)
        }
    }
}
```

## Platform-Specific Integration

### iOS Integration Pattern
```swift
// ✅ CORRECT - iOS-specific BrowserServicesKit usage
import BrowserServicesKit
import UIKit

final class iOSBrowserViewController: UIViewController {
    private let contentBlockingManager = ContentBlockingManager.shared
    private let privacyDashboard = PrivacyDashboard()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBrowserServices()
    }
    
    private func setupBrowserServices() {
        // Configure content blocking for iOS
        contentBlockingManager.configure(for: .iOS)
        
        // Setup privacy dashboard
        privacyDashboard.delegate = self
    }
}
```

### macOS Integration Pattern
```swift
// ✅ CORRECT - macOS-specific BrowserServicesKit usage
import BrowserServicesKit
import AppKit

final class macOSBrowserViewController: NSViewController {
    private let contentBlockingManager = ContentBlockingManager.shared
    private let downloadManager = DownloadManager.shared
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupBrowserServices()
    }
    
    private func setupBrowserServices() {
        // Configure content blocking for macOS
        contentBlockingManager.configure(for: .macOS)
        
        // Setup download handling
        downloadManager.delegate = self
    }
}
```

## Feature-Specific Integration

### Autofill Integration
```swift
// ✅ CORRECT - Autofill implementation
import Autofill
import BrowserServicesKit

final class AutofillCoordinator {
    private let autofillManager = AutofillManager.shared
    
    func setupAutofill(for webView: WKWebView) {
        // Configure autofill user scripts
        let autofillScripts = autofillManager.userScripts
        autofillScripts.forEach { script in
            webView.configuration.userContentController.addUserScript(script)
        }
        
        // Setup message handlers
        autofillManager.setupMessageHandlers(for: webView)
    }
    
    func handleAutofillRequest(_ request: AutofillRequest) async {
        await autofillManager.handleRequest(request)
    }
}
```

### Sync Integration
```swift
// ✅ CORRECT - Sync functionality
import DDGSync
import BrowserServicesKit

final class SyncManager {
    private let syncService = SyncService.shared
    
    func enableSync() async {
        await syncService.enable()
    }
    
    func syncBookmarks() async {
        await syncService.sync(.bookmarks)
    }
    
    func syncCredentials() async {
        await syncService.sync(.credentials)
    }
}
```

## Testing with BrowserServicesKit

### Mock BrowserServicesKit Components
```swift
// ✅ CORRECT - Testing with mocks
import BrowserServicesKit
import XCTest

final class MockContentBlockingManager: ContentBlockingManagerProtocol {
    var enabledRules: [ContentBlockingRule] = []
    var isBlocked: Bool = false
    
    func enable(rules: [ContentBlockingRule]) {
        enabledRules = rules
    }
    
    func isBlocked(url: URL) -> Bool {
        return isBlocked
    }
}

final class BrowserFeatureTests: XCTestCase {
    private var mockContentBlocking: MockContentBlockingManager!
    private var browserManager: BrowserManager!
    
    override func setUp() {
        super.setUp()
        mockContentBlocking = MockContentBlockingManager()
        browserManager = BrowserManager(contentBlocking: mockContentBlocking)
    }
    
    func testContentBlockingEnabled() {
        // Given
        let rules = [ContentBlockingRule.trackerRule]
        
        // When
        browserManager.enableContentBlocking(rules: rules)
        
        // Then
        XCTAssertEqual(mockContentBlocking.enabledRules, rules)
    }
}
```

## Configuration and Environment

### Environment-Based Configuration
```swift
// ✅ CORRECT - Environment configuration
import Configuration
import BrowserServicesKit

final class AppConfiguration {
    static func configure() {
        // Configure BrowserServicesKit for current environment
        let config = Configuration.current
        
        BrowserServicesKit.configure(
            environment: config.environment,
            privacyConfig: config.privacyConfig,
            contentBlockingConfig: config.contentBlockingConfig
        )
    }
}
```

### Feature Flag Integration
```swift
// ✅ CORRECT - Feature flag integration
import FeatureFlags
import BrowserServicesKit

extension FeatureFlags {
    var isAdvancedPrivacyEnabled: Bool {
        return isEnabled(.advancedPrivacy)
    }
    
    var isEnhancedAutofillEnabled: Bool {
        return isEnabled(.enhancedAutofill)
    }
}

final class FeatureFlagBrowserManager {
    func configureFeatures() {
        if FeatureFlags.shared.isAdvancedPrivacyEnabled {
            PrivacyConfiguration.shared.enableAdvancedFeatures()
        }
        
        if FeatureFlags.shared.isEnhancedAutofillEnabled {
            AutofillManager.shared.enableEnhancedFeatures()
        }
    }
}
```

## Performance Optimization

### Efficient BrowserServicesKit Usage
```swift
// ✅ CORRECT - Performance-optimized usage
import BrowserServicesKit

final class OptimizedBrowserManager {
    private let contentBlockingManager = ContentBlockingManager.shared
    private var cachedRules: [ContentBlockingRule] = []
    
    func loadContentBlockingRules() async {
        // Cache rules to avoid repeated API calls
        if cachedRules.isEmpty {
            cachedRules = await contentBlockingManager.loadRules()
        }
        
        // Apply cached rules
        await contentBlockingManager.apply(cachedRules)
    }
    
    func updateRulesIfNeeded() async {
        let lastUpdate = await contentBlockingManager.lastUpdateTime
        let shouldUpdate = Date().timeIntervalSince(lastUpdate) > 3600 // 1 hour
        
        if shouldUpdate {
            await loadContentBlockingRules()
        }
    }
}
```

## Error Handling

### BrowserServicesKit Error Handling
```swift
// ✅ CORRECT - Error handling patterns
import BrowserServicesKit

enum BrowserServiceError: LocalizedError {
    case contentBlockingFailed
    case bookmarkSaveFailed
    case credentialStoreFailed
    
    var errorDescription: String? {
        switch self {
        case .contentBlockingFailed:
            return "Failed to enable content blocking"
        case .bookmarkSaveFailed:
            return "Failed to save bookmark"
        case .credentialStoreFailed:
            return "Failed to store credential"
        }
    }
}

final class ErrorHandlingBrowserManager {
    func enableContentBlocking() async {
        do {
            try await ContentBlockingManager.shared.enable()
        } catch {
            // Log error and provide fallback
            Logger.error("Content blocking failed: \(error)")
            await showErrorToUser(BrowserServiceError.contentBlockingFailed)
        }
    }
}
```

## API Usage Guidelines

### Consistent API Patterns
```swift
// ✅ CORRECT - Follow BrowserServicesKit API patterns
import BrowserServicesKit

final class BrowserAPIManager {
    // Use async/await for async operations
    func loadData() async throws -> BrowserData {
        return try await BrowserDataManager.shared.load()
    }
    
    // Use Combine for reactive streams
    func observePrivacyEvents() -> AnyPublisher<PrivacyEvent, Never> {
        return PrivacyManager.shared.privacyEventPublisher
    }
    
    // Use completion handlers only when required by platform APIs
    func legacyOperation(completion: @escaping (Result<Data, Error>) -> Void) {
        Task {
            do {
                let data = try await modernAsyncOperation()
                completion(.success(data))
            } catch {
                completion(.failure(error))
            }
        }
    }
}
```

## Common Integration Patterns

### Dependency Injection with BrowserServicesKit
```swift
// ✅ CORRECT - Dependency injection pattern
protocol BrowserServiceProvider {
    var contentBlockingManager: ContentBlockingManagerProtocol { get }
    var bookmarkManager: BookmarkManagerProtocol { get }
    var autofillManager: AutofillManagerProtocol { get }
}

final class DefaultBrowserServiceProvider: BrowserServiceProvider {
    let contentBlockingManager: ContentBlockingManagerProtocol = ContentBlockingManager.shared
    let bookmarkManager: BookmarkManagerProtocol = BookmarkManager.shared
    let autofillManager: AutofillManagerProtocol = AutofillManager.shared
}

final class BrowserViewModel: ObservableObject {
    private let serviceProvider: BrowserServiceProvider
    
    init(serviceProvider: BrowserServiceProvider = DefaultBrowserServiceProvider()) {
        self.serviceProvider = serviceProvider
    }
}
```

This guide ensures proper integration with BrowserServicesKit while maintaining privacy-first principles and cross-platform compatibility. 