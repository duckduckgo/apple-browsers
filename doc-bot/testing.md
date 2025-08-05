---
alwaysApply: false
title: "Testing Guidelines & Best Practices"
description: "Comprehensive testing practices and patterns for DuckDuckGo browser development across iOS and macOS platforms including unit tests, mocks, memory management, and advanced testing techniques"
keywords: ["testing", "unit tests", "XCTest", "mocks", "async testing", "UI tests", "performance tests", "memory management", "snapshot testing", "MockFeatureFlagger", "Tab Extensions", "BSK tests"]
---

# Testing Guidelines & Best Practices

*This guide covers testing practices and patterns for the DuckDuckGo browser on iOS and macOS platforms.*

## 🚨 MANDATORY: Testing Execution Rules

### NEVER Run Tests Without Permission
**NEVER execute any test commands without EXPLICIT user permission or unles user explicitly asked to in their prompt.**

#### Required Testing Workflow:
1. Write or modify test code as requested
2. if user did not ask to run tests in their prompt, **STOP** before running any test commands:
   - `swift test`
   - `npm test` 
   - `xcodebuild test`
   - `fastlane test`
   - Any other test execution commands
3. **ASK** the user: "Should I run the tests?"
4. **WAIT** for explicit permission (e.g., "yes", "run tests", "test it")
5. Only then execute test commands

**This rule applies to ALL test execution - unit tests, integration tests, UI tests, performance tests, etc.**

---

## Future Improvements

This guide is a living document. Consider these areas for future improvements:

- **Tab Extensions Testing**: Expand patterns for testing complex tab extension interactions and lifecycle management
- **WebKit Integration Testing**: Add comprehensive patterns for testing WKWebView configurations, user scripts, and content blocking integration
- **Privacy Feature Testing**: Develop specialized testing approaches for tracker protection, HTTPS upgrade, and content blocking rule validation
- **Cross-Platform Testing**: Create patterns for testing SharedPackages functionality across iOS and macOS with consistent behavior validation
- **Fire Button Integration Testing**: Add comprehensive testing patterns for data clearing workflows across all browser components
- **Autofill and Credential Testing**: Expand testing approaches for AutofillCredentialProvider, password management, and form filling scenarios
- **Sync Testing**: Develop patterns for testing bookmark sync, conflict resolution, and cross-device data consistency
- **AI Chat Integration Testing**: Add testing patterns for AI chat functionality, context management, and user interaction flows
- **Feature Flag Testing**: Expand MockFeatureFlagger usage patterns and integration testing with real feature configurations

## Unit Tests

### What to Include

Unit tests should focus on testing individual components, functions, or classes in isolation. They should be:

- **Fast**: Run quickly (< 1 second per test)
- **Independent**: Not depend on external systems or other tests
- **Deterministic**: Always produce the same result given the same input
- **Focused**: Test one specific behavior or functionality

### ✅ When to Write Unit Tests

#### Model Logic
Testing business logic, data transformations, and model behavior:

```swift
func testBookmarkFolderCreation() {
    let folder = BookmarkFolder(title: "Test Folder")
    XCTAssertEqual(folder.title, "Test Folder")
    XCTAssertTrue(folder.children.isEmpty)
}
```

#### Algorithms/Parsers
Testing parsing logic, URL manipulation, search algorithms:

```swift
func testURLSchemeDetection() {
    let detector = URLSchemeDetector()
    XCTAssertTrue(detector.isValidURL("https://duckduckgo.com"))
    XCTAssertFalse(detector.isValidURL("invalid-url"))
}
```

#### Utility Functions
Testing helper functions, extensions, formatters:

```swift
func testDateFormatter() {
    let formatter = DateFormatter.shortDate
    let date = Date(timeIntervalSince1970: 1640995200) // 2022-01-01
    XCTAssertEqual(formatter.string(from: date), "1/1/22")
}
```

#### State Management
Testing ViewModels, state transitions, and data flow:

```swift
func testViewModelStateTransition() {
    let viewModel = SearchViewModel()
    viewModel.performSearch("test query")
    XCTAssertEqual(viewModel.state, .loading)
}
```

### ❌ What to Avoid

#### Simple Property Toggles
Testing trivial getters/setters:

```swift
// ❌ DON'T test this
func testIsEnabledToggle() {
    feature.isEnabled = true
    XCTAssertTrue(feature.isEnabled)
}
```

#### Complex UI Interactions
Use Integration or UI tests instead.

#### External Dependencies
File system, network calls, databases.

#### State/Strategy Pattern Switching
These are better suited for integration tests:

```swift
// ❌ DON'T test state switching in unit tests
func testStateSwitching() {
    stateMachine.transition(to: .loading)
    stateMachine.transition(to: .loaded)
    // This is brittle and doesn't test real behavior
}
```

## Mocks and Test Helpers

The DuckDuckGo browser project includes multiple mock categories for testing different components and scenarios:

### Mock Categories

#### Unit Tests Mocks
For testing individual components in isolation:
- **UI mocks**: MockWindow, MockTabViewItemDelegate
- **WebView mocks**: WebViewMock, WKSecurityOriginMock
- **Storage mocks**: FileStoreMock, UserDefaultsMock
- **Feature-specific mocks**: MockBookmarkManager, MockFireproofDomains, MockAIChatPreferencesStorage

#### Integration Tests Mocks
For testing component interactions and workflows:
- Content blocking mocks
- Tab navigation mocks
- Fire integration mocks
- Onboarding flow mocks
- System integration mocks

#### BSK Tests Mocks
For testing BrowserServicesKit functionality:
- **Feature flag mocks**: MockFeatureFlagger
- **Privacy configuration mocks**: MockPrivacyConfiguration
- **Statistics mocks**: MockStatisticsStore
- **Variant management mocks**: MockVariantManager
- **Network mocks**: MockAPIService

### Mock Usage Examples

#### UI Testing with MockWindow

```swift
func testViewControllerLifecycle() {
    autoreleasepool {
        let mockWindow = MockWindow()
        let viewController = MyViewController()
        
        mockWindow.contentViewController = viewController
        viewController.viewDidLoad() // Safe to call with MockWindow
        
        XCTAssertNotNil(viewController.view)
    } // Ensures proper cleanup
}
```

#### WebKit Testing with WebViewMock

```swift
func testGeolocationPermission() {
    autoreleasepool {
        let mockWebView = WebViewMock()
        let origin = WKSecurityOriginMock.new(url: URL(string: "https://example.com")!)
        let frameInfo = WKFrameInfoMock(webView: mockWebView, securityOrigin: origin, 
                                       request: URLRequest(url: URL(string: "https://example.com")!), 
                                       isMainFrame: true)
        
        // Test permission handling without actual web content
        permissionManager.requestGeolocationPermission(for: frameInfo) { granted in
            XCTAssertTrue(granted)
        }
    }
}
```

#### Feature Flag Testing with MockFeatureFlagger

**⚠️ CRITICAL**: MockFeatureFlagger is **REQUIRED** for feature tests throughout the entire codebase (iOS, macOS, BSK). Tests will crash without it due to DefaultFeatureFlagger assertions that prevent real feature flag usage in test environments.

```swift
func testFeatureFlaggedBehavior() {
    let mockFlagger = MockFeatureFlagger()
    mockFlagger.enabledFeatureFlags = [.contextualOnboarding]
    
    let feature = SomeFeature(featureFlagger: mockFlagger)
    XCTAssertTrue(feature.isOnboardingEnabled)
}

// Alternative approach using featuresStub
func testWithFeatureStub() {
    let mockFlagger = MockFeatureFlagger()
    mockFlagger.featuresStub = [
        "contextualOnboarding": true,
        "duckPlayer": false
    ]
    
    let component = TestComponent(featureFlagger: mockFlagger)
    XCTAssertTrue(component.hasOnboarding)
    XCTAssertFalse(component.hasDuckPlayer)
}

// Testing feature flag injection into Tab
func testTabWithFeatureFlags() {
    autoreleasepool {
        let mockFlagger = MockFeatureFlagger()
        mockFlagger.enabledFeatureFlags = [.tabCrashDebugging]
        
        let tab = Tab(content: .newtab, featureFlagger: mockFlagger)
        XCTAssertTrue(tab.canKillWebContentProcess)
    }
}
```

**Why MockFeatureFlagger is Essential**:
- **Test Isolation**: Prevents real feature flag configurations from affecting test outcomes
- **Crash Prevention**: DefaultFeatureFlagger includes assertions that crash tests if not using MockFeatureFlagger
- **Controlled Environment**: Ensures predictable test behavior regardless of remote configuration
- **Performance**: Avoids network calls and complex privacy configuration setup

### Mock Guidelines

#### When to Use Each Mock Category
- **Unit Tests Mocks**: Testing individual classes, methods, and components in isolation
- **Integration Tests Mocks**: Testing workflows, component interactions, and system behavior
- **BSK Tests Mocks**: Testing shared functionality, feature flags, and cross-platform components

#### Memory Management with Mocks
- Always use `autoreleasepool {}` for UI and WebKit mocks
- Use shared mock instances when testing multiple scenarios
- Reset mock state between tests to prevent pollution
- Be careful with reactive mocks that use Combine publishers

#### Mock Selection Criteria
When creating mocks:
- **Check existing mocks first** - Use available mocks before creating new ones
- **Create what you need** - Don't hesitate to create mocks for single-use scenarios if no suitable mock exists
- **Focus on behavior** - Mock the interfaces and protocols your code depends on
- **Make them realistic** - Mocks should behave similarly to real implementations

### Avoid "Testing Mocks" (Anti-patterns)

**Golden Rule**: "If you can omit mocking, omit mocking" - The more you mock, the more you deviate from the real system, decreasing test confidence.

#### Testing Implementation Details Instead of Behavior

```swift
// ❌ BAD - Testing that internal methods are called
func testUserServiceCallsCorrectMethods() {
    let mockRepository = MockUserRepository()
    let userService = UserService(repository: mockRepository)
    
    userService.getCurrentUser()
    
    XCTAssertTrue(mockRepository.lookupSessionsCalled)  // Testing HOW, not WHAT
    XCTAssertTrue(mockRepository.getLatestSessionCalled)
}

// ✅ GOOD - Testing the actual outcome
func testUserServiceReturnsCurrentUser() {
    let mockRepository = MockUserRepository()
    mockRepository.mockUser = User(id: "123", name: "John")
    let userService = UserService(repository: mockRepository)
    
    let user = userService.getCurrentUser()
    
    XCTAssertEqual(user?.name, "John")  // Testing WHAT happens, not HOW
}
```

#### Over-mocking Creates a Fake System

```swift
// ❌ BAD - Testing mostly mock interactions
func testCompleteWorkflow() {
    let mockAuth = MockAuthService()
    let mockAPI = MockAPIService() 
    let mockStorage = MockStorage()
    let mockLogger = MockLogger()
    let mockAnalytics = MockAnalytics()
    // ... testing interactions between mocks, not real behavior
}
```

#### Complex Scenarios Need Integration Testing

```swift
// ❌ BAD - Complex mocking setup for user flows
func testBookmarkSyncFlow() {
    let mockNetworkMonitor = MockNetworkMonitor()
    let mockSyncService = MockSyncService()
    let mockBookmarkStore = MockBookmarkStore()
    let mockConflictResolver = MockConflictResolver()
    // ... 50 lines of mock setup for a flow that should be integration tested
}

// ✅ BETTER - Use Integration Test instead
// This complex scenario is better tested as an integration test
// with real components, providing higher confidence and less maintenance
```

When complex mocking suggests better alternatives:
- If you're setting up many interconnected mocks → Consider an Integration Test with real components
- If you're mocking user interaction flows → Consider a UI Test that exercises the actual user journey 
- If mock setup takes longer than the test logic → You're probably over-mocking

## Memory Management - TestRunHelper

The project includes **TestRunHelper** that provides automatic memory management and tracking during testing.

### TestRunHelper Features (Automatically Enabled)

- **Autorelease Tracking**: Automatically enabled for all tests, tracks specific classes (WKWebView, NSWindow, NSWindowController, NSViewController, TabBarItemCellView)
- **View Hierarchy Tracking**: Monitors NSView creations and validates deallocation with 3-second timeout
- **UI Presentation Prevention**: Fails tests that try to present real UI with `fatalError("Unit Tests should not present UI. Use MockWindow if needed.")`
- **Test Instance Variables Clearing**: Monitors test case instance variables and ensures they're cleared after test completion
- **Shared Resource Management**: Shared WKProcessPool for WebKit tests, temporary directory cleanup

### Memory Issue Detection

TestRunHelper will break/assert in these scenarios:
- **CI Environment**: `fatalError()` with test failure
- **Local Development**: `breakByRaisingSigInt()` with debugging guidance
- **Tab Deallocation Check**: Tab.deinit includes comprehensive WebKit object deallocation verification

#### Override allowedNonNilVariables for Legitimate Cases

```swift
override var allowedNonNilVariables: Set<String> {
    ["constantData", "sharedManager", "staticConfiguration"]
}
```

### When to Use autoreleasepool {}

**Always Required**:

```swift
// 1. View Controller lifecycle testing
func testViewControllerLifecycle() {
    autoreleasepool {
        let window = MockWindow()
        let viewController = MyViewController()
        window.contentViewController = viewController
        // Test lifecycle methods
    } // Ensures immediate cleanup
}

// 2. Heavy object creation in loops
func testBatchOperations() {
    for i in 0..<1000 {
        autoreleasepool {
            let object = HeavyObject(data: testData[i])
            processObject(object)
        } // Releases object immediately instead of waiting for test end
    }
}

// 3. WebKit and content blocking tests
func testContentBlockingRules() {
    autoreleasepool {
        let rulesManager = MockContentBlockerRulesManager()
        let webView = WebViewMock()
        // Test content blocking behavior
    } // WebKit objects can be memory intensive
}

// 4. File system and database operations
func testDatabaseOperations() {
    autoreleasepool {
        let context = managedObjectContext
        let objects = createTestObjects(count: 100)
        context.save()
    } // Ensures Core Data cleanup
}
```

### Memory Management Best Practices

- Use `autoreleasepool` when creating more than a few objects in a test
- Always wrap view controller tests that involve UI hierarchy
- Use for any test involving file I/O, network operations, or large data
- Wrap tearDown operations when dealing with complex object hierarchies
- Essential for batch operations and performance tests

### Template for Memory-Safe Testing

```swift
func testFeature() {
    autoreleasepool {
        // 1. Setup mocks and dependencies
        let mockWindow = MockWindow()
        let mockManager = MockSomeManager()
        
        // 2. Create objects under test
        let objectUnderTest = MyObject(dependencies: mockManager)
        
        // 3. Perform test operations
        objectUnderTest.performAction()
        
        // 4. Assert results
        XCTAssertEqual(objectUnderTest.state, .expected)
        
        // 5. Objects are automatically released at end of autoreleasepool
    }
}
```

### AutoreleaseTracker

**What it is**: AutoreleaseTracker creates tracker objects that are autoreleased alongside specific tracked objects, maintaining malloc stack traces for debugging memory leaks.

**What it tracks**: WKWebView, NSWindow, NSWindowController, NSViewController, TabBarItemCellView

**How to debug autorelease issues**:
1. Enable MallocStackLogging in Tests scheme → Arguments → Environment Variables
2. Run your test and wait for deallocation timeout
3. Open Memory Browser in Xcode (Debug → Debug Workflow → View Memory)
4. Search for "AutoreleaseTracker" in Memory Browser
5. Analyze the stack trace to see where the autorelease call was made

## Integration Tests

### What to Include

Integration tests verify that multiple components work together correctly. They test:
- **Component Interactions**: How different modules communicate
- **Data Flow**: End-to-end data processing
- **System Integration**: External services, APIs, databases

### ✅ When to Write Integration Tests

#### Complex Feature Workflows
Testing complete user journeys:

```swift
func testBookmarkSyncFlow() {
    // Test bookmark creation -> sync -> retrieval
    let bookmark = createBookmark()
    syncManager.sync()
    let retrievedBookmark = bookmarkStore.fetch(by: bookmark.id)
    XCTAssertEqual(bookmark.title, retrievedBookmark?.title)
}
```

#### State Management
Testing complex state transitions in real scenarios.

#### Cross-Module Communication
Testing how different packages interact.

#### Database Operations
Testing Core Data models and persistence.

### ❌ Integration Test Anti-patterns

- **Debug Information**: Don't include debug prints, use `Logger.tests` instead
- **Real UI Dependencies**: Prefer mock windows and views
- **Heavy Resource Usage**: Avoid tests that load unnecessary resources
- **External Network Calls**: Use mocked services

### Best Practices for Integration Tests

```swift
class IntegrationTestCase: XCTestCase {
    
    override func setUp() {
        super.setUp()
        // Use mock window to avoid UI dependencies
        let mockWindow = MockWindow()
        setupTestEnvironment(window: mockWindow)
    }
    
    override func tearDown() {
        // Ensure all resources are properly released
        cleanupTestEnvironment()
        super.tearDown()
    }
    
    func testFeatureIntegration() {
        // Test real component interaction without UI
        let coordinator = FeatureCoordinator()
        let result = coordinator.performAction()
        XCTAssertNotNil(result)
    }
}
```

## BSK Tests

BSK (BrowserServicesKit) tests are specialized for the shared browser services package.

### Logging in BSK Tests

#### Getting BSK Test Logs

**From GitHub Actions**: Download the `bsk-xctest-log-stream.log` artifact from failed builds

**Local Development**:
```bash
# Use real-time log streaming (in separate terminal)
log stream --debug --info --predicate 'process == "xctest"' --style syslog &
swift test
```

> ⚠️ **AI Assistant Note**: These commands are examples for manual execution only. Never run test commands automatically without explicit user permission.

#### Enabling Private Data in Console App

By default, macOS Console app shows `<private>` instead of actual values for privacy. To see private data for debugging:

1. Install the logging plist (located at `SharedPackages/BrowserServicesKit/com.apple.system.logging.plist`):
   ```bash
   sudo cp com.apple.system.logging.plist /Library/Preferences/Logging/com.apple.system.logging.plist
   ```

2. Restart Console app to apply changes
3. Private data will now be visible in system logs for debugging purposes

**Note**: Only use this for debugging - remove the plist when done to restore privacy protection.

## Tab Extensions Testing

Tab Extensions are modular components that provide specific functionality to tabs. For comprehensive guidance on Tab Extensions architecture and implementation patterns, see the **Tab Extensions Knowledge Sharing**.

### Key Files to Reference
- `TabExtensions.swift` - Extension registration and architecture patterns
- `TabExtensionsBuilder.swift` - Extension initialization and dependency injection
- `Tab+Navigation.swift` - setupNavigationDelegate for navigation handling

### Basic Tab Extension Testing

```swift
class MyTabExtensionTests: XCTestCase {
    var extensionsBuilder: TestTabExtensionsBuilder!
    
    override func setUp() {
        super.setUp()
        // Load only the extension you want to test
        extensionsBuilder = TestTabExtensionsBuilder(load: [MyTabExtension.self])
    }
    
    func testExtensionFunctionality() {
        autoreleasepool {
            let tab = Tab(content: .none, extensionsBuilder: extensionsBuilder)
            let myExtension = tab.extensions.myExtension
            
            XCTAssertNotNil(myExtension)
            myExtension?.performAction()
            XCTAssertEqual(myExtension?.publicProperty, "expected_value")
        }
    }
}
```

### Advanced Testing with Mocked Dependencies

```swift
class AdClickAttributionTabExtensionTests: XCTestCase {
    func testExtensionWithMockedDependencies() {
        let extensionsBuilder = TestTabExtensionsBuilder(load: [AdClickAttributionTabExtension.self]) { builder in { args, dependencies in
            builder.override {
                AdClickAttributionTabExtension(
                    // Override with mocked dependencies
                    userContentControllerFuture: Future { $0(.success(self.mockUserContentController)) },
                    dependencies: dependencies.privacyFeatures.contentBlocking
                ) { _ in (logic: self.mockLogic, detection: self.mockDetection) }
            }
        }}
        
        autoreleasepool {
            let tab = Tab(content: .none, extensionsBuilder: extensionsBuilder)
            // Test extension behavior with mocked dependencies
        }
    }
}
```

### Tab Extension Testing Guidelines

#### ✅ Do:
- Use TestTabExtensionsBuilder for controlled extension loading
- Load only required extensions for isolated testing
- Test through public protocol interfaces
- Use autoreleasepool for memory management
- Mock dependencies through override patterns

#### ❌ Don't:
- Load all extensions unless testing integration
- Access private implementation details
- Create real UI (use MockWindow)
- Ignore proper setup and teardown

## UI Tests

UI Tests verify the end-to-end user experience and interface behavior.

### Setting Up UI Tests

#### ❗Always Use UITestCase Base Class

```swift
class FeatureUITests: UITestCase {  // ✅ Use UITestCase, not XCTestCase
    private var app: XCUIApplication!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()  // ✅ Use setUp(), never launch() directly
        // app is already launched and configured by setUp()
    }
}
```

#### Feature Flag Configuration

```swift
// Configure feature flags during test setup
override func setUpWithError() throws {
    app = XCUIApplication.setUp(featureFlags: [
        "contextualOnboarding": true,
        "visualUpdates": false,
        "duckPlayer": true
    ])
    // Feature flags are automatically applied via FEATURE_FLAGS environment variable
}

// Alternative: Custom environment
app = XCUIApplication.setUp(environment: [
    "UITEST_MODE_ONBOARDING": "1"
], featureFlags: [
    "newTabPageSections": true
])
```

**❗Why Feature Flag Configuration is Critical**:
- UI tests run against notarized builds - feature flags can't be changed at runtime
- MockFeatureFlagger is NOT available in UI tests (only real DefaultFeatureFlagger)
- Feature flags must be configured via FEATURE_FLAGS environment variable before app launch
- Incorrect feature state will cause UI tests to fail when expected UI elements don't appear

### Best Practices for UI Tests

#### Use Existing Element Queries and Helper Methods

```swift
// ✅ GOOD - Use existing element queries
let addressBarTextField = app.windows.textFields["AddressBarViewController.addressBarTextField"]
let historyMenuItem = app.menuItems["HistoryMenu.clearAllHistory"]

// ✅ GOOD - Add popular queries to extensions when appropriate
extension XCUIApplication {
    var addressBar: XCUIElement {
        windows.textFields["AddressBarViewController.addressBarTextField"]
    }
    
    var fakeFireButton: XCUIElement {
        buttons["FireViewController.fakeFireButton"]
    }
}
```

#### Available XCUIElement Helper Methods

```swift
// ✅ GOOD - Use existing helper methods that solve real problems

// 1. Safe element interaction with existence checks
element.clickAfterExistenceTestSucceeds()
element.hoverAfterExistenceTestSucceeds()
element.typeURLAfterExistenceTestSucceeds(testURL)

// 2. URL handling with colon workaround
element.typeURL(url, pressingEnter: true)  // Handles colon typing issues
element.pasteURL(url, pressingEnter: true) // Faster than typing

// 3. Element disappearance tracking  
element.waitForNonExistence(timeout: UITests.Timeouts.elementExistence)

// 4. Proper existence checking patterns
XCTAssertTrue(mainElement.waitForExistence(timeout: UITests.Timeouts.elementExistence))
XCTAssertTrue(relatedButton.exists)  // ✅ Good after waitForExistence passed
XCTAssertTrue(anotherComponent.exists)  // ✅ Good for checking multiple components

// ❌ BAD - Avoid these patterns
XCTAssertTrue(element.exists)  // Without waitForExistence first - may fail due to timing
XCTAssertTrue(element1.waitForExistence(timeout: 5))
XCTAssertTrue(element2.waitForExistence(timeout: 5))  // Consecutive waits slow down tests
Thread.sleep(forTimeInterval: 2.0)  // Unreliable, use waitForExistence
Task.sleep(nanoseconds: 2_000_000_000)  // Same issue, avoid
```

#### Timing and Existence Guidelines

- Use `waitForExistence(timeout:)` first for the main element/view that needs to appear
- Then use `XCTAssertTrue(element.exists)` to check related components that should already be present
- Avoid consecutive `waitForExistence` calls - they slow down test execution unnecessarily
- Avoid `Thread.sleep()` or `Task.sleep()` - they're unreliable and slow tests down
- Use helper methods that combine existence checks with actions - they're more reliable
- Use `UITests.Timeouts` constants for consistent timeout values across tests

#### Context Menu Interaction Workaround

```swift
// Use coordinate-based context menu clicking for reliability across macOS versions
func testContextMenuAction() {
    let webView = app.webViews.firstMatch
    webView.rightClick()
    
    // ✅ Use the coordinate-based context menu hack
    try app.clickContextMenuItem(matching: { $0.identifier == "PDFContextMenu.print" })
    
    // This method uses coordinate-based clicking instead of direct element interaction
    // because context menu detection fails on older macOS systems (13/14) in CI
}
```

### Local Test Server Setup

UI tests use a local test server running on `http://localhost:8085/` for reliable page loading and content simulation.

#### How It Works:
- Test server runs on port 8085 (not 8080)
- Uses `TestsURLExtension.swift` shared with Integration Tests
- Provides `URL.testsServer` and `.appendingTestParameters()` methods
- Supports dynamic content generation via query parameters

#### Creating Test URLs:

```swift
// Static content from test files
let url = URL.testsServer.appendingPathComponent("test-page.html")

// Dynamic content with custom HTML
let url = UITests.simpleServedPage(titled: "Test Page")
// Creates: http://localhost:8085/?data=<html>...<title>Test Page</title>...</html>

// Custom responses with headers and status codes
let url = URL.testsServer
    .appendingPathComponent("test-endpoint")
    .appendingTestParameters(
        status: 404,
        reason: "Not Found",
        headers: ["Content-Type": "application/json"]
    )
```

#### URL Parameter Options:
- `status`: HTTP status code (default: 200)
- `reason`: HTTP status string (default: "OK") 
- `data`: Response body (Data or String, base64 encoded if binary)
- `headers`: HTTP response headers

#### Best Practices:
- Use `UITests.simpleServedPage(titled:)` for basic HTML pages
- Use `URL.testsServer.appendingTestParameters()` for custom responses
- Test various HTTP status codes and response types
- Keep test content simple and predictable

### Using Pasteboard for Speed

```swift
func testAddressBarInput() {
    // Instead of typing character by character
    let testURL = "https://example.com"
    UIPasteboard.general.string = testURL
    
    addressBar.press(forDuration: 1.0)
    app.menuItems["Paste"].tap()
    
    // Much faster than: addressBar.typeText(testURL)
}
```

### UI Test Build Architecture

UI tests use a unique build architecture:
- **App Binary**: Built using notarized build action (latest Xcode/toolchain)
- **UI Test Bundle**: Built on target macOS version (macOS 13/14/15 runners)
- **Testing**: UI Test bundle tests the notarized app binary across macOS 13/14/15

#### Critical UI Test Code Compatibility Requirements:

```swift
// ✅ GOOD - UI Test code must compile on older Xcode versions
func testFeature() {
    let app = XCUIApplication.setUp()
    app.addressBar.typeText("test")
    // Uses APIs available in minimum supported Xcode
}

// ❌ BAD - Don't use newest APIs that aren't available on older Xcode
@available(macOS 14.0, *)
func testNewAPI() {
    // This won't compile on macOS 13 UI test runners
}
```

**Compatibility Guidelines**:
- UI Test code must compile on oldest supported Xcode version (for macOS 13 runner)
- App code can use latest Swift/Xcode features (built with latest toolchain)
- Test only stable APIs - avoid beta/preview APIs in UI test code
- Use `@available` checks carefully - must work across all test runners

### Screenshot Management

- **Automatic Screenshots**: Screenshots are taken automatically on test failures
- **Manual Screenshots**: Use `XCTAttachment` for custom screenshots

```swift
func takeScreenshot(name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
}
```

## Snapshot Testing

### Overview

The project uses `swift-snapshot-testing` for snapshot testing, which captures and compares outputs to detect regressions.

**Available snapshot types**:
- **Image snapshots**: Visual UI testing
- **JSON snapshots**: Data structure testing
- **Inline snapshots**: Text-based output testing

### When to Use Snapshot Testing

#### ✅ Excellent for:

**Complex Data Structures**: Testing JSON responses, complex model transformations

```swift
// Example: Testing complex suggestion results
func testSuggestionResults() {
    let suggestions = suggestionLoader.getSuggestions(for: "duck")
    assertInlineSnapshot(of: suggestions.encoded(), as: .lines, matches: """
    Suggestions:
    - Search: "duck" (score: 100)
    - Bookmark: "DuckDuckGo" (https://duckduckgo.com)
    - History: "Duck typing" (https://en.wikipedia.org/wiki/Duck_typing)
    """)
}
```

**Visual Regression Testing**: UI components, layouts, visual elements

**Algorithm Output Validation**: Testing complex calculations, parsing results

**Cross-Platform Consistency**: Ensuring consistent output across iOS/macOS

### Image Snapshot Testing

Perfect for visual regression testing:

```swift
import SnapshotTesting

func testButtonAppearance() {
    for appearanceName: NSAppearance.Name in [.aqua, .darkAqua] {
        NSApp.appearance = .init(named: appearanceName)!
        
        let button = createStyledButton()
        assertSnapshot(of: button, as: .image(perceptualPrecision: 0.9), named: appearanceName.rawValue)
    }
}
```

**Image snapshot guidelines**:
- Test in both light and dark modes
- Use `perceptualPrecision: 0.9` for UI components (allows minor anti-aliasing differences)
- Use `perceptualPrecision: 1.0` for pixel-perfect requirements
- Create consistent test environments (fixed window sizes, scale factors)

### JSON Snapshot Testing

Ideal for data structure validation:

```swift
func testBookmarkImport() {
    let importResult = bookmarkImporter.importFromHTML(testFile)
    assertSnapshot(of: importResult.bookmarks, as: .json, named: "imported_bookmarks")
}
```

**JSON snapshot benefits**:
- Catches structural changes in data models
- Validates complex transformations
- Provides clear diffs for debugging
- Language-agnostic format

### Inline Snapshot Testing

Best for text-based output and algorithm results:

```swift
func testSearchSuggestions() {
    let results = searchEngine.getSuggestions(for: "privacy")
    assertInlineSnapshot(of: results.encoded(), as: .lines, matches: """
    Privacy Settings
    Privacy Policy
    Privacy Tools
    """)
}
```

**Inline snapshot advantages**:
- Snapshots live in the test file
- Easy to review changes in pull requests
- No external files to manage
- Great for small, predictable outputs

### Snapshot Testing Best Practices

#### Guidelines

- **Make tests deterministic**: Use fixed dates, sorted collections, consistent ordering
- **Test meaningful changes**: Don't snapshot trivial variations
- **Use descriptive names**: `named: "dark_mode_large_text"` instead of `named: "test1"`
- **Review snapshot changes**: Always review generated snapshots during development
- **Keep snapshots small**: Large snapshots are hard to review and maintain

#### Memory Management with Snapshots

```swift
func testComplexView() {
    autoreleasepool {
        let window = SnapshotWindow()
        let view = ComplexView(data: testData)
        window.contentView = view
        
        assertSnapshot(of: view, as: .image())
    } // Ensures immediate cleanup
}
```

### ❌ When NOT to Use Snapshot Testing

- **Highly dynamic content**: Real-time data, user-specific content
- **Performance testing**: Snapshot testing is about correctness, not speed
- **Simple value comparisons**: Use `XCTAssertEqual` for basic assertions
- **Flaky systems**: Outputs that vary between runs

## Test Logging and Debugging

### Using Logger.tests for Test Information

All tests should use `Logger.tests` for logging instead of print statements or debug prints:

```swift
import os.log

func testComplexFlow() {
    Logger.tests.info("Starting complex flow test")
    Logger.tests.debug("Setting up test data with \(testData.count) items")
    
    // Perform test operations
    
    Logger.tests.log("Test completed successfully")
}
```

### Comprehensive Failure Logging

For CI debugging, provide comprehensive failure logs:

```swift
func testDataProcessing() {
    Logger.tests.info("Testing data processing with \(inputData.count) items")
    
    do {
        let result = try processor.process(inputData)
        Logger.tests.debug("Processing completed with \(result.count) results")
        
        XCTAssertEqual(result.count, expectedCount, 
                      "Expected \(expectedCount) results, got \(result.count). Input: \(inputData)")
    } catch {
        Logger.tests.error("Processing failed: \(error)")
        XCTFail("Processing failed with error: \(error)")
    }
}
```

**Best practices for failure logging**:
- Include relevant context in assertion messages
- Log the actual values that caused failures
- Use structured logging for complex data
- Include test setup information that might affect results

## Best Practices

### Test Naming

#### XCTest Syntax (traditional):
```swift
func testBookmarkCreation_WhenValidData_ShouldSucceed() { }
func testUserAuthentication_WithInvalidCredentials_ShouldFail() { }
```

#### @Test Syntax (Swift Testing - preferred for new tests):
```swift
@Test("Bookmark creation succeeds with valid data")
func bookmark_creation_with_valid_data() { }

@Test("User authentication fails with invalid credentials")
func user_authentication_fails_with_invalid_credentials() { }

@Test("External URLs are validated correctly")
func external_urls_are_valid() { }
```

#### @Test Naming Guidelines:
- Use clear, descriptive text in `@Test("description")`
- Function names should be simple and readable (no "test" prefix needed)
- Use underscores for better readability in function names
- Focus the description on what behavior is being verified

### Test Organization

Group related tests using `// MARK:` comments:

```swift
// MARK: - Bookmark Creation Tests
// MARK: - Bookmark Deletion Tests
```

### Async Testing

#### Basic Async Testing:
```swift
func testAsyncOperation() async {
    let result = await service.fetchData()
    XCTAssertNotNil(result)
}
```

#### Async Testing with Timeouts:
```swift
// Using withTimeout for async operations
func testAsyncOperationWithTimeout() async throws {
    let result = try await withTimeout(5.0) {
        return try await service.performLongOperation()
    }
    XCTAssertNotNil(result)
}

// Custom timeout error
func testAsyncOperationWithCustomError() async throws {
    do {
        _ = try await withTimeout(1.0, throwing: CustomTimeoutError()) {
            return try await service.performSlowOperation()
        }
        XCTFail("Should have timed out")
    } catch is CustomTimeoutError {
        // Expected timeout
    }
}
```

#### Publisher Testing with Timeouts:
```swift
// Testing publisher with timeout using extensions
func testPublisherWithTimeout() async throws {
    let subject = PassthroughSubject<String, Never>()
    
    // Use timeout extension for publishers
    let future = subject.timeout(2.0, "Publisher timeout").first().promise()
    
    // Simulate delayed value
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
        subject.send("test value")
    }
    
    let result = try await future.get()
    XCTAssertEqual(result, "test value")
}
```

#### Async Timeout Guidelines:
- Use `withTimeout()` for Task-based async operations - prevents indefinite hanging
- Use publisher `.timeout()` extensions for Combine workflows - handles stream timeouts gracefully
- Choose appropriate timeout values: Short for unit tests (1-5s), longer for integration tests (10s+)
- Always test timeout scenarios - ensure your code handles timeouts properly
- Use descriptive timeout messages - helps with debugging when timeouts occur

### Error Testing
Test both success and failure cases:

```swift
func testNetworkError_ShouldHandleGracefully() {
    // Test error handling
}
```

### Skipping Tests

Use `XCTSkip` to temporarily disable problematic tests:

```swift
// XCTest syntax
func testFlakySomething() throws {
    throw XCTSkip("Flaky test - temporarily disabled")
}

// @Test syntax
@Test("Temporarily disabled flaky test")
func flaky_behavior() throws {
    throw XCTSkip("Flaky test - investigating timing issues")
}
```

**XCTSkip Guidelines**:
- Use `throw XCTSkip("reason")` to temporarily disable flaky or problematic tests
- Function must be marked as `throws` to use XCTSkip
- Include a clear reason in the skip message for future investigation

## CI/CD Integration

Tests are automatically run in GitHub Actions with:
- Parallel execution for iOS and macOS
- Automatic log collection on failures
- JUnit report generation
- Crash report collection
- Asana integration for failure tracking

## Debugging Failed Tests

### 1. Check Logs
Download log artifacts from GitHub Actions

### 2. Reproduce Locally
Use command line tools for consistent reproduction:

```bash
# Use xcodebuild, set same environment variables as CI
xcodebuild -project macOS/DuckDuckGo.xcodeproj -scheme 'DuckDuckGo (macOS)' -configuration Debug -destination 'platform=macOS' test -only-testing:DuckDuckGo_Privacy_BrowserTests/TabViewModelTests/testDisplayedFaviconForAIChat

# Use swift test for BSK and shared packages
cd SharedPackages/BrowserServicesKit
swift test --filter NavigationTests.DistributedNavigationDelegateTests.testWhenCustomHeadersAreSet_headersAreSent
```

> ⚠️ **AI Assistant Note**: These commands are examples for manual execution only. Never run test commands automatically without explicit user permission.

### 3. Reproduce Flaky Tests
Reduce timeouts to increase failure rate locally:

```swift
// Temporarily reduce timeouts to catch race conditions
let shortTimeout = 0.1 // Instead of 5.0
XCTAssertTrue(element.waitForExistence(timeout: shortTimeout))
```

### 4. Run Multiple Times
Use Xcode's repeat testing options:
- **Test Navigator**: Right-click test → "Run [TestName] Repeatedly..."
- **Test Settings**: Set "Run" to repeat 10-100 times
- **Without Building**: Hold Option when clicking Run button for "Run Without Building"
- **Command Line**: Use `--repeat-count` with xcodebuild

### 5. Memory Debugging
Use Memory Browser and allocation tracking:

```bash
# Enable malloc stack logging for detailed memory traces
export MallocStackLogging=1

# Run tests with memory debugging
xcodebuild test -scheme YourScheme
```

**In Xcode**:
- **Memory Browser**: Debug → Debug Workflow → View Memory
- **Malloc Stack Logging**: Enable in scheme environment variables
- **AutoreleaseTracker**: Search for "AutoreleaseTracker" in Memory Browser to find leaked objects
- **Stack Traces**: View allocation stack traces for retained objects

---

**For questions or improvements to this guide, please contribute to the documentation or reach out to the iOS/macOS team.**