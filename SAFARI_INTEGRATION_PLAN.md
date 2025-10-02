# Safari Performance Test Integration Plan

## Overview
Integrate the existing Safari performance test infrastructure with the browser's performance testing UI, allowing users to run and compare Safari tests directly from the browser.

---

## Phase 1: Safari Test Runner Integration

### 1.1 Create Safari Test Runner Wrapper (NEW FILE)
**File**: `macOS/LocalPackages/PerformanceTest/Sources/PerformanceTest/Core/SafariTestRunner.swift`

- Swift wrapper to execute the Node.js Safari test script
- Use `Process` to launch: `SafariTestRunner/bin/safari-performance-test`
- Pass URL, iterations, and temp output folder as arguments
- Capture stdout/stderr and log using `os.log` with `.default` (always visible)
- Monitor process state and progress
- Handle graceful cancellation
- Return path to JSON results file on completion

### 1.2 Add Safari Test ViewModel (NEW FILE)
**File**: `macOS/LocalPackages/PerformanceTest/Sources/PerformanceTest/UI/SafariPerformanceTestViewModel.swift`

- Extend or mirror `PerformanceTestViewModel` structure
- Add properties for Safari test state
- Implement Safari test execution flow:
  - Create temp directory for results
  - Execute `SafariTestRunner` with URL and iterations
  - Parse console output for progress updates
  - Update progress UI based on iteration logs
  - Handle test completion/cancellation
  - Parse JSON results file

### 1.3 Add Debug Menu Entry
**File**: `macOS/DuckDuckGo/Menus/MainMenu.swift` (MODIFY)

Add to the existing "Performance Tests" submenu (around line 695-700):
```swift
NSMenuItem(title: "Test Current Site Performance")  // existing
NSMenuItem(title: "Test Current Site Performance (Safari)", action: #selector(MainViewController.testCurrentSitePerformanceWithSafari))
    .withAccessibilityIdentifier("MainMenu.testCurrentSitePerformanceSafari")
```

### 1.4 Add Action Handler
**File**: `macOS/DuckDuckGo/MainWindow/MainViewController.swift` (MODIFY)

Add new method similar to `testCurrentSitePerformance()`:
```swift
@objc func testCurrentSitePerformanceWithSafari() {
    guard let currentTab = tabCollectionViewModel.selectedTabViewModel?.tab else {
        // Show "No Active Page" alert
        return
    }

    // Launch Safari test window with Safari test runner
    let windowController = SafariPerformanceTestWindowController(
        url: currentTab.url,
        webView: currentTab.webView  // For displaying results later
    )
    windowController.showWindow(nil)
}
```

---

## Phase 2: Results Processing & Display

### 2.1 Create Safari Results Processor (NEW FILE)
**File**: `macOS/LocalPackages/PerformanceTest/Sources/PerformanceTest/Core/SafariResultsProcessor.swift`

- Parse Safari JSON output format
- Transform to `PerformanceTestResults` structure
- Map Safari metrics to browser metrics:
  - Safari's iteration data → `CollectedMetrics` arrays
  - Calculate statistics (mean, median, p95, etc.)
  - Handle missing/unavailable metrics
  - Set failedAttempts based on success/failure counts

### 2.2 Safari Test Window Controller (NEW FILE)
**File**: `macOS/LocalPackages/PerformanceTest/Sources/PerformanceTest/UI/SafariPerformanceTestWindowController.swift`

- Similar to `PerformanceTestWindowController`
- Initialize with URL instead of WebView
- Use `SafariPerformanceTestViewModel`
- Show same iteration selection dialog
- On completion, process results and display using existing `PerformanceTestWindowView`

### 2.3 Reuse Existing UI
**File**: `macOS/LocalPackages/PerformanceTest/Sources/PerformanceTest/UI/PerformanceTestWindowView.swift` (MINOR MODIFY)

- Already works with `PerformanceTestResults` structure
- May need minor tweaks to handle Safari-specific edge cases
- Add label/indicator showing "Safari Results" vs "Browser Results"

---

## Implementation Details

### Temp File Management
- Create temp directory: `FileManager.default.temporaryDirectory.appendingPathComponent("safari-perf-tests")`
- Generate unique filename: `safari-results-{timestamp}.json`
- Clean up temp files after reading results

### Progress Logging
Safari test runner logs to console in format:
```
[INFO] Starting iteration 2 of 10
[INFO] Clearing cache...
[INFO] Loading page...
```

Parse these logs to update progress UI:
- Extract iteration number
- Extract status text
- Calculate progress percentage

### Error Handling
- Handle missing Node.js/dependencies
- Handle Safari WebDriver not enabled
- Handle test timeouts/failures
- Show user-friendly error messages
- Preserve partial results on failure

### Data Flow
```
User clicks menu →
Dialog for iterations →
Launch SafariTestRunner (Node.js process) →
Monitor progress via stdout →
Write JSON to temp file →
Parse JSON →
Transform to PerformanceTestResults →
Display in existing UI
```

---

## Files to Create (6 new files)
1. `SafariTestRunner.swift` - Process wrapper
2. `SafariPerformanceTestViewModel.swift` - Safari test VM
3. `SafariPerformanceTestWindowController.swift` - Window controller
4. `SafariResultsProcessor.swift` - JSON parser/transformer
5. `SafariTestModels.swift` - Codable structs for Safari JSON
6. `SafariTestRunner+Resources.swift` - Resource bundle helpers

## Files to Modify (2 files)
1. `MainMenu.swift` - Add debug menu item
2. `MainViewController.swift` - Add action handler

## Files to Reference (no changes needed)
- `PerformanceTestWindowView.swift` - Reuse for display
- `PerformanceTestResults.swift` - Target data structure
- `PerformanceTestConstants.swift` - Shared constants

---

## Testing Strategy
1. Test with Safari test runner standalone first
2. Test Swift wrapper with various URLs
3. Test UI integration with successful tests
4. Test error scenarios (missing deps, timeouts)
5. Test cancellation handling
6. Verify results match expected format
7. Compare Safari vs Browser results side-by-side

---

## TDD Approach

### Test First
For each component:
1. Write failing tests that define expected behavior
2. Implement minimum code to pass tests
3. Refactor while keeping tests green
4. Repeat

### Key Test Coverage
- `SafariTestRunner`: Process execution, output parsing, error handling, cancellation
- `SafariResultsProcessor`: JSON parsing, data transformation, edge cases
- `SafariPerformanceTestViewModel`: State management, progress tracking, lifecycle
- Integration: End-to-end workflow from menu to results display
