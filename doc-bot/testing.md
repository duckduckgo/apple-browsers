---
alwaysApply: false
title: "Testing Guidelines & Best Practices"
description: "Comprehensive testing practices and patterns for DuckDuckGo browser development across iOS and macOS platforms including unit tests, mocks, memory management, advanced testing techniques, time/date testing patterns, and critical async testing anti-patterns to avoid"
keywords: ["testing", "unit tests", "XCTest", "mocks", "async testing", "UI tests", "performance tests", "memory management", "snapshot testing", "MockFeatureFlagger", "Tab Extensions", "BSK tests", "event-driven testing", "timing anti-patterns", "DispatchQueue", "Timer", "expectations", "TestClock", "MockDateProvider", "TimeTraveller", "Sleeper", "time injection", "date provider"]
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

#### Privacy Subfeature Configuration

```swift
// Configure privacy subfeatures (separate from feature flags)
override func setUpWithError() throws {
    app = XCUIApplication.setUp(privacySubfeatures: [
        "autoconsent-filterlist": true,
        "tracker-allowlist": true
    ])
    // Privacy subfeatures are applied via PRIVACY_SUBFEATURES environment variable
}

// Combined feature flags and privacy subfeatures
app = XCUIApplication.setUp(
    featureFlags: [
        "contextualOnboarding": true
    ],
    privacySubfeatures: [
        "autoconsent-filterlist": true
    ]
)
```

**❗Why Feature Flag and Privacy Subfeature Configuration is Critical**:
- UI tests run against notarized builds - feature flags can't be changed at runtime
- MockFeatureFlagger is NOT available in UI tests (only real DefaultFeatureFlagger)
- Feature flags must be configured via FEATURE_FLAGS environment variable before app launch
- **Privacy subfeatures are controlled by PrivacyConfiguration, not feature flags**
- Privacy subfeatures must be configured via PRIVACY_SUBFEATURES environment variable
- Incorrect feature/subfeature state will cause UI tests to fail when expected UI elements don't appear

**Key Differences**:
- **Feature Flags**: Control app features (e.g., `contextualOnboarding`, `duckPlayer`)
- **Privacy Subfeatures**: Control privacy functionality (e.g., `autoconsent-filterlist`, `tracker-allowlist`)
- Both use separate environment variables and configuration systems

### XCUIElement Query Best Practices

#### CRITICAL: XCUIElement Queries Are Always Live
**XCUIElement queries are always valid and re-query the UI when accessed (e.g., `exists`, `waitForExistence`). No need to create "fresh" element references:**

```swift
// ✅ CORRECT: Reuse the same element reference
class FeatureUITests: UITestCase {
    private var addressBarTextField: XCUIElement!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        
        // Get address bar reference once
        addressBarTextField = app.addressBar
    }
    
    func testAddressBarNavigation() throws {
        // Type URL and navigate
        addressBarTextField.typeText("example.com")
        addressBarTextField.typeKey(.enter, modifierFlags: [])
        
        // Wait for navigation - validate specific content, not generic webView existence
        let webView = app.webViews.firstMatch
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 30.0), "Should navigate to example.com and show page content")
        
        // ✅ CORRECT: Reuse original reference - XCUIElement queries are live
        app.activateAddressBar() // Use helper method instead of manual Cmd+L
        XCTAssertTrue(addressBarTextField.exists, "Address bar should still be accessible")
        
        // ✅ CORRECT: The same element reference works after navigation
        addressBarTextField.typeText("another-site.com")
    }
}

// ❌ INCORRECT: Creating "fresh" element references unnecessarily
func testBadPattern() {
    addressBarTextField.typeText("example.com")
    
    // ❌ Wrong: No need to create fresh reference
    let freshAddressBar = app.textFields["AddressBarViewController.addressBarTextField"]
    let currentAddressBar = app.textFields["AddressBarViewController.addressBarTextField"]
    
    // The original addressBarTextField reference is still valid!
}
```

### Test Assertions Must Be Precise

**CRITICAL RULE**: All test checks must be predictable and precise. Avoid OR-conditions, Thread.sleep(), and vague checks.

```swift
// ❌ WRONG - Vague OR-conditions with sleep
Thread.sleep(forTimeInterval: 1.0)
let someUIVisible = element1.exists || element2.exists || element3.exists
XCTAssertTrue(someUIVisible, "Some UI should be accessible")

// ❌ WRONG - Using XCTNSPredicateExpectation for simple element waiting
let webView = app.webViews.firstMatch
let pageLoaded = XCTNSPredicateExpectation(
    predicate: NSPredicate(format: "exists == true"),
    object: webView
)
XCTAssertEqual(XCTWaiter.wait(for: [pageLoaded], timeout: 15.0), .completed)

// ❌ WRONG - Using 'if' statements for button waiting
if runButton.waitForExistence(timeout: 5.0) {
    runButton.click()
}

// ✅ CORRECT - Use waitForExistence with assertion for simple element waiting
XCTAssertTrue(runButton.waitForExistence(timeout: 15.0), "Run button should be available")
runButton.click()

// ✅ BEST PRACTICE - Wait for the actual element you need, not its container
// Don't wait for webView if you need a button inside it - button existence implies page loaded
let runButton = app.webViews.buttons["run"]
XCTAssertTrue(runButton.waitForExistence(timeout: 15.0), "Run button should be available")
runButton.click()

// ✅ CORRECT - Use XCTNSPredicateExpectation only for complex conditions
let complexCondition = XCTNSPredicateExpectation(
    predicate: NSPredicate(format: "count > 2"),
    object: app.tables.cells
)
XCTAssertEqual(XCTWaiter.wait(for: [complexCondition], timeout: 5.0), .completed)
```

**Prohibited Patterns:**
- `Thread.sleep()` - Use `waitForExistence` or `XCTNSPredicateExpectation` instead
- OR-conditions (`||`) in assertions - Test one specific state
- Vague "should be accessible" - Test specific elements and values
- Fallback checks - If primary check fails, test should fail clearly
- `if button.waitForExistence()` - Use `XCTAssertTrue(button.waitForExistence())` instead
- Complex `XCTNSPredicateExpectation` for simple existence checks - Use `waitForExistence` directly

#### Address Bar Usage Pattern
**Use the extension property and follow activation rules:**

```swift
func testAddressBarInteraction() {
    // ✅ CORRECT: Use extension property
    let addressBar = app.addressBar
    XCTAssertTrue(addressBar.waitForExistence(timeout: 5.0))
    
    // ✅ CORRECT: On new tab page, address bar is already activated - no Cmd+L needed
    addressBar.typeText("example.com")
    addressBar.typeKey(.enter, modifierFlags: [])
    
    // Wait for navigation
    Thread.sleep(forTimeInterval: 3.0)
    
    // ✅ REQUIRED: After navigation, activate address bar before further interaction
    app.activateAddressBar()  // Use extension method instead of direct Cmd+L
    
    // Now the address bar is ready for input
    addressBar.typeText("another-site.com")
    addressBar.typeKey(.enter, modifierFlags: [])
}

// ❌ INCORRECT: Don't create your own addressBar reference
func testBadPattern() {
    let addressBarTextField = app.textFields["AddressBarViewController.addressBarTextField"]  // ❌ Use app.addressBar instead
    
    // ❌ INCORRECT: Don't use Cmd+L on new tab pages
    app.typeKey("l", modifierFlags: [.command])  // Address bar is already activated on new tabs
    addressBarTextField.typeText("example.com")
}
```

**Address Bar Activation Rules**:
- ✅ **NEW TAB PAGE**: Address bar is already activated - do NOT use `Cmd+L`
- ✅ **AFTER NAVIGATION**: Address bar becomes read-only - USE `app.activateAddressBar()` before typing
- ✅ **USE EXTENSION**: Always use `app.addressBar` instead of creating your own reference
- ✅ **USE HELPER METHOD**: Use `app.activateAddressBar()` instead of direct `Cmd+L`

#### Element Query Guidelines

```swift
// ✅ CORRECT: Use element references efficiently
class MyUITests: UITestCase {
    private var addressBar: XCUIElement!
    private var webView: XCUIElement!
    
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        
        // Create element references once
        addressBar = app.textFields["AddressBarViewController.addressBarTextField"]
        webView = app.webViews.firstMatch
    }
    
    func testNavigation() {
        // Use the same references throughout the test
        XCTAssertTrue(addressBar.waitForExistence(timeout: 5.0))
        
        addressBar.typeText("example.com")
        addressBar.typeKey(.enter, modifierFlags: [])
        
        // Wait for specific page content, not generic webView existence
        let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
        XCTAssertTrue(pageContent.waitForExistence(timeout: 10.0), "Should show example.com page content")
        
        // After navigation, activate address bar for new input
        app.activateAddressBar()
        
        // Same addressBar reference is still valid
        addressBar.typeText("duckduckgo.com")
    }
}

// ❌ INCORRECT: Don't create multiple references to same element
func testBadElementHandling() {
    let addressBar1 = app.textFields["AddressBarViewController.addressBarTextField"]
    addressBar1.typeText("example.com")
    
    // ❌ Unnecessary - addressBar1 is still valid
    let addressBar2 = app.textFields["AddressBarViewController.addressBarTextField"] 
    let freshAddressBar = app.textFields["AddressBarViewController.addressBarTextField"]
    
    // All three references point to the same element!
}
```

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

#### Helper Method Organization

**CRITICAL: Move common helper methods to `XCUIApplication` extensions instead of duplicating them across test classes:**

```swift
// ❌ BAD: Duplicating helper methods across test classes
class FeatureUITests: UITestCase {
    private func setupSingleWindow() {
        app.typeKey("w", modifierFlags: [.command, .option, .shift])
        app.typeKey("n", modifierFlags: .command)
    }
}

class AnotherFeatureUITests: UITestCase {
    private func setupSingleWindow() {  // ❌ Duplicate!
        app.typeKey("w", modifierFlags: [.command, .option, .shift])
        app.typeKey("n", modifierFlags: .command)
    }
}

// ✅ GOOD: Use existing extension methods or add new ones to XCUIApplicationExtension.swift
class FeatureUITests: UITestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication.setUp()
        
        // Use existing extension method
        app.enforceSingleWindow()  // ✅ Already exists in XCUIApplicationExtension.swift
    }
}

// ✅ GOOD: Add new helper methods to the extension for reuse
extension XCUIApplication {
    /// Navigate to a URL and wait for page load
    /// - Parameter url: The URL to navigate to
    /// - Parameter timeout: Timeout for page load wait
    /// - Parameter isNewTab: Whether this is happening on a new tab (affects address bar activation)
    func navigateToURL(_ url: String, timeout: TimeInterval = 10.0, isNewTab: Bool = false) -> Bool {
        guard addressBar.waitForExistence(timeout: 5.0) else { return false }
        
        // Only activate address bar if not on a new tab (new tabs have address bar pre-activated)
        if !isNewTab {
            activateAddressBar()
        }
        
        addressBar.typeText(url)
        addressBar.typeKey(.enter, modifierFlags: [])
        
        // Wait for specific content rather than generic webView existence
        let webView = webViews.firstMatch
        let pageContent = webView.staticTexts.firstMatch
        return pageContent.waitForExistence(timeout: timeout)
    }
    
    /// Open downloads popup and verify it appears
    func openDownloadsPopup() -> Bool {
        typeKey("j", modifierFlags: [.command])
        let downloadsPopup = windows.containing(.any).firstMatch
        return downloadsPopup.waitForExistence(timeout: 5.0)
    }
}
```

**Available Extension Properties and Methods:**
- `app.addressBar` → Address bar text field element (replaces manual `app.textFields["AddressBarViewController.addressBarTextField"]`)
- `app.enforceSingleWindow()` → Close all windows and open new one (replaces `setupSingleWindow()`)
- `app.activateAddressBar()` → Activate address bar for input (replaces direct `Cmd+L`)
- `app.openNewTab()` → Open new tab via `Cmd+T`
- `app.resetBookmarks()` → Reset bookmarks for testing
- `app.openBookmarksManager()` → Open bookmarks manager
- `app.openBookmarksPanel()` → Show bookmarks panel

**Common patterns that should be moved to extensions:**
- `setupSingleWindow()` → Use existing `enforceSingleWindow()`
- Manual address bar references → Use `app.addressBar`
- Direct `Cmd+L` usage → Use `app.activateAddressBar()`
- URL navigation helpers → `navigateToURL(_:timeout:)`
- Downloads popup helpers → `openDownloadsPopup()`
- Common assertion patterns → Extension methods

**Benefits of using extension methods:**
- ✅ **No duplication** - Write once, use everywhere
- ✅ **Consistent behavior** - Same implementation across all tests
- ✅ **Easier maintenance** - Fix bugs in one place
- ✅ **Better discoverability** - Other developers can find and reuse helpers
- ✅ **Cleaner test files** - Focus on test logic, not boilerplate

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
- **NEVER use `Thread.sleep()` or `Task.sleep()` in tests** - they're unreliable, slow tests down, and create flaky tests
- Use helper methods that combine existence checks with actions - they're more reliable
- Use `UITests.Timeouts` constants for consistent timeout values across tests

### 🚫 CRITICAL: UI Testing Anti-Patterns - NEVER USE THESE

#### ❌ Anti-Pattern #1: Thread.sleep and Arbitrary Delays
**NEVER USE:**
```swift
// ❌ FORBIDDEN: Thread.sleep() 
Thread.sleep(forTimeInterval: 2.0)

// ❌ FORBIDDEN: DispatchQueue.main.asyncAfter
DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
    // test logic
}

// ❌ FORBIDDEN: Any fixed time delays
usleep(2000000)
```

**✅ USE INSTEAD:**
```swift
// ✅ CORRECT: Use waitForExistence with appropriate timeout
XCTAssertTrue(element.waitForExistence(timeout: 10.0), "Element should appear")

// ✅ CORRECT: Use waitForNonExistence for disappearing elements
XCTAssertTrue(element.waitForNonExistence(timeout: 5.0), "Element should disappear")

// ✅ CORRECT: Use XCTNSPredicateExpectation for complex conditions
let webView = app.webViews.firstMatch
let pageLoaded = XCTNSPredicateExpectation(
    predicate: NSPredicate(format: "exists == true"),
    object: webView
)
let result = XCTWaiter.wait(for: [pageLoaded], timeout: 30.0)
```

#### ❌ Anti-Pattern #2: Validation Branching (if/else Logic)
**NEVER USE:**
```swift
// ❌ FORBIDDEN: if/else validation branching
if button.waitForExistence(timeout: 5.0) {
    button.click()
    // test logic
} else {
    XCTAssertTrue(true, "Button not available")
}

// ❌ FORBIDDEN: Combined conditional checks
if button.waitForExistence(timeout: 5.0) && button.isEnabled {
    // test logic
} else {
    XCTAssertTrue(true, "fallback message")
}
```

**✅ USE INSTEAD:**
```swift
// ✅ CORRECT: Direct assertions that fail clearly
XCTAssertTrue(button.waitForExistence(timeout: 5.0), "Button should be available")
XCTAssertTrue(button.isEnabled, "Button should be enabled")
button.click()

// ✅ CORRECT: Use XCTFail for impossible conditions
XCTAssertTrue(element.waitForExistence(timeout: 10.0), "Element should exist")
// If element doesn't exist, test fails clearly - no fallback needed
```

#### ❌ Anti-Pattern #3: Cop-Out Assertions
**NEVER USE:**
```swift
// ❌ FORBIDDEN: XCTAssertTrue(true) cop-outs
XCTAssertTrue(true, "Test completed - implementation may vary")

// ❌ FORBIDDEN: print() instead of assertions
if condition {
    // test logic
} else {
    print("Feature not available in test environment") // ❌ NO!
}
```

**✅ USE INSTEAD:**
```swift
// ✅ CORRECT: Meaningful assertions that can fail
XCTAssertEqual(actualCount, expectedCount, "Should have exact number of elements")

// ✅ CORRECT: Use XCTFail for impossible conditions
if !element.waitForExistence(timeout: 10.0) {
    XCTFail("Critical element should always be available")
}
```

#### ❌ Anti-Pattern #4: Generic WebView Existence Checks
**NEVER USE:**
```swift
// ❌ FORBIDDEN: Pointless webView.waitForExistence()
XCTAssertTrue(webView.waitForExistence(timeout: 30.0), "Page should load")
```

**✅ USE INSTEAD:**
```swift
// ✅ CORRECT: Wait for specific content
let expectedContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'expected text'")).firstMatch
XCTAssertTrue(expectedContent.waitForExistence(timeout: 30.0), "Page should show expected content")

// ✅ CORRECT: Validate specific page elements
let pageTitle = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Welcome'")).firstMatch
XCTAssertTrue(pageTitle.waitForExistence(timeout: 15.0), "Welcome page should load")
```

#### ❌ Anti-Pattern #5: typeURL() Usage
**NEVER USE:**
```swift
// ❌ FORBIDDEN: typeURL() is unreliable
addressBarTextField.typeURL(url)
```

**✅ USE INSTEAD:**
```swift
// ✅ CORRECT: Use pasteURL() with pressingEnter
addressBarTextField.pasteURL(url, pressingEnter: true)
```

#### ❌ Anti-Pattern #6: Manual Cmd+L for Address Bar Activation
**NEVER USE:**
```swift
// ❌ FORBIDDEN: Manual keyboard shortcuts
app.typeKey("l", modifierFlags: [.command])
```

**✅ USE INSTEAD:**
```swift
// ✅ CORRECT: Use dedicated helper method
app.activateAddressBar()
```

#### ❌ Anti-Pattern #7: Incorrect NSPredicate Usage
**NEVER USE:**
```swift
// ❌ FORBIDDEN: label CONTAINS in predicates
NSPredicate(format: "label CONTAINS 'search-text'")
```

**✅ USE INSTEAD:**
```swift
// ✅ CORRECT: value CONTAINS for UI elements
NSPredicate(format: "value CONTAINS 'search-text'")
```

### Privacy Button Access
```swift
// ✅ CORRECT: Use the proper accessibility identifier
let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
```

#### ❌ Anti-Pattern #8: Windows for Tab Counting
**NEVER USE:**
```swift
// ❌ FORBIDDEN: Using windows.count for tabs in tabbed browser
let tabCount = app.windows.count
```

**✅ USE INSTEAD:**
```swift
// ✅ CORRECT: Use tabGroups for counting tabs
let tabCount = app.tabGroups.count
```

#### ❌ Anti-Pattern #9: Incorrect Modifier Clicks
**NEVER USE:**
```swift
// ❌ FORBIDDEN: These don't work or are unreliable
element.click(forDuration: 0.1, thenDragTo: element)
element.tap()
element.rightClick() // for modifier clicks
```

**✅ USE INSTEAD:**
```swift
// ✅ CORRECT: Use perform(withKeyModifiers:)
element.perform(withKeyModifiers: [.option]) {
    element.click()
}
```

### 🔍 Debug Operator: `???` for Optional String Conversion

The `???` operator provides safe string conversion for debugging:

```swift
// ✅ CORRECT: Debug string conversion with ??? operator
Logger.general.debug("event received: \(event ??? "<nil>")")
XCTAssertTrue(element.exists, "Element should exist: \(optionalValue ??? "missing")")
```

**What it does:**
- **Converts any optional to String** for debugging/logging
- **Uses `String(describing:)` if value exists**
- **Falls back to provided default string if nil**
- **Safer than force unwrapping** for debug output

### 🔍 Debugging Pattern: UI Snapshot Logging

When UI tests fail and you need to see the actual element hierarchy:

```swift
// ✅ CORRECT: UI snapshot debugging for failed assertions  
XCTAssertTrue(element.waitForExistence(timeout: 5.0), 
    "Element should exist: \((try? parentElement.snapshot().toDictionary()) ??? "snapshot failed")")
```

**When to use:**
- **UI tests fail unexpectedly** and you need to see what's actually there
- **Element queries don't find expected elements**
- **Debugging privacy dashboard content**, context menus, or complex UI
- **Only during debugging** - remove before committing

**Key Points:**
- Use `(try? element.snapshot().toDictionary())` to safely get UI hierarchy
- Use `??? "fallback"` to handle snapshot failures
- Provides complete element tree structure when tests fail
- Remove debugging code before final commit

### ⚠️ ENFORCEMENT: These Rules Are MANDATORY

- **Every UI test MUST follow these patterns**
- **No exceptions for "quick fixes" or "temporary solutions"**
- **All existing tests MUST be refactored to follow these patterns**
- **Code reviews MUST check for these anti-patterns**

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
- Looks for files in its current working directory or accepts dynamic content via `data` parameter

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

### UI Test Debugging with View Hierarchy Snapshots

When debugging UI test failures, use the `toDictionary()` helper method to capture and inspect the complete view hierarchy:

```swift
// ✅ CORRECT: Debug view hierarchy when UI elements aren't found as expected
func testComplexUIInteraction() {
    let webView = app.webViews.firstMatch
    let runButton = webView.buttons["Start"]
    
    if !runButton.waitForExistence(timeout: 5.0) {
        // Capture view hierarchy for debugging
        let snapshot = try! webView.snapshot().toDictionary()
        print("WebView hierarchy:\n\(snapshot)")
        XCTFail("Start button not found in webView")
    }
    
    runButton.click()
}

// ✅ CORRECT: Include hierarchy in assertion failure messages
func testAddressBarBehavior() {
    app.activateAddressBar()
    let addressBarValue = addressBarTextField.value as? String ?? ""
    
    if addressBarValue.isEmpty {
        // Include snapshot in failure message for debugging
        let snapshot = try! app.snapshot().toDictionary()
        XCTAssertFalse(addressBarValue.isEmpty, 
                      "Address bar should have content, got: \(addressBarValue)\n\(snapshot)")
    }
}
```

**Available snapshot properties** (customizable via `keys` parameter):
- `elementType`: UI element type (button, textField, etc.)
- `identifier`: Accessibility identifier
- `label`: Accessibility label
- `title`: Element title
- `value`: Current value
- `isEnabled`: Whether element is enabled
- `frame`: Element position and size
- `children`: Nested elements (automatically included)

```swift
// ✅ CORRECT: Custom properties for specific debugging needs
let snapshot = try! element.snapshot().toDictionary(keys: [
    "elementType", "identifier", "label", "isEnabled"
])

// ✅ CORRECT: Full default properties for comprehensive debugging
let snapshot = try! element.snapshot().toDictionary()
```

**When to use view hierarchy debugging**:
- Element not found when expected to exist
- UI interaction failing unexpectedly
- Need to understand complex nested view structures
- Debugging test flakiness related to UI timing
- Adding detailed context to assertion failure messages

**Best practices**:
- Use sparingly in production tests (only for debugging)
- Include snapshots in assertion failure messages for context
- Remove debug snapshots once issues are resolved
- Use custom `keys` parameter to focus on relevant properties

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

**NEVER use `print()` in tests. ALWAYS use `Logger.tests` for debug output:**

```swift
import os.log

✅ // GOOD: Use Logger.tests for test debugging
func testComplexFlow() {
    Logger.tests.info("Starting complex flow test")
    Logger.tests.debug("Setting up test data with \(testData.count) items")
    Logger.tests.debug("DEBUG: requestCount = \(requestCount), currentState = \(service.currentState)")
    
    // Perform test operations
    
    Logger.tests.log("Test completed successfully")
}

❌ // BAD: Using print() statements
func testComplexFlow() {
    print("Starting test")  // Never use print()
    print("DEBUG: requestCount = \(requestCount)")  // Use Logger.tests.debug() instead
}
```

**Benefits of Logger.tests:**
- Structured logging that integrates with Xcode and CI systems
- Proper log levels (info, debug, error)
- Automatic collection in CI artifacts
- Better performance than print() statements

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
    
    DispatchQueue.main.async {
        subject.send("test value")
    }
    
    let result = try await future.get()
    XCTAssertEqual(result, "test value")
}

// For testing actual async behavior, use proper event-driven patterns:
func testPublisherWithAsyncBehavior() {
    let expectation = expectation(description: "Should receive published value")
    let subject = PassthroughSubject<String, Never>()
    
    let cancellable = subject
        .sink { value in
            XCTAssertEqual(value, "test value")
            expectation.fulfill()
        }
    
    // Trigger the real event that should cause publication
    service.performActionThatPublishes() // This internally calls subject.send()
    
    wait(for: [expectation], timeout: 1.0)
    cancellable.cancel()
}
```

#### Async Timeout Guidelines:
- Use `withTimeout()` for Task-based async operations - prevents indefinite hanging
- Use publisher `.timeout()` extensions for Combine workflows - handles stream timeouts gracefully
- Choose appropriate timeout values: Short for unit tests (1-5s), longer for integration tests (10s+)
- Always test timeout scenarios - ensure your code handles timeouts properly
- Use descriptive timeout messages - helps with debugging when timeouts occur

## 🚨 CRITICAL: Async Testing Anti-Patterns

### ❌ NEVER Use These Timing Patterns in Tests

**NEVER use arbitrary delays in tests - they make tests flaky, slow, and unreliable:**

```swift
❌ // BAD: Arbitrary time delays
func testBadPattern() {
    // NEVER DO THIS
    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
        expectation.fulfill()
    }
    
    // OR THIS
    Timer.scheduledTimer(withTimeInterval: 2.0, repeats: false) { _ in
        expectation.fulfill()
    }
    
    // OR THIS
    Thread.sleep(forTimeInterval: 0.5)
    
    wait(for: [expectation], timeout: 5.0)
}
```

### ✅ Use Event-Driven Testing Instead

**Replace timing delays with event-driven expectations:**

#### Pattern 1: Callback-Based Expectations
```swift
✅ // GOOD: Event-driven testing with callbacks
class MockService {
    var onEventTriggered: (() -> Void)?
    
    func triggerEvent() {
        // Do work...
        onEventTriggered?() // Signal completion
    }
}

func testGoodPattern() {
    let expectation = expectation(description: "Event should be triggered")
    
    mockService.onEventTriggered = {
        expectation.fulfill()
    }
    
    // Trigger the actual event
    mockService.triggerEvent()
    
    wait(for: [expectation], timeout: 1.0) // Short timeout for deterministic events
}
```

#### Pattern 2: Publisher-Based Expectations
```swift
✅ // GOOD: Combine publisher testing
func testPublisherPattern() {
    let expectation = expectation(description: "Publisher should emit value")
    
    let cancellable = service.statePublisher
        .compactMap { $0 }
        .first()
        .sink { value in
            XCTAssertEqual(value, .expectedState)
            expectation.fulfill()
        }
    
    // Trigger the state change
    service.updateState(.expectedState)
    
    wait(for: [expectation], timeout: 1.0)
    cancellable.cancel()
}
```

#### Pattern 3: Predicate-Based Expectations
```swift
✅ // GOOD: Condition-based waiting
func testPredicatePattern() {
    // Trigger the operation
    service.startOperation()
    
    // Wait for specific condition to be true
    let predicate = NSPredicate { _, _ in
        service.isOperationComplete
    }
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: nil)
    wait(for: [expectation], timeout: 2.0)
    
    XCTAssertTrue(service.isOperationComplete)
}
```

#### Pattern 4: Inverted Expectations for "Should Not Happen"
```swift
✅ // GOOD: Testing that something should NOT happen
func testShouldNotHappen() {
    let expectation = expectation(description: "Should not trigger unwanted behavior")
    expectation.isInverted = true // Test passes if expectation is NOT fulfilled
    
    mockService.onUnwantedEvent = {
        expectation.fulfill() // This would fail the test
    }
    
    // Trigger some action
    service.performAction()
    
    wait(for: [expectation], timeout: 1.0) // Short timeout for negative tests
    
    // Verify expected behavior occurred instead
    XCTAssertTrue(service.didPerformExpectedBehavior)
}
```

### Why Event-Driven Testing Is Superior

1. **Deterministic**: Tests wait for actual events, not arbitrary time
2. **Fast**: No unnecessary delays - tests complete as soon as events occur  
3. **Reliable**: Eliminates race conditions and timing-dependent failures
4. **Maintainable**: Clear relationship between triggers and expectations
5. **Debuggable**: Failures point to actual logic issues, not timing problems

### Migration Strategy

When you see these patterns in existing tests:
1. **Identify the real event** the test is waiting for
2. **Add callback/publisher** to the mock or service to signal that event
3. **Replace arbitrary delays** with event-driven expectations
4. **Use shorter timeouts** (1-2s) since events are deterministic

**Remember: Good tests are event-driven, not time-driven!**

## ⏰ Time/Date Testing Patterns

### Critical Design Principle
**ALWAYS inject time/date dependencies into your classes - NEVER use `Date()` or `Task.sleep()` directly in production code that needs testing.**

### 🚫 **FORBIDDEN: Task.sleep() in Tests**

**NEVER use `Task.sleep()` in any test code:**

```swift
// ❌ NEVER DO THIS
try await Task.sleep(nanoseconds: 100_000_000) // Creates flaky tests
try await Task.sleep(for: .seconds(1))         // Unreliable timing
try? await Task.sleep(interval: 0.1)           // Arbitrary delays

// ✅ DO THIS INSTEAD
let expectation = expectation(description: "Wait for async operation")
someAsyncOperation {
    expectation.fulfill()
}
await fulfillment(of: [expectation], timeout: 1.0)
```

**Why `Task.sleep()` is banned:**
1. **Flaky tests** - Real-world timing varies
2. **Slow tests** - Fixed delays waste time 
3. **Unreliable** - May not wait long enough or wait too long
4. **Hides race conditions** - Masks real timing issues

### Timeout Guidelines

- Keep test timeouts reasonable: **maximum 5 seconds** for most async operations
- Use shorter timeouts (1-3 seconds) when possible to catch issues faster
- Only use longer timeouts for truly slow operations (network requests, file I/O)

### 🚫 **NEVER Change Tests to Match Wrong Behavior**

**When tests fail, fix the code, not the test:**

```swift
// ❌ WRONG: Changing test to match broken behavior
XCTAssertEqual(result.count, 3, "Should return 3 items") // Changed from 5 to 3 to make test pass

// ✅ RIGHT: Fix the actual code issue
// Fix the logic to properly return all expected items
XCTAssertEqual(result.count, 5, "Should return all 5 items as originally designed")
```

**Tests should verify correct behavior, not accommodate bugs. If a test fails:**
1. **First** - Check if the production code has a bug
2. **Fix the bug** in the production code  
3. **Only then** update the test if the expected behavior has legitimately changed

**Never adjust tests to hide problems in the implementation.**

When a class needs current time or sleep functionality, inject these dependencies through the initializer:

```swift
✅ // GOOD: Injectable time dependencies
class MyService {
    private let dateProvider: () -> Date
    private let sleeper: Sleeper
    
    init(dateProvider: @escaping () -> Date = Date.init,
         sleeper: Sleeper = .default) {
        self.dateProvider = dateProvider
        self.sleeper = sleeper
    }
    
    func performOperation() async throws {
        let now = dateProvider() // ✅ Testable
        // ... do work ...
        try await sleeper.sleep(for: 1.0) // ✅ Testable
    }
}

❌ // BAD: Hard-coded time dependencies
class MyService {
    func performOperation() async throws {
        let now = Date() // ❌ Not testable
        // ... do work ...
        try await Task.sleep(nanoseconds: 1_000_000_000) // ❌ Not testable
    }
}
```

### Pattern 1: TestClock for Async Sleep Testing

**Use `TestClock<Duration>` for testing code that uses `Task.sleep()` or periodic operations:**

```swift
✅ // GOOD: TestClock pattern for async sleep testing
func testPeriodicUpdates() async throws {
    let clock = TestClock<Duration>()
    let sleeper = Sleeper(clock: clock)
    
    // Inject the test sleeper
    let service = MyPeriodicService(sleeper: sleeper, interval: 2.0)
    
    let expectation1 = expectation(description: "First update")
    let expectation2 = expectation(description: "Second update")
    
    var updateCount = 0
    service.onUpdate = {
        updateCount += 1
        if updateCount == 1 {
            expectation1.fulfill()
        } else if updateCount == 2 {
            expectation2.fulfill()
        }
    }
    
    // Start the periodic task
    let task = service.startPeriodicUpdates()
    
    // Wait for first update (immediate)
    await fulfillment(of: [expectation1], timeout: 1.0)
    XCTAssertEqual(updateCount, 1)
    
    // Advance clock by 2 seconds to trigger next update
    await clock.advance(by: .seconds(2))
    await fulfillment(of: [expectation2], timeout: 1.0)
    XCTAssertEqual(updateCount, 2)
    
    task.cancel()
}

// Production service with injectable sleeper
class MyPeriodicService {
    private let sleeper: Sleeper
    private let interval: TimeInterval
    var onUpdate: (() -> Void)?
    
    init(sleeper: Sleeper = .default, interval: TimeInterval) {
        self.sleeper = sleeper
        self.interval = interval
    }
    
    func startPeriodicUpdates() -> Task<Void, Error> {
        Task.periodic(interval: interval, sleeper: sleeper) {
            await self.performUpdate()
        }
    }
    
    private func performUpdate() async {
        // Do work...
        onUpdate?()
    }
}
```

#### TestClock Best Practices

**ALWAYS use `Task.megaYield(count: N)` after `clock.advance()` to allow async processing:**

```swift
✅ // GOOD: Proper megaYield usage
await clock.advance(by: .seconds(5))
await Task.megaYield(count: 5)  // Allow async tasks to process

❌ // BAD: Multiple consecutive megaYield calls
await clock.advance(by: .seconds(5))
await Task.megaYield()
await Task.megaYield()
await Task.megaYield()

❌ // BAD: No megaYield after clock advance
await clock.advance(by: .seconds(5))
// Missing yield - async tasks may not complete
```

**Why `megaYield` is critical:**
- TestClock advancement is synchronous, but triggered async tasks need time to process
- `megaYield(count: N)` ensures async operations complete before assertions
- Use `count: 5` as a standard (allows multiple yield cycles)

### Pattern 2: MockDateProvider for Date Testing

**Use `MockDateProvider` or `TimeTraveller` for testing code that needs current date:**

```swift
✅ // GOOD: MockDateProvider pattern
class MockDateProvider {
    private var date: Date
    
    init(date: Date = Date()) {
        self.date = date
    }
    
    func setNowDate(_ date: Date) {
        self.date = date
    }
    
    func advanceBy(_ timeInterval: TimeInterval) {
        date.addTimeInterval(timeInterval)
    }
    
    func getDate() -> Date {
        date
    }
}

func testDateBasedLogic() {
    let mockDateProvider = MockDateProvider(date: Date(timeIntervalSince1970: 0))
    let service = MyService(dateProvider: mockDateProvider.getDate)
    
    // Test with specific date
    let result1 = service.processData()
    XCTAssertEqual(result1.timestamp, Date(timeIntervalSince1970: 0))
    
    // Advance time and test again
    mockDateProvider.advanceBy(TimeInterval.days(1))
    let result2 = service.processData()
    XCTAssertEqual(result2.timestamp, Date(timeIntervalSince1970: 86400))
}

// Production service with injectable date provider
class MyService {
    private let dateProvider: () -> Date
    
    init(dateProvider: @escaping () -> Date = Date.init) {
        self.dateProvider = dateProvider
    }
    
    func processData() -> DataResult {
        return DataResult(timestamp: dateProvider(), data: "...")
    }
}
```

### Pattern 3: Protocol-Based Date Injection

**For more complex date/time scenarios, use protocol injection:**

```swift
✅ // GOOD: Protocol-based date injection
protocol CurrentDateProviding {
    var currentDate: Date { get }
}

extension Date: CurrentDateProviding {
    public var currentDate: Date { self }
}

class MockDateProvider: CurrentDateProviding {
    var currentDate: Date
    
    init(currentDate: Date = Date()) {
        self.currentDate = currentDate
    }
}

class MyService {
    private let dateProvider: CurrentDateProviding
    
    init(dateProvider: CurrentDateProviding = Date()) {
        self.dateProvider = dateProvider
    }
    
    func isExpired(_ item: Item) -> Bool {
        return item.expiryDate < dateProvider.currentDate
    }
}

func testExpiryLogic() {
    let mockDateProvider = MockDateProvider(currentDate: Date(timeIntervalSince1970: 1000))
    let service = MyService(dateProvider: mockDateProvider)
    
    let expiredItem = Item(expiryDate: Date(timeIntervalSince1970: 500))
    let validItem = Item(expiryDate: Date(timeIntervalSince1970: 1500))
    
    XCTAssertTrue(service.isExpired(expiredItem))
    XCTAssertFalse(service.isExpired(validItem))
}
```

### Pattern 4: Combined TestClock and MockDateProvider

**For services that need both current time and sleep capabilities:**

```swift
✅ // GOOD: Combined time and sleep mocking
func testServiceWithTimeAndSleep() async throws {
    let mockDateProvider = MockDateProvider(date: Date(timeIntervalSince1970: 0))
    let clock = TestClock<Duration>()
    let sleeper = Sleeper(clock: clock)
    
    let service = MyTimedService(
        dateProvider: mockDateProvider.getDate,
        sleeper: sleeper
    )
    
    let expectation = expectation(description: "Operation should complete")
    
    service.onOperationComplete = { result in
        // Verify the result includes the correct timestamp
        XCTAssertEqual(result.startTime, Date(timeIntervalSince1970: 0))
        expectation.fulfill()
    }
    
    // Start operation
    let task = service.startOperation()
    
    // Advance mock time (affects dateProvider)
    mockDateProvider.advanceBy(5.0)
    
    // Advance test clock (affects sleeper)
    await clock.advance(by: .seconds(1))
    
    await fulfillment(of: [expectation], timeout: 1.0)
    task.cancel()
}
```

### Time Testing Best Practices

1. **Always inject time dependencies** - Never use `Date()` or `Task.sleep()` directly in production code
2. **Use TestClock for async operations** - When testing `Task.sleep()`, `Task.periodic`, or `Sleeper`
3. **Use MockDateProvider for date logic** - When testing date comparisons, timestamps, or date-based decisions
4. **Test time progression** - Use `advance()` methods to test how your code behaves over time
5. **Test boundary conditions** - Test behavior at midnight, month boundaries, leap years, etc.
6. **Keep time control granular** - Advance time by specific amounts rather than arbitrary delays

### Common Time Testing Mistakes

❌ **Don't use real time in tests:**
```swift
// BAD: Unreliable and slow
func testBadTimePattern() async {
    service.scheduleTask()
    try await Task.sleep(nanoseconds: 2_000_000_000) // 2 seconds
    XCTAssertTrue(service.taskCompleted)
}
```

✅ **Use mock time instead:**
```swift
// GOOD: Fast and deterministic
func testGoodTimePattern() async {
    let clock = TestClock<Duration>()
    let service = MyService(sleeper: Sleeper(clock: clock))
    
    let expectation = expectation(description: "Task should complete")
    service.onTaskComplete = { expectation.fulfill() }
    
    service.scheduleTask()
    await clock.advance(by: .seconds(2))
    
    await fulfillment(of: [expectation], timeout: 1.0)
}
```

**Remember: Control time in tests, don't wait for it!**

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

# Run macOS tests
xcodebuild test \
  -scheme "macOS Browser" \
  -configuration "Debug" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -allowProvisioningUpdates=NO \
  -only-testing:Unit\ Tests
```

```bash
# Run specific macOS Unit Test (e.g., HotspotDetectionServiceTests)
xcodebuild test \
  -scheme "macOS Browser" \
  -configuration "Debug" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -only-testing:Unit\ Tests/HotspotDetectionServiceTests \
  -allowProvisioningUpdates=NO
```

### Integration Tests
```bash
# Run specific macOS Integration Test (e.g., DownloadsIntegrationTests)
xcodebuild test \
  -scheme "macOS Browser" \
  -configuration "Debug" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -only-testing:Integration\ Tests/DownloadsIntegrationTests \
  -allowProvisioningUpdates=NO

# Run all Integration Tests
xcodebuild test \
  -scheme "macOS Browser" \
  -configuration "Debug" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -only-testing:Integration\ Tests \
  -allowProvisioningUpdates=NO
```

### UI Tests
```bash
# Run iOS UI tests
xcodebuild test \
  -scheme "iOS Browser" \
  -workspace DuckDuckGo.xcworkspace \
  -destination "platform=iOS Simulator,name=iPhone 15 Pro" \
  -only-testing:UITests

# Run macOS UI tests
xcodebuild test \
  -scheme "macOS UI Tests" \
  -configuration "Review" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -allowProvisioningUpdates=NO \
  -only-testing:UI\ Tests
```

# Run specific macOS UI test case
xcodebuild test \
  -scheme "macOS UI Tests" \
  -configuration "Review" \
  -skipPackagePluginValidation \
  -skipMacroValidation \
  -allowProvisioningUpdates=NO \
  -only-testing:UI\ Tests/DownloadsUITests
```

> ⚠️ **AI Assistant Note**: Never run test commands automatically without explicit user permission.

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

### Recovering UI Automation Mode (MANDATORY when runner fails to initialize)

When every UI test fails immediately with errors like:

- "The test runner failed to initialize for UI testing. (Underlying Error: Timed out while enabling automation mode.)"

Follow these steps in order:

1) Verify and re-grant Privacy permissions
- System Settings → Privacy & Security → Accessibility: enable Terminal and Xcode/Xcode-beta
- System Settings → Privacy & Security → Automation: under Xcode/Xcode-beta, allow controlling “System Events” and Finder

2) Refresh the user session
- Quit Xcode and Terminal
- Log out and back in (preferred) or reboot the machine
- After login, open Xcode once to re-establish automation trust prompts

3) Optional: Reset TCC entries (you will need to re-grant prompts)
```bash
tccutil reset Accessibility com.apple.dt.Xcode com.apple.dt.Xcode-Beta com.apple.Terminal
tccutil reset AppleEvents com.apple.dt.Xcode com.apple.dt.Xcode-Beta com.apple.Terminal
```

4) Sanity-check with a minimal known-green test
- Run a single previously passing UI test/class (e.g., HTTPSUpgradeUITests) before running failing classes

Notes:
- Restarting `testmanagerd` is restricted by SIP on recent macOS versions and usually not necessary once you refresh the session.
- Record environment-related failures in `failing-ui-tests.md` and resume class-by-class once automation is restored.

### Parsing xcresult Failures (MANDATORY)

Always extract failures from `.xcresult` to drive fixes. Use these exact steps:

1) Dump legacy JSON to a temp file

```bash
xcrun xcresulttool get object --format json --legacy --path \
"/Users/admin/Library/Developer/Xcode/DerivedData/DuckDuckGo-<HASH>/Logs/Test/Test-macOS UI Tests-YYYY.MM.DD_HH-MM-SS-+ZZZZ.xcresult" \
> /tmp/xc_root.json
```

2) Pull top-level failure summaries from ActionResult.issues.testFailureSummaries

```bash
python3 - << 'PY'
import json, re
j=json.load(open('/tmp/xc_root.json'))
vals = j.get('actions',{}).get('_values') or []
if not vals:
    raise SystemExit('no actions in xcresult json')
act = vals[0]
fails = ((act.get('actionResult',{})
           .get('issues',{})
           .get('testFailureSummaries',{})
           .get('_values')) or [])

def decode_url(url):
    if not url: return ('','')
    m = re.match(r'^file:\/\/(.*?)#.*StartingLineNumber=(\d+)', url)
    return (m.group(1), m.group(2)) if m else (url,'')

for f in fails:
    name = (f.get('testCaseName') or {}).get('_value','')
    msg  = (f.get('message') or {}).get('_value','')
    url  = (f.get('documentLocationInCreatingWorkspace') or {}).get('url',{}).get('_value','')
    filePath, line = decode_url(url)
    print(f"{name}\t{' '.join(msg.split())}\t{filePath}\t{line}")
PY
```

Notes:
- Use `--legacy`; the non-legacy command is deprecated and returns no JSON here.
- If per-test details aren't under the top-level summaries, traverse `actions._values[].actionResult.testsRef` and follow `summaryRef` ids for each leaf test to collect `failureSummaries`.
- Never guess failures by console output; always parse `.xcresult`.

3) Update `failing-ui-tests.md` with a flat list of ❌ tests and exact reasons (include `file:line` when available). Then fix tests one by one, marking progress as:
- ❓ fixed/unchecked
- ✅ validated
- ❌ still failing — reason
