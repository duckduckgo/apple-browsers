---
alwaysApply: false
title: "Testing Guidelines & Best Practices"
description: "Testing guidelines and best practices for DuckDuckGo browser including unit tests, mocks, async testing, and performance tests"
keywords: ["testing", "unit tests", "XCTest", "mocks", "async testing", "UI tests", "performance tests", "TDD"]
---

# Testing Guidelines for DuckDuckGo Browser

## Test Organization

### File Structure
- Mirror source file structure in test directories
- Test file naming: `FeatureNameTests.swift` for `FeatureName.swift`
- Group related tests in test classes
- Use descriptive test method names

### Test Class Structure
```swift
import XCTest
@testable import DuckDuckGo

class FeatureViewModelTests: XCTestCase {
    
    // MARK: - Properties
    private var sut: FeatureViewModel!  // System Under Test
    private var mockService: MockFeatureService!
    private var cancellables: Set<AnyCancellable>!
    
    // MARK: - Setup
    override func setUp() {
        super.setUp()
        mockService = MockFeatureService()
        sut = FeatureViewModel(service: mockService)
        cancellables = []
    }
    
    override func tearDown() {
        sut = nil
        mockService = nil
        cancellables = nil
        super.tearDown()
    }
    
    // MARK: - Tests
    func testInitialState() {
        XCTAssertEqual(sut.state, .idle)
        XCTAssertTrue(sut.items.isEmpty)
    }
}
```

## Unit Testing

### ViewModel Testing
```swift
func testLoadDataSuccess() async {
    // Given
    let expectedItems = [Item.mock(), Item.mock()]
    mockService.itemsToReturn = expectedItems
    
    // When
    await sut.loadData()
    
    // Then
    XCTAssertEqual(sut.items, expectedItems)
    XCTAssertFalse(sut.isLoading)
    XCTAssertNil(sut.error)
}

func testLoadDataFailure() async {
    // Given
    let expectedError = NetworkError.noConnection
    mockService.errorToThrow = expectedError
    
    // When
    await sut.loadData()
    
    // Then
    XCTAssertTrue(sut.items.isEmpty)
    XCTAssertNotNil(sut.error)
}
```

### Testing Combine Publishers
```swift
func testPublishedPropertyUpdates() {
    // Given
    let expectation = expectation(description: "State updated")
    var receivedStates: [ViewState] = []
    
    sut.$state
        .dropFirst() // Skip initial value
        .sink { state in
            receivedStates.append(state)
            if receivedStates.count == 2 {
                expectation.fulfill()
            }
        }
        .store(in: &cancellables)
    
    // When
    sut.startOperation()
    
    // Then
    waitForExpectations(timeout: 1.0)
    XCTAssertEqual(receivedStates, [.loading, .loaded])
}
```

## Mock Objects

### Creating Mocks
```swift
class MockFeatureService: FeatureServiceProtocol {
    var itemsToReturn: [Item] = []
    var errorToThrow: Error?
    var fetchItemsCalled = false
    var fetchItemsCallCount = 0
    
    func fetchItems() async throws -> [Item] {
        fetchItemsCalled = true
        fetchItemsCallCount += 1
        
        if let error = errorToThrow {
            throw error
        }
        return itemsToReturn
    }
}
```

### Test Doubles Strategy
- Use protocols for all dependencies
- Create mock implementations for testing
- Verify interactions with mocks
- Use dependency injection for testability

## Async Testing

### Testing Async Functions
```swift
func testAsyncOperation() async throws {
    // Use async/await for testing async code
    let result = try await sut.performAsyncOperation()
    XCTAssertNotNil(result)
}

func testAsyncWithTimeout() async throws {
    // Set timeout for async operations
    let task = Task {
        try await sut.longRunningOperation()
    }
    
    let result = try await task.value(timeout: 5.0)
    XCTAssertNotNil(result)
}
```

### Testing Concurrent Code
```swift
func testConcurrentAccess() async {
    // Test thread safety
    await withTaskGroup(of: Void.self) { group in
        for i in 0..<100 {
            group.addTask {
                await self.sut.addItem(Item(id: i))
            }
        }
    }
    
    let items = await sut.getAllItems()
    XCTAssertEqual(items.count, 100)
}
```

## Integration Testing

### Database Testing
```swift
class DatabaseIntegrationTests: XCTestCase {
    private var database: TestDatabase!
    
    override func setUp() {
        super.setUp()
        // Use in-memory database for tests
        database = TestDatabase.inMemory()
    }
    
    func testDataPersistence() throws {
        // Given
        let bookmark = Bookmark(title: "Test", url: URL(string: "https://example.com")!)
        
        // When
        try database.save(bookmark)
        let loaded = try database.loadBookmarks()
        
        // Then
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded.first?.title, "Test")
    }
}
```

## UI Testing

### UI Test Structure
```swift
class FeatureUITests: XCTestCase {
    private var app: XCUIApplication!
    
    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["--uitesting"]
        app.launch()
    }
    
    func testNavigationFlow() {
        // Given
        let mainScreen = MainScreen(app: app)
        
        // When
        mainScreen.tapSettingsButton()
        let settingsScreen = SettingsScreen(app: app)
        
        // Then
        XCTAssertTrue(settingsScreen.isDisplayed)
    }
}
```

### Page Object Pattern
```swift
struct MainScreen {
    let app: XCUIApplication
    
    var settingsButton: XCUIElement {
        app.buttons["settings_button"]
    }
    
    func tapSettingsButton() {
        settingsButton.tap()
    }
    
    var isDisplayed: Bool {
        app.navigationBars["Main"].exists
    }
}
```

## Test Data

### Test Fixtures
```swift
extension Item {
    static func mock(
        id: Int = 1,
        title: String = "Test Item",
        isCompleted: Bool = false
    ) -> Item {
        Item(id: id, title: title, isCompleted: isCompleted)
    }
}

extension Array where Element == Item {
    static var mockItems: [Item] {
        [
            .mock(id: 1, title: "First"),
            .mock(id: 2, title: "Second"),
            .mock(id: 3, title: "Third", isCompleted: true)
        ]
    }
}
```

## Performance Testing

### Measure Performance
```swift
func testPerformanceOfLargeDataSet() {
    let items = (0..<10000).map { Item.mock(id: $0) }
    
    measure {
        _ = sut.processItems(items)
    }
}

func testMemoryUsage() {
    // Use memory graph debugger and instruments
    autoreleasepool {
        for _ in 0..<1000 {
            _ = sut.createLargeObject()
        }
    }
    
    XCTAssertTrue(sut.memoryFootprint < 100_000_000) // 100MB
}
```

## Best Practices

### Test Naming
```swift
// Use descriptive test names following given-when-then pattern
func test_loadData_whenServiceReturnsItems_updatesStateWithItems()
func test_deleteItem_whenItemDoesNotExist_throwsNotFoundError()
func test_refresh_whenNetworkUnavailable_showsErrorMessage()
```

### Assertions
```swift
// Use specific assertions
XCTAssertEqual(actual, expected, "Custom failure message")
XCTAssertTrue(condition, "Expected condition to be true")
XCTAssertNil(optionalValue, "Expected nil but got \(optionalValue!)")

// Use XCTUnwrap for optionals
let unwrappedValue = try XCTUnwrap(optionalValue)
XCTAssertEqual(unwrappedValue, expectedValue)
```

### Test Coverage
- Aim for >80% code coverage
- Test edge cases and error conditions
- Test both success and failure paths
- Don't test implementation details, test behavior

### Continuous Integration
- All tests must pass before merging
- Run tests on multiple iOS versions
- Include performance benchmarks
- Monitor test execution time