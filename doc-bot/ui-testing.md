---
alwaysApply: false
title: "UI Testing Guidelines & Best Practices"
description: "Comprehensive UI testing practices and patterns for DuckDuckGo browser macOS UI tests including element handling, navigation testing, window management, and accessibility patterns"
keywords: ["UI testing", "UI tests", "UITests", "XCTest", "XCUIApplication", "XCUIElement", "accessibility", "tab navigation", "window management", "element timing", "feature flags", "test server", "macOS testing", "middle click", "modifier keys", "timing patterns"]
---

# UI Testing Guidelines & Best Practices

*This guide covers UI testing practices and patterns specifically for the DuckDuckGo macOS browser.*

## Overview

UI Tests verify the end-to-end user experience and interface behavior. They test user workflows, navigation patterns, window management, and complex interactions across the entire application.

## Setting Up UI Tests

### ❗Always Use UITestCase Base Class

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

**Why UITestCase is Required**:
- Provides proper app lifecycle management
- Handles feature flag configuration
- Sets up test server environment
- Manages window state and cleanup
- Provides debugging utilities

### Feature Flag Configuration

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

### File Management in UI Tests

The `UITestCase` base class provides built-in file management capabilities for handling downloads, temporary files, and other file operations during testing.

**Important**: UI tests run in a sandboxed environment and cannot directly read or delete files from user directories using standard FileManager calls. For non-temp directories, use the `filesToCleanup` pattern that's handled in the base class `tearDown()`.

#### Automatic File Cleanup

All UI test classes automatically clean up tracked files after test completion:

```swift
class DownloadsUITests: UITestCase {
    func testFileDownload() {
        let downloadsDir = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        let fileName = "test-file.json"
        let filePath = downloadsDir.appendingPathComponent(fileName).path
        
        // Track file for automatic cleanup
        trackForCleanup(filePath)
        
        // Perform download test...
        // File will be automatically cleaned up after test completes
    }
}
```

#### Reading Files via Local Server

Use `readFileViaLocalServer()` to read files that may have permission restrictions:

```swift
func testJSONFileContent() throws {
    let filePath = "/Users/admin/Downloads/test-results.json"
    
    // Read file via local test server (bypasses permission issues)
    let jsonData = try readFileViaLocalServer(filePath: filePath)
    let results = try JSONDecoder().decode(TestResults.self, from: jsonData)
    
    // Validate file contents
    XCTAssertFalse(results.items.isEmpty)
}
```

#### File Management Best Practices

```swift
class FileBasedUITests: UITestCase {
    func testCompleteFileWorkflow() throws {
        // 1. Track all files that will be created
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("test-files")
        trackForCleanup(tempDir.path)
        
        let downloadedFile = "/Users/admin/Downloads/results.json"
        trackForCleanup(downloadedFile)
        
        // 2. Perform file operations
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        // 3. Read files via server if needed
        let fileData = try readFileViaLocalServer(filePath: downloadedFile)
        
        // 4. Files are automatically cleaned up in tearDown()
    }
}
```

#### Available Methods

- **`trackForCleanup(_ path: String)`**: Track a file/directory for automatic cleanup
- **`readFileViaLocalServer(filePath: String) throws -> Data`**: Read file via local test server
- **Automatic cleanup**: All tracked files are cleaned up after each test via the base class `tearDown()`

## Element Access Patterns

### Accessibility IDs - The Golden Standard

**ALWAYS prefer accessibility IDs for element access**. They provide the most reliable and maintainable element identification.

#### Finding Existing Accessibility IDs

1. **Check the actual browser code** for assigned accessibility IDs:
```swift
// In browser code - look for patterns like:
button.accessibilityIdentifier = "AddressBarViewController.addressBarButton"
textField.identifier = "PreferencesGeneralView.switchToNewTabImmediately"
```

2. **Check XCUIApplication/XCUIElement extensions** for existing quick-accessor variables:
```swift
// Check Common/XCUIApplicationExtension.swift
extension XCUIApplication {
    var addressBar: XCUIElement {
        windows.textFields["AddressBarViewController.addressBarTextField"]
    }
    
    var backButton: XCUIElement {
        buttons["NavigationBarViewController.backButton"]
    }
}
```

3. **Use accessibility identifiers consistently**:
```swift
// ✅ CORRECT: Using accessibility IDs
let addressBar = app.textFields["AddressBarViewController.addressBarTextField"]
let bookmarksMenu = app.menuItems["BookmarksMenu.showBookmarks"]
let downloadButton = app.buttons["DownloadsViewController.downloadButton"]

// ❌ INCORRECT: Using text-based selectors
let addressBar = app.textFields["Enter search or URL"]  // Fragile - breaks with localization
let bookmarksMenu = app.menuItems["Bookmarks"]          // Fragile - breaks with text changes
```

#### When to Add New Accessibility IDs

**ALWAYS validate with user before modifying main app code** to add missing accessibility IDs:

```swift
// Before adding to main app code, ask:
// "I need to add accessibility ID 'TabBarViewController.newTabButton' 
//  to the new tab button in TabBarViewController.swift. Should I proceed?"

// Then add to the main app:
newTabButton.accessibilityIdentifier = "TabBarViewController.newTabButton"
```

#### Element Variable Guidelines

**Only create element variables in test cases if they are very specific to the testable area**:

```swift
// ✅ CORRECT: Test-specific elements
func testSpecificFeatureWorkflow() {
    let featureSpecificButton = app.buttons["FeatureViewController.specialActionButton"]
    let uniqueDialog = app.dialogs["FeatureDialog.confirmationDialog"]
    // Use directly in test
}
```

**If elements are generic, add accessors to XCUIApplication/XCUIElement extensions**:

```swift
// ✅ CORRECT: Add to XCUIApplicationExtension.swift
extension XCUIApplication {
    var downloadButton: XCUIElement {
        buttons["DownloadsViewController.downloadButton"]
    }
    
    var preferencesWindow: XCUIElement {
        windows["PreferencesWindow"]
    }
}

// Then use in tests:
func testDownloadFlow() {
    app.downloadButton.click()
    XCTAssertTrue(app.downloadButton.exists)
}
```

### Timeout Constants Usage

**MANDATORY**: Always use `UITests.Timeouts` constants instead of hardcoded timeout values.

```swift
// ✅ CORRECT: Use semantic timeout constants
XCTAssertTrue(button.waitForExistence(timeout: UITests.Timeouts.elementExistence), "Button should appear")
XCTAssertTrue(pageContent.waitForExistence(timeout: UITests.Timeouts.navigation), "Page should load")
XCTAssertTrue(localContent.waitForExistence(timeout: UITests.Timeouts.localTestServer), "Local server content should load")

// ❌ INCORRECT: Hardcoded timeout values
XCTAssertTrue(button.waitForExistence(timeout: 5.0), "Button should appear")
XCTAssertTrue(pageContent.waitForExistence(timeout: 30.0), "Page should load")
XCTAssertTrue(localContent.waitForExistence(timeout: 15.0), "Local server content should load")
```

**Available Timeout Constants**:
- `UITests.Timeouts.elementExistence` (5 sec) - UI elements, buttons, text fields, dialogs
- `UITests.Timeouts.navigation` (30 sec) - Page loads, network requests, external sites
- `UITests.Timeouts.localTestServer` (15 sec) - Localhost connections, test server content
- `UITests.Timeouts.fireAnimation` (30 sec) - Fire animation completion

### Address Bar Validation Rules

**MANDATORY**: Always use `app.addressBarValueActivatingIfNeeded()` for address bar validation and prefer exact matches over contains checks.

```swift
// ✅ CORRECT: Use helper method with exact match for known URLs
XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://example.com/", "Should navigate to example.com")
XCTAssertEqual(app.addressBarValueActivatingIfNeeded(), "https://duckduckgo.com/", "Should be on DuckDuckGo")

// ❌ INCORRECT: Manual address bar access, partial comparison
app.activateAddressBar()
let addressBarValue = addressBarTextField.value as? String ?? ""
XCTAssertTrue(addressBarValue.contains("example.com"), "Should be on example.com")

// ❌ INCORRECT: Contains check for known exact URLs
let addressBarValue = app.addressBarValueActivatingIfNeeded() ?? ""
XCTAssertTrue(addressBarValue.contains("example.com"), "Should be on example.com") // Use XCTAssertEqual instead
```

**Address Bar Validation Guidelines**:
- **Use exact matches** (`XCTAssertEqual`) for known static URLs
- **Use contains checks** only for dynamic URLs (search results, localhost with ports)
- **Always use** `app.addressBarValueActivatingIfNeeded()` helper method
- **Never manually** call `app.activateAddressBar()` + `addressBarTextField.value`

### CRITICAL: XCUIElement Queries Are Always Live

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

### Element Access Hierarchy

1. **Accessibility IDs** (most reliable)
2. **Extension-provided accessors** (for common elements)
3. **Stable attributes** (for dynamic content)
4. **Text-based selectors** (last resort, fragile)

## Window and Tab Management

### Essential Window/Tab Validation Patterns

Based on our tab navigation testing improvements, always validate both UI state and browser state:

#### Single-Window Tab Operations

```swift
func testTabOperation() {
    // Perform action that opens new tab
    link.click()
    
    // ✅ CORRECT: Wait first, then validate counts
    XCTAssertTrue(app.tabs["New Tab Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    XCTAssertEqual(app.windows.count, 1)  // Still single window
    XCTAssertEqual(app.tabs.count, 2)     // Original + new tab
    
    // Validate both tabs exist
    XCTAssertTrue(app.tabs["Original Page"].exists)
    XCTAssertTrue(app.tabs["New Tab Page"].exists)
    
    // Validate webview state
    XCTAssertTrue(app.webViews["New Tab Page"].exists)
}
```

#### Multi-Window Operations

```swift
func testWindowOperation() {
    // Perform action that opens new window
    XCUIElement.perform(withKeyModifiers: [.command, .option]) {
        link.click()
    }
    
    // ✅ CORRECT: Wait for new window, then validate structure
    let mainWindow = app.windows.firstMatch
    let backgroundWindow = app.windows.element(boundBy: 1)
    XCTAssertTrue(backgroundWindow.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    XCTAssertEqual(app.windows.count, 2)
    
    // Validate content in correct windows
    XCTAssertTrue(backgroundWindow.webViews["New Window Page"].exists)
    XCTAssertFalse(mainWindow.webViews["New Window Page"].exists)
    XCTAssertTrue(mainWindow.webViews["Original Page"].exists)
    
    // Validate tab counts per window
    XCTAssertEqual(mainWindow.tabs.count, 1)
    XCTAssertEqual(backgroundWindow.tabs.count, 1)
    XCTAssertTrue(mainWindow.tabs["Original Page"].exists)
    XCTAssertTrue(backgroundWindow.tabs["New Window Page"].exists)
}
```

#### Window Focus Behavior

**Important**: When windows are activated/deactivated, the `firstMatch` window changes:

```swift
func testWindowActivation() {
    // Initially: Window A is active (firstMatch), Window B is background
    let initialActiveWindow = app.windows.firstMatch
    let backgroundWindow = app.windows.element(boundBy: 1)
    
    // Click on background window to activate it
    backgroundWindow.click()
    
    // Now: Window B becomes firstMatch, Window A becomes background
    let newActiveWindow = app.windows.firstMatch  // This is now Window B
    let newBackgroundWindow = app.windows.element(boundBy: 1)  // This is now Window A
    
    // Validate the swap occurred
    XCTAssertNotEqual(initialActiveWindow, newActiveWindow)
}
```

### Navigation Modifier Patterns

Understanding modifier key behaviors for comprehensive testing:

#### Tab Opening Modifiers
- **Command Click**: Opens in background tab
- **Command+Shift Click**: Opens in foreground tab (switches to it)
- **Middle Click**: Opens in background tab  
- **Middle+Shift Click**: Opens in foreground tab

#### Window Opening Modifiers
- **Command+Option Click**: Opens in background window
- **Command+Option+Shift Click**: Opens in foreground window (switches to it)
- **Middle+Option Click**: Opens in background window
- **Middle+Option+Shift Click**: Opens in foreground window

#### Validation Patterns by Modifier

```swift
// Background tab (Command click)
func testCommandClickOpensBackgroundTab() {
    XCUIElement.perform(withKeyModifiers: [.command]) {
        link.click()
    }
    
    XCTAssertTrue(app.tabs["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    XCTAssertEqual(app.windows.count, 1)
    XCTAssertEqual(app.tabs.count, 2)
    
    // Original page still visible (background tab behavior)
    XCTAssertTrue(app.webViews["Original Page"].exists)
    XCTAssertTrue(app.tabs["Original Page"].exists)
    XCTAssertTrue(app.tabs["New Tab"].exists)
}

// Foreground tab (Command+Shift click)
func testCommandShiftClickOpensActiveTab() {
    XCUIElement.perform(withKeyModifiers: [.command, .shift]) {
        link.click()
    }
    
    XCTAssertTrue(app.webViews["New Tab"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    XCTAssertEqual(app.windows.count, 1)
    XCTAssertEqual(app.tabs.count, 2)
    
    // New page visible, original page in background (foreground tab behavior)
    XCTAssertFalse(app.webViews["Original Page"].exists)
    XCTAssertTrue(app.tabs["Original Page"].exists)  // Tab still exists
    XCTAssertTrue(app.tabs["New Tab"].exists)
}
```

## Element Interaction Patterns

### Timing and Existence Best Practices

**Critical**: Always wait for elements before checking counts or states:

```swift
// ❌ BAD: Checking counts before content appears
action()
XCTAssertEqual(app.windows.count, 1)  // Race condition!
XCTAssertTrue(element.waitForExistence(...))

// ✅ GOOD: Wait first, then validate
action()
XCTAssertTrue(element.waitForExistence(timeout: UITests.Timeouts.elementExistence))
XCTAssertEqual(app.windows.count, 1)  // Now safe to check
```

### Interaction Methods

#### Safe Element Interaction

```swift
// ✅ GOOD - Use existing helper methods
element.clickAfterExistenceTestSucceeds()
element.hoverAfterExistenceTestSucceeds()
element.typeURLAfterExistenceTestSucceeds(testURL)

// ✅ GOOD - URL handling with colon workaround  
element.typeURL(url, pressingEnter: true)  // Handles colon typing issues
element.pasteURL(url, pressingEnter: true) // Faster than typing

// ✅ GOOD - Element disappearance tracking
element.waitForNonExistence(timeout: UITests.Timeouts.elementExistence)
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
- `app.addressBarValueActivatingIfNeeded()` → Activate address bar and return its current value as String?
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

#### Existence Checking Patterns

```swift
// ✅ GOOD - Proper existence checking
XCTAssertTrue(mainElement.waitForExistence(timeout: UITests.Timeouts.elementExistence))
XCTAssertTrue(relatedButton.exists)  // Good after waitForExistence passed
XCTAssertTrue(anotherComponent.exists)  // Good for checking multiple components

// ❌ BAD - Avoid these patterns
XCTAssertTrue(element.exists)  // Without waitForExistence first
XCTAssertTrue(element1.waitForExistence(timeout: 5))
XCTAssertTrue(element2.waitForExistence(timeout: 5))  // Consecutive waits slow tests
Thread.sleep(forTimeInterval: 2.0)  // Unreliable
Task.sleep(nanoseconds: 2_000_000_000)  // Same issue
```

#### XCUIElement Property Waiting Extensions

**NEW: Type-safe property waiting methods for more reliable UI tests:**

```swift
// ✅ EXCELLENT: Wait for element properties using key paths
let addressBar = app.addressBar
let button = app.buttons["TestButton"]

// Wait for property to contain substring (case-insensitive)
XCTAssertTrue(addressBar.wait(for: \.value, contains: "example.com", timeout: 10.0))
XCTAssertTrue(button.wait(for: \.label, contains: "Submit"))

// Wait for property to equal specific value
XCTAssertTrue(button.wait(for: \.isEnabled, equals: true, timeout: 5.0))
XCTAssertTrue(addressBar.wait(for: \.value, equals: "https://duckduckgo.com"))

// Use in assertions with descriptive failure messages
XCTAssertTrue(statusField.wait(for: \.value, equals: "1 of 4"), 
              "Status field should show '1 of 4', but got: \(statusField.value ?? "nil")")
```

**Benefits of property waiting extensions:**
- **Type-safe**: Uses Swift key paths instead of string predicates
- **Flexible**: Works with any property (\.value, \.label, \.title, \.isEnabled, etc.)
- **Reliable**: Built on XCTNSPredicateExpectation for proper waiting
- **Debuggable**: Easy to add current value to failure messages

#### XCUIElementQuery Filtering Extensions

**Type-safe element filtering using key paths:**

```swift
// ✅ CORRECT: Filter elements using key paths
let webView = app.webViews.firstMatch

// Filter by substring (case-insensitive)
let pageContent = webView.staticTexts.containing(\.value, containing: "Example Domain").firstMatch
let submitButtons = app.buttons.containing(\.label, containing: "Submit")

// Filter by exact value  
let enabledButtons = app.buttons.containing(\.isEnabled, equalTo: true)
let specificText = webView.staticTexts.containing(\.value, equalTo: "Welcome").firstMatch
let settingsWindow = app.windows.containing(\.title, equalTo: "Settings").firstMatch

// Element matching patterns
let stopMenuItem = app.menuItems.containing(\.title, equalTo: "Stop").firstMatch
let backgroundTab = app.radioButtons.containing(\.title, equalTo: "Background Download").firstMatch

// Replace old NSPredicate format strings  
// ❌ OLD: webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'"))
// ✅ NEW: webView.staticTexts.containing(\.value, containing: "Example Domain")
```

**Available XCUIElementQuery Methods**:
- `containing(_:containing:)` - Filter elements where property contains substring
- `containing(_:equalTo:)` - Filter elements where property equals value
- `containing(_:where:)` - Filter elements containing specific element type with predicate
- `matching(_:containing:)` - Alternative filtering method for contains
- `matching(_:equalTo:)` - Alternative filtering method for equals
- `element(matching:containing:)` - Get single element matching contains criteria
- `element(matching:equalTo:)` - Get single element matching equals criteria

#### NSPredicate KeyPath Extensions

**Type-safe predicate construction for complex filtering:**

```swift
// ✅ CORRECT: Using .keyPath() method for predicate construction
let webView = app.webViews.firstMatch

// Complex element filtering with compound predicates
let pdfElement = app.groups.containing(.staticText, where: .keyPath(\.value, beginsWith: "TestPDF")).firstMatch

// Compound predicates combining multiple conditions
let summaryGroup = webView.groups.containing(.keyPath(\.value, beginsWith: "1p navigation -")).firstMatch
let headerGroup = summaryGroup.groups.containing(.staticText, where: .keyPath(\.value, beginsWith: "Blocked")).firstMatch

// Advanced predicate construction with chaining
let complexPredicate = NSPredicate.keyPath(\.elementType, equalTo: XCUIElement.ElementType.staticText.rawValue)
    .and(.keyPath(\.value, beginsWith: "Expected"))

let pathCell = tables.cells.containing(NSPredicate { element, _ in
    guard let id = (element as? NSObject)?.value(forKey: #keyPath(XCUIElement.identifier)) as? String,
          id.hasPrefix("/"),
          URL(fileURLWithPath: id).standardizedFileURL.path == standardizedPath else { return false }
    return true
}).firstMatch

// Window filtering patterns
let namedWindow = app.windows.containing(NSPredicate(format: "title == %@", "Page Title")).firstMatch

// Replace manual NSPredicate format strings
// ❌ OLD: NSPredicate(format: "value CONTAINS %@ AND isEnabled == %@", "text", true)
// ✅ NEW: .keyPath(\.value, contains: "text").and(.keyPath(\.isEnabled, equalTo: true))
```

**Available NSPredicate Static Methods**:

**Equality and Membership**:
- `.keyPath(_:equalTo:)` - Property equals specific value
- `.keyPath(_:in: [values])` - Property in collection of values
- `.keyPath(_:in: range)` - Property in numeric range

**String Operations**:
- `.keyPath(_:contains:)` - Property contains substring (case-insensitive)
- `.keyPath(_:like:)` - Pattern matching with wildcards (* and ?)
- `.keyPath(_:beginsWith:)` - Property starts with prefix
- `.keyPath(_:endsWith:)` - Property ends with suffix
- `.keyPath(_:matchingRegex:)` - Property matches regular expression

**Numeric Range Operations**:
- `.keyPath(_:in: 1...10)` - Closed range (inclusive)
- `.keyPath(_:in: 1..<10)` - Half-open range
- `.keyPath(_:in: 5...)` - Greater than or equal (>= 5)
- `.keyPath(_:in: ..<10)` - Less than (< 10)
- `.keyPath(_:in: ...10)` - Less than or equal (<= 10)

**Compound Operations**:
- `predicate.and(otherPredicate)` - AND combination (instance method)
- `predicate.or(otherPredicate)` - OR combination (instance method)
- `.and(pred1, pred2, ...)` - AND multiple predicates (static)
- `.or(pred1, pred2, ...)` - OR multiple predicates (static)
- `predicate.inverted` - NOT predicate (property)

**Benefits of NSPredicate KeyPath Extensions**:
- **Type Safety**: Compile-time KeyPath validation
- **Automatic Format Specifiers**: Handles %@, %d, %f automatically based on type
- **Composable**: Easy compound predicate construction with and/or/not
- **Reusable**: Store predicates as variables for reuse across tests

#### XCUIElementQuery Waiting Extensions

**Wait for conditions on element queries (e.g., count changes):**

```swift
// ✅ CORRECT: Wait for element count conditions
let table = app.tables.firstMatch
let cells = table.cells

// Wait for exact count
XCTAssertTrue(cells.wait(for: \.count, equals: 5, timeout: UITests.Timeouts.localTestServer), "Should have exactly 5 cells")

// Wait for range conditions
XCTAssertTrue(cells.wait(for: \.count, in: 1...10, timeout: UITests.Timeouts.elementExistence), "Should have 1-10 cells")
XCTAssertTrue(cells.wait(for: \.count, in: 2..., timeout: UITests.Timeouts.elementExistence), "Should have at least 2 cells")
XCTAssertTrue(cells.wait(for: \.count, in: ..<10, timeout: UITests.Timeouts.elementExistence), "Should have less than 10 cells")

// Wait with custom predicate
let countPredicate = NSPredicate.keyPath(\.count, in: 1...5)
XCTAssertTrue(cells.wait(for: countPredicate, timeout: UITests.Timeouts.elementExistence), "Should have 1-5 cells")

// Replace old XCTNSPredicateExpectation patterns
// ❌ OLD: Manual XCTNSPredicateExpectation creation
// let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "count == %d", 2), object: table.cells)
// XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 15.0), .completed)

// ✅ NEW: Direct query waiting methods
// XCTAssertTrue(table.cells.wait(for: \.count, equals: 2, timeout: UITests.Timeouts.localTestServer))
```

**Available XCUIElementQuery Wait Methods**:
- `wait(for: NSPredicate, timeout:)` - Wait for custom NSPredicate condition
- `wait(for: \.count, equals: value, timeout:)` - Wait for count to equal specific value
- `wait(for: \.count, in: ClosedRange, timeout:)` - Wait for count in inclusive range (1...10)
- `wait(for: \.count, in: Range, timeout:)` - Wait for count in half-open range (1..<10) 
- `wait(for: \.count, in: PartialRangeFrom, timeout:)` - Wait for count >= value (5...)
- `wait(for: \.count, in: PartialRangeUpTo, timeout:)` - Wait for count < value (..<10)
- `wait(for: \.count, in: PartialRangeThrough, timeout:)` - Wait for count <= value (...10)

**Benefits of query waiting extensions:**
- **Type-safe**: Uses Swift key paths with compile-time validation
- **Range support**: Native Swift range syntax for numeric conditions
- **Simplified**: Replaces verbose XCTNSPredicateExpectation patterns
- **Consistent**: Same predicate-based API as filtering methods
- **Maintainable**: Compiler catches property and range type errors

#### Middle Click Special Handling

```swift
// ❌ NEVER: Use synthesized CGEvent approach
let mouseDownEvent = CGEvent(mouseEventSource: nil,
                                mouseType: .otherMouseDown,
                                mouseCursorPosition: point,
                                mouseButton: .center)!
let mouseUpEvent = CGEvent(mouseEventSource: nil,
                            mouseType: .otherMouseUp,
                            mouseCursorPosition: point,
                            mouseButton: .center)!
mouseDownEvent.post(tap: .cghidEventTap)
mouseUpEvent.post(tap: .cghidEventTap)

// ✅ CORRECT: Use extension method directly
element.middleClick()  // Extension handles middle-click properly

// ✅ CORRECT: For middle-click with modifiers, use separate perform block
XCUIElement.perform(withKeyModifiers: [.option]) {
    element.middleClick()  // This doesn't work correctly
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

    // ✅ CORRECT: On new tab page, address bar is already activated - no Cmd+L needed
    addressBar.pasteURL("example.com")
    
    // Wait for navigation
    let pageContent = webView.staticTexts.containing(NSPredicate(format: "value CONTAINS 'Example Domain'")).firstMatch
    XCTAssertTrue(pageContent.waitForExistence(timeout: 30.0), "Example.com should load")
    
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

### Context Menu Interaction

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

## Local Test Server Integration

UI tests use a local test server running on `http://localhost:8085/` for reliable page loading and content simulation.

### Test Server Architecture

- **Port**: 8085 (not 8080)  
- **Integration**: Uses `TestsURLExtension.swift` shared with Integration Tests
- **APIs**: Provides `URL.testsServer` and `.appendingTestParameters()` methods
- **Content**: Supports dynamic content generation via query parameters

### Creating Test Content

#### Static Content
```swift
// Static content from test files
let url = URL.testsServer.appendingPathComponent("test-page.html")
```

#### Dynamic Content  
```swift
// Dynamic content with custom HTML
let url = UITests.simpleServedPage(titled: "Test Page")
// Creates: http://localhost:8085/?data=<html>...<title>Test Page</title>...</html>

// With custom body content
let url = UITests.simpleServedPage(titled: "Test Page") {
    "<a href='http://example.com'>Test Link</a>"
}
```

#### Custom HTTP Responses
```swift
let url = URL.testsServer
    .appendingPathComponent("test-endpoint")
    .appendingTestParameters(
        status: 404,
        reason: "Not Found",
        headers: ["Content-Type": "application/json"]
    )
```

### URL Parameter Options
- `status`: HTTP status code (default: 200)
- `reason`: HTTP status string (default: "OK")
- `data`: Response body (Data or String, base64 encoded if binary)
- `headers`: HTTP response headers

### Test Server Best Practices
- Use `UITests.simpleServedPage(titled:)` for basic HTML pages
- Use `URL.testsServer.appendingTestParameters()` for custom responses
- Test various HTTP status codes and response types
- Keep test content simple and predictable
- Always validate server responses in tests

## Performance Optimizations

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

### Avoiding Slow Operations

```swift
// ✅ FAST: Use paste for long URLs: it manages pasting into the pasteboard and restores its contents afterwards
addressBar.pasteURL(longURL)

// ❌ SLOW: Character-by-character typing  
addressBar.typeText(longURL)

// ✅ FAST: Single waitForExistence
XCTAssertTrue(mainElement.waitForExistence(timeout: 5))
XCTAssertTrue(relatedElement.exists)

// ❌ SLOW: Multiple consecutive waits
XCTAssertTrue(element1.waitForExistence(timeout: 5))
XCTAssertTrue(element2.waitForExistence(timeout: 5))
```

## UI Test Build Architecture

UI tests use a unique build architecture that affects compatibility:

### Build Process
- **App Binary**: Built using notarized build action (latest Xcode/toolchain)
- **UI Test Bundle**: Built on target macOS version (macOS 13/14/15 runners)  
- **Testing**: UI Test bundle tests the notarized app binary across macOS 13/14/15

### Code Compatibility Requirements

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

### Compatibility Guidelines
- UI Test code must compile on oldest supported Xcode version (for macOS 13 runner)
- App code can use latest Swift/Xcode features (built with latest toolchain)
- Test only stable APIs - avoid beta/preview APIs in UI test code
- Use `@available` checks carefully - must work across all test runners

## Advanced Testing Patterns

### Tab Extension Testing in UI Tests

For testing Tab Extension behavior through the UI:

```swift
func testTabExtensionUIBehavior() {
    // Load page that triggers tab extension
    openTestPage("Extension Test Page")
    
    // Test extension UI elements appear
    XCTAssertTrue(app.buttons["TabExtension.actionButton"].waitForExistence(timeout: 5))
    
    // Test extension interactions
    app.buttons["TabExtension.actionButton"].click()
    XCTAssertTrue(app.alerts["TabExtension.confirmationAlert"].exists)
}
```

### Settings and Preferences Testing

```swift
func testPreferencesImpactOnBehavior() {
    // Navigate to preferences
    navigateToGeneralPreferences()
    
    // Change setting
    let toggle = app.checkBoxes["PreferencesGeneralView.switchToNewTabImmediately"]
    XCTAssertTrue(toggle.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    
    if (toggle.value as? Bool) != true {
        toggle.click()
    }
    
    // Test behavior change
    openTestPage("Test Page")
    XCUIElement.perform(withKeyModifiers: [.command]) {
        link.click()
    }
    
    // Validate inverted behavior due to setting
    XCTAssertTrue(app.webViews["New Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    
    // Reset setting
    if (toggle.value as? Bool) == true {
        toggle.click()
    }
}
```

### Bookmark and History Testing

#### Bookmark Testing Best Practices

**Always reset bookmarks before testing** to ensure a clean state:

```swift
func testBookmarkNavigation() {
    // ✅ CORRECT: Reset bookmarks for clean test state
    app.resetBookmarks()
    
    // Add bookmark
    openTestPage("Test Page")
    app.mainMenuAddBookmarkMenuItem.click()
    app.addBookmarkAlertAddButton.click()
    
    // Test bookmark interactions
    app.bookmarksMenu.click()
    // ✅ CORRECT: Use bookmarksMenu.menuItems for bookmark items
    let bookmarkItem = app.bookmarksMenu.menuItems["Test Page"]
    XCTAssertTrue(bookmarkItem.waitForExistence(timeout: UITests.Timeouts.elementExistence))
    
    // Test modifier behaviors
    XCUIElement.perform(withKeyModifiers: [.command]) {
        bookmarkItem.click()
    }
    
    XCTAssertTrue(app.webViews["Test Page"].waitForExistence(timeout: UITests.Timeouts.elementExistence))
    XCTAssertEqual(app.windows.count, 1)
    XCTAssertEqual(app.tabs.count, 2)
}
```

#### Bookmark Testing Setup Patterns

**For single bookmark tests**: Call `app.resetBookmarks()` at the beginning of each test:

```swift
func testSingleBookmarkBehavior() {
    app.resetBookmarks()  // Clean state for this test
    
    // Test bookmark functionality...
}
```

**For test suites focused on bookmark management**: Reset in `setUp` if all tests involve bookmarks:

```swift
class BookmarkManagementUITests: UITestCase {
    override func setUpWithError() throws {
        super.setUpWithError()
        app.resetBookmarks()  // Clean state for all bookmark tests
    }
    
    func testAddBookmark() {
        // No need to reset here - already done in setUp
    }
    
    func testDeleteBookmark() {
        // No need to reset here - already done in setUp
    }
}
```

#### Bookmark Menu Item Access

**Always use `app.bookmarksMenu.menuItems` for bookmark menu items**:

```swift
// ✅ CORRECT: Specific bookmark menu item access
app.bookmarksMenu.click()
let bookmarkItem = app.bookmarksMenu.menuItems["My Bookmark"]

// ❌ INCORRECT: Generic menu item access (may conflict with other menus)
let bookmarkItem = app.menuItems["My Bookmark"]
```

## Screenshot and Debugging

### Automatic Screenshots
Screenshots are taken automatically on test failures for debugging.

### Manual Screenshots
```swift
func takeScreenshot(name: String) {
    let screenshot = XCUIScreen.main.screenshot()
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
}
```

### UI Tests Logging

**For UI tests, NEVER use `print()`. ALWAYS use `Logger.log()` for debug output:**

```swift
✅ // GOOD: Use Logger.log() for UI test debugging
class FeatureUITests: UITestCase {
    func testComplexFlow() {
        Logger.log("Starting complex UI flow test")
        Logger.log("Setting up test data with \(testData.count) items")
        Logger.log("DEBUG: currentState = \(app.addressBarValueActivatingIfNeeded())")
        
        // Perform UI test operations
        
        Logger.log("UI test completed successfully")
    }
}

❌ // BAD: Using print() statements in UI tests
func testComplexFlow() {
    print("Starting test")  // Never use print()
    print("DEBUG: addressBar = \(addressBar.value)")  // Use Logger.log() instead
}
```

**Benefits of Logger.log():**
- Integrates with XCTest's internal logging system
- Appears in test logs alongside other XCTest debug output
- Better performance and integration than print() statements
- Proper formatting for CI log collection
- Uses XCTest's private debug logging infrastructure for better integration

**Usage Examples:**
```swift
class FeatureUITests: UITestCase {
    func testComplexInteraction() {
        Logger.log("Starting test with \(elements.count) elements")
        
        let currentURL = app.addressBarValueActivatingIfNeeded()
        Logger.log("Current URL: \(currentURL ?? "nil")")
        
        if !button.waitForExistence(timeout: 5.0) {
            Logger.log("Button not found, taking screenshot for debugging")
            takeScreenshot("button-not-found")
        }
    }
}
```

### 🔍 Debug Operator: `???` for Optional String Conversion

The `???` operator provides safe string conversion for debugging:

```swift
// ✅ CORRECT: Debug string conversion with ??? operator (UI tests)
Logger.log("event received: \(event ??? "<nil>")")
XCTAssertTrue(element.exists, "Element should exist: \(optionalValue ??? "missing")")

// ✅ CORRECT: Debug string conversion with ??? operator (unit tests)
Logger.log("event received: \(event ??? "<nil>")")
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
        Logger.log("WebView hierarchy:\n\(snapshot)")
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

### Debug Information
```swift
func debugElementHierarchy() {
    // Print element hierarchy for debugging
    Logger.log("Current window hierarchy: \(app.windows.debugDescription)")
    Logger.log("Current tab structure: \(app.tabs.debugDescription)")
}
```

## Code Reading Requirements

### Always Read Actual Code

**Never assume how UI implementation is done**. Always read the actual browser code related to the tested area:

1. **Find the relevant view controller** or UI component
2. **Check for existing accessibility identifiers**
3. **Understand the UI hierarchy and structure**
4. **Identify interaction patterns and state management**
5. **Verify element lifecycle and timing**

```swift
// Example: Before testing address bar, read:
// - AddressBarViewController.swift 
// - Check how textField.accessibilityIdentifier is set
// - Understand the view hierarchy
// - Look for existing test accessors in extensions
```

### Extension Integration

Before creating element accessors, check existing extensions:

```swift
// Check XCUIApplicationExtension.swift for patterns like:
extension XCUIApplication {
    var addressBar: XCUIElement {
        windows.textFields["AddressBarViewController.addressBarTextField"]
    }
}

// Check XCUIElementExtension.swift for helper methods like:
extension XCUIElement {
    func clickAfterExistenceTestSucceeds() {
        // Implementation
    }
}
```

## Test Execution Guidelines

### ❗Never Run Tests Yourself

**DO NOT attempt to run UI tests unless explicitly asked by the user.** UI tests:
- Take significant time to execute
- Require specific setup and environment
- Can interfere with system state
- Should only be run when specifically requested for debugging

### Local Testing Recommendations

When users want to run tests locally:

```bash
# Use xcodebuild for consistency with CI
xcodebuild -project macOS/DuckDuckGo.xcodeproj \
           -scheme 'DuckDuckGo (macOS)' \
           -configuration Debug \
           -destination 'platform=macOS' \
           test \
           -only-testing:DuckDuckGo_Privacy_BrowserTests/TabNavigationTests

# For specific test methods
xcodebuild -project macOS/DuckDuckGo.xcodeproj \
           -scheme 'DuckDuckGo (macOS)' \
           -configuration Debug \
           -destination 'platform=macOS' \
           test \
           -only-testing:DuckDuckGo_Privacy_BrowserTests/TabNavigationTests/testCommandClickOpensBackgroundTab
```

## 🚫 CRITICAL: UI Testing Anti-Patterns - NEVER USE THESE

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
    print("Feature not available in test environment") // ❌ NO! Use Logger.log() instead
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

### Privacy Button Access
```swift
// ✅ CORRECT: Use the proper accessibility identifier
let privacyButton = app.buttons.matching(identifier: "AddressBarButtonsViewController.privacyDashboardButton").firstMatch
```

### ⚠️ ENFORCEMENT: These Rules Are MANDATORY

- **Every UI test MUST follow these patterns**
- **No exceptions for "quick fixes" or "temporary solutions"**
- **All existing tests MUST be refactored to follow these patterns**
- **Code reviews MUST check for these anti-patterns**

### Common Anti-Patterns to Avoid

#### ❌ Don't Use Generic Element Access
```swift
// ❌ BAD: Generic, fragile selectors
app.buttons.firstMatch
app.textFields["Search"]
app.menuItems.element(boundBy: 2)
```

#### ❌ Don't Create Redundant Element Variables
```swift
// ❌ BAD: Test-specific variables for common elements
func testSomething() {
    let addressBar = app.textFields["AddressBarViewController.addressBarTextField"]
    let backButton = app.buttons["NavigationBarViewController.backButton"]
    // These should be in extensions
}
```

#### ❌ Don't Check State Before Waiting
```swift
// ❌ BAD: Race conditions
action()
XCTAssertEqual(app.tabs.count, 2)  // Too early!
XCTAssertTrue(newElement.waitForExistence(...))
```

#### ❌ Don't Use Text-Based Selectors for Stable Elements
```swift
// ❌ BAD: Fragile to localization/text changes
app.buttons["Download"]
app.menuItems["Open in New Tab"]

// ✅ GOOD: Use accessibility IDs
app.buttons["DownloadsViewController.downloadButton"]  
app.menuItems["ContextMenu.openInNewTab"]
```

#### ❌ Don't Test Bookmarks Without Clean State
```swift
// ❌ BAD: Testing without resetting bookmarks (may conflict with existing bookmarks)
func testBookmarkBehavior() {
    openTestPage("Test Page")
    app.mainMenuAddBookmarkMenuItem.click()
    // Test may fail if bookmark already exists
}

// ❌ BAD: Using generic menu item access for bookmarks
app.bookmarksMenu.click()
let bookmarkItem = app.menuItems["My Bookmark"]  // May conflict with other menus

// ✅ GOOD: Clean state and specific bookmark menu access
func testBookmarkBehavior() {
    app.resetBookmarks()  // Ensure clean state
    openTestPage("Test Page")
    app.mainMenuAddBookmarkMenuItem.click()
    
    app.bookmarksMenu.click()
    let bookmarkItem = app.bookmarksMenu.menuItems["Test Page"]
}
```

## Running UI Tests
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

## Best Practices Summary

1. **Always read actual browser code** before writing tests
2. **Use accessibility IDs** for element access
3. **Wait for elements before checking counts** or states
4. **Validate both UI state and browser state** (webViews + tabs)
5. **Use existing extensions** and helper methods
6. **Test modifier key behaviors** comprehensively
7. **Handle multi-window scenarios** with proper window indexing
8. **Reset bookmarks with `app.resetBookmarks()`** before bookmark tests or in setUp for bookmark-focused test suites
9. **Use `app.bookmarksMenu.menuItems`** for accessing bookmark menu items
10. **Never run tests unless explicitly requested**
11. **Ask permission before modifying main app code** for accessibility IDs
12. **Use middle-click extension methods** properly

---

**For questions about UI testing patterns or to request test execution, please reach out to the iOS/macOS team.** 
