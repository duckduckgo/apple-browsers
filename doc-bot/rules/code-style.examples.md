---
alwaysApply: false
title: "Swift Code Style Examples"
description: "Detailed code examples demonstrating Swift style conventions for DuckDuckGo browser development"
keywords: ["Swift", "code examples", "style", "formatting", "patterns", "naming conventions"]
---

# Swift Code Style Examples

## Type Names Examples

```swift
// ✅ CORRECT: Descriptive, UpperCamelCase
class UserAuthenticationManager { }
struct BookmarkItem { }
enum NavigationState { }
protocol DataSourceProtocol { }

// ❌ INCORRECT: Too generic
class Manager { }
struct Data { }
```

## Variable and Function Names Examples

```swift
// ✅ CORRECT: Descriptive, clear intent
let maximumNumberOfLoginAttempts = 3
func fetchUserProfile(for userId: String) -> UserProfile
func updateBookmark(with url: URL, title: String)

// ❌ INCORRECT: Too brief or unclear
let max = 3
func fetch(_ id: String)
func update(_ url: URL)
```

## Protocol Naming Examples

```swift
// ✅ CORRECT: Nouns for capabilities
protocol DataSource { }
protocol NavigationDelegate { }

// ✅ CORRECT: -ing/-able for behaviors
protocol Downloading {
    func download(from url: URL)
}

protocol Cacheable {
    func cache()
}

// ❌ INCORRECT: Generic or unclear
protocol Helper { }
protocol Thing { }
```

## Method Naming Examples

```swift
// ✅ CORRECT: Clear action and parameters
func convert(_ temperature: Temperature, to unit: TemperatureUnit) -> Temperature
func move(from start: Point, to end: Point)
func addBookmark(for url: URL, in folder: BookmarkFolder?)

// ❌ INCORRECT: Unclear parameters
func convert(_ temp: Temperature, _ unit: TemperatureUnit) -> Temperature
func move(_ start: Point, _ end: Point)
```

## Delegate Method Naming

```swift
// ✅ CORRECT: Start with delegate name
protocol BookmarkManagerDelegate {
    func bookmarkManager(_ manager: BookmarkManager, didAdd bookmark: Bookmark)
    func bookmarkManager(_ manager: BookmarkManager, willRemove bookmark: Bookmark)
    func bookmarkManagerDidFinishImport(_ manager: BookmarkManager)
}

// ❌ INCORRECT: Unclear source
protocol BookmarkManagerDelegate {
    func didAddBookmark(_ bookmark: Bookmark)  // From where?
    func willRemove(_ bookmark: Bookmark)      // What will remove?
}
```

## Type Inferred Context Examples

```swift
// ✅ CORRECT: Use type inference when clear
let selector: Selector = #selector(buttonTapped)
let view = UIView(frame: .zero)
let bookmarks: [Bookmark] = []

// ❌ INCORRECT: Unnecessary type repetition
let selector: Selector = Selector(#selector(buttonTapped))
let view = UIView(frame: CGRect.zero)
```

## Generics Examples

```swift
// ✅ CORRECT: Descriptive generic names
struct NetworkResponse<ResponseData> {
    let data: ResponseData
}

func fetchData<DataType: Decodable>() -> DataType {
    // Implementation
}

// ❌ INCORRECT: Single letters for unclear generics
struct NetworkResponse<T> {  // What is T?
    let data: T
}
```

## File Organization Example

```swift
//
//  BookmarkViewModel.swift
//  DuckDuckGo
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
//

import Foundation
import Combine

// MARK: - Protocol Definitions

protocol BookmarkViewModelDelegate: AnyObject {
    func bookmarkViewModelDidUpdate(_ viewModel: BookmarkViewModel)
}

// MARK: - Main Implementation

final class BookmarkViewModel: ObservableObject {
    
    // MARK: - Properties
    
    // Public stored properties
    @Published var bookmarks: [Bookmark] = []
    @Published var isLoading = false
    
    // Private stored properties
    private let bookmarkManager: BookmarkManagerProtocol
    private var cancellables = Set<AnyCancellable>()
    
    // Computed properties
    var hasBookmarks: Bool {
        !bookmarks.isEmpty
    }
    
    // MARK: - Initialization
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.bookmarkManager = dependencies.bookmarkManager
    }
    
    // MARK: - Public Methods
    
    func loadBookmarks() {
        // Implementation
    }
    
    // MARK: - Private Methods
    
    private func setupBindings() {
        // Implementation
    }
}

// MARK: - Extensions

extension BookmarkViewModel {
    func bookmarkURL(at index: Int) -> URL? {
        guard bookmarks.indices.contains(index) else { return nil }
        return bookmarks[index].url
    }
}
```

## Function Declaration Examples

```swift
// ✅ CORRECT: Short function
func isValid() -> Bool {
    return !isEmpty && count > 0
}

// ✅ CORRECT: Multi-line parameter list
func authenticateUser(
    username: String,
    password: String,
    completion: @escaping (Result<User, AuthError>) -> Void
) {
    // Implementation
}

// ✅ CORRECT: Generic function with constraints
func sorted<T: Comparable>(
    _ elements: [T],
    by keyPath: KeyPath<T, String>
) -> [T] {
    // Implementation
}
```

## Closure Expression Examples

```swift
// ✅ CORRECT: Trailing closure
bookmarks.forEach { bookmark in
    process(bookmark)
}

// ✅ CORRECT: Single expression closure
let doubled = numbers.map { $0 * 2 }

// ✅ CORRECT: Multi-line closure with capture list
let networkTask = Task { [weak self] in
    guard let self = self else { return }
    
    do {
        let result = try await self.networkService.fetch()
        await MainActor.run {
            self.handleResult(result)
        }
    } catch {
        Logger.network.error("Network request failed: \(error)")
    }
}

// ✅ CORRECT: Chained methods with closures
let processedBookmarks = bookmarks
    .filter { $0.isValid }
    .sorted { $0.title < $1.title }
    .map { BookmarkViewModel(bookmark: $0) }
```

## Memory Management Examples

```swift
// ✅ CORRECT: Weak self in closure
class NetworkManager {
    func fetchData() {
        urlSession.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }
            self.handleResponse(data, error)
        }
    }
}

// ✅ CORRECT: Lazy initialization
class ExpensiveService {
    lazy var processor: DataProcessor = {
        DataProcessor(configuration: self.configuration)
    }()
}
```

## Control Flow Examples

```swift
// ✅ CORRECT: Guard for early returns
func processBookmark(_ bookmark: Bookmark?) {
    guard 
        let bookmark = bookmark,
        bookmark.isValid,
        !bookmark.isDeleted
    else {
        Logger.general.debug("Invalid bookmark")
        return
    }
    
    // Process valid bookmark
    updateUI(with: bookmark)
}

// ✅ CORRECT: Ternary for simple assignments
let statusText = isConnected ? "Online" : "Offline"

// ❌ INCORRECT: Ternary for complex operations
let result = isValid ? performComplexValidation() : showErrorAndReturnDefault()
```

## Class Definition Examples

```swift
// ✅ CORRECT: Well-organized class
final class BookmarkService {
    
    // MARK: - Properties
    
    private let networkClient: NetworkClient
    private let cacheStore: CacheStore
    
    // MARK: - Initialization
    
    init(networkClient: NetworkClient, cacheStore: CacheStore) {
        self.networkClient = networkClient
        self.cacheStore = cacheStore
    }
    
    // MARK: - Public Interface
    
    func fetchBookmarks() async throws -> [Bookmark] {
        if let cached = cacheStore.bookmarks, !cached.isEmpty {
            return cached
        }
        
        let bookmarks = try await networkClient.fetchBookmarks()
        cacheStore.store(bookmarks)
        return bookmarks
    }
    
    // MARK: - Private Helpers
    
    private func validateBookmark(_ bookmark: Bookmark) -> Bool {
        return !bookmark.title.isEmpty && bookmark.url.isValid
    }
}
```

## Async/Await Examples

```swift
// ✅ CORRECT: Async function
func fetchUserData(for userID: String) async throws -> User {
    let response = try await networkClient.get("/users/\(userID)")
    return try decoder.decode(User.self, from: response.data)
}

// ✅ CORRECT: Task with error handling
func updateBookmarks() {
    Task { @MainActor in
        do {
            isLoading = true
            bookmarks = try await bookmarkService.fetchAll()
        } catch {
            showError(error)
        }
        isLoading = false
    }
}

// ✅ CORRECT: TaskGroup for concurrent operations
func fetchAllData() async throws -> (bookmarks: [Bookmark], history: [HistoryItem]) {
    try await withThrowingTaskGroup(of: Any.self) { group in
        group.addTask { try await self.fetchBookmarks() }
        group.addTask { try await self.fetchHistory() }
        
        var bookmarks: [Bookmark] = []
        var history: [HistoryItem] = []
        
        for try await result in group {
            switch result {
            case let fetchedBookmarks as [Bookmark]:
                bookmarks = fetchedBookmarks
            case let fetchedHistory as [HistoryItem]:
                history = fetchedHistory
            default:
                break
            }
        }
        
        return (bookmarks, history)
    }
}
```

## Property Wrapper Examples

```swift
// ✅ CORRECT: AppStorage usage
struct SettingsView: View {
    @AppStorage("showFavicons") private var showFavicons = true
    @AppStorage("defaultSearchEngine") private var searchEngine = SearchEngine.duckDuckGo
    
    var body: some View {
        Form {
            Toggle("Show Favicons", isOn: $showFavicons)
            Picker("Search Engine", selection: $searchEngine) {
                ForEach(SearchEngine.allCases) { engine in
                    Text(engine.displayName).tag(engine)
                }
            }
        }
    }
}

// ✅ CORRECT: Custom property wrapper
@propertyWrapper
struct Clamped<Value: Comparable> {
    private var value: Value
    private let range: ClosedRange<Value>
    
    var wrappedValue: Value {
        get { value }
        set { value = max(range.lowerBound, min(range.upperBound, newValue)) }
    }
    
    init(wrappedValue: Value, _ range: ClosedRange<Value>) {
        self.range = range
        self.value = max(range.lowerBound, min(range.upperBound, wrappedValue))
    }
}

// Usage
struct VolumeControl {
    @Clamped(0...100) var volume: Int = 50
}
```

## Design System Integration Examples

```swift
// ✅ CORRECT: Use DesignResourcesKit
struct BookmarkCell: View {
    let bookmark: Bookmark
    
    var body: some View {
        HStack {
            Image(uiImage: DesignSystemImages.Glyphs.Size20.bookmark)
                .renderingMode(.template)
                .foregroundColor(Color(designSystemColor: .iconPrimary))
            
            Text(bookmark.title)
                .font(Font(designSystemFont: .body))
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
        .padding()
        .background(Color(designSystemColor: .backgroundSecondary))
    }
}

// ❌ INCORRECT: Hardcoded values
struct BookmarkCell: View {
    let bookmark: Bookmark
    
    var body: some View {
        HStack {
            Image(systemName: "bookmark")
                .foregroundColor(.blue)
            
            Text(bookmark.title)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.black)
        }
        .padding()
        .background(Color.gray.opacity(0.1))
    }
}
```

## Dependency Injection Examples

```swift
// ✅ CORRECT: Dependency injection pattern
final class BookmarkViewModel: ObservableObject {
    private let bookmarkService: BookmarkServiceProtocol
    private let analytics: AnalyticsTracking
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.bookmarkService = dependencies.bookmarkService
        self.analytics = dependencies.analytics
    }
}

// ❌ INCORRECT: Direct singleton usage
final class BookmarkViewModel: ObservableObject {
    private let bookmarkService = BookmarkService.shared  // Hard dependency
    private let analytics = Analytics.shared              // Hard dependency
}
```

## Testing Examples

```swift
// ✅ CORRECT: Testable code with dependency injection
class BookmarkManagerTests: XCTestCase {
    private var sut: BookmarkManager!
    private var mockNetworkClient: MockNetworkClient!
    private var mockCacheStore: MockCacheStore!
    
    override func setUp() {
        super.setUp()
        mockNetworkClient = MockNetworkClient()
        mockCacheStore = MockCacheStore()
        sut = BookmarkManager(
            networkClient: mockNetworkClient,
            cacheStore: mockCacheStore
        )
    }
    
    func testFetchBookmarks_WhenCacheEmpty_FetchesFromNetwork() async throws {
        // Given
        mockCacheStore.bookmarks = []
        mockNetworkClient.bookmarksToReturn = [
            Bookmark(title: "Test", url: URL(string: "https://example.com")!)
        ]
        
        // When
        let bookmarks = try await sut.fetchBookmarks()
        
        // Then
        XCTAssertEqual(bookmarks.count, 1)
        XCTAssertEqual(bookmarks.first?.title, "Test")
        XCTAssertTrue(mockNetworkClient.fetchBookmarksWasCalled)
    }
}
```