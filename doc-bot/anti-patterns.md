---
alwaysApply: true
title: "Anti-patterns and Common Mistakes"
description: "Anti-patterns to avoid and common mistakes to prevent in DuckDuckGo browser development including singleton misuse, memory leaks, and performance issues"
keywords: ["anti-patterns", "common mistakes", "singletons", "memory leaks", "async/await", "error handling", "performance", "testing"]
---

# Anti-patterns and Common Mistakes to Avoid

## Singleton Anti-patterns

### ❌ NEVER: Static Shared Instances Without Dependency Injection (.shared instance pattern)
```swift
// ❌ AVOID - Static shared instance without DI
final class FeatureManager {
    static let shared = FeatureManager()
    private init() {}
    
    func performAction() {
        // Implementation
    }
}

// Usage:
FeatureManager.shared.performAction() // Hard to test and tightly coupled

// ✅ CORRECT - Dependency injection pattern
protocol FeatureManagerProtocol {
    func performAction()
}

final class FeatureManager: FeatureManagerProtocol {
    func performAction() {
        // Implementation
    }
}

// Register in AppDependencyProvider
extension AppDependencyProvider {
    var featureManager: FeatureManagerProtocol {
        return FeatureManager()
    }
}

// Usage:
final class ViewModel {
    private let featureManager: FeatureManagerProtocol
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.featureManager = dependencies.featureManager
    }
}
```

### ❌ NEVER: Global State Access
```swift
// ❌ AVOID - Global state access
var globalSettings: [String: Any] = [:]

func someFunction() {
    globalSettings["key"] = "value" // Global state is hard to test and debug
}

// ✅ CORRECT - Injected dependencies
final class SomeService {
    private let settings: AppSettings
    
    init(settings: AppSettings) {
        self.settings = settings
    }
    
    func someFunction() {
        settings.setValue("value", for: "key")
    }
}
```

## Async/Await Anti-patterns

### ❌ NEVER: UI Updates Without @MainActor
```swift
// ❌ AVOID - UI updates without main thread guarantee
class ViewModel: ObservableObject {
    @Published var isLoading = false
    
    func loadData() async {
        isLoading = true // May crash if not on main thread
        let data = try? await service.fetchData()
        isLoading = false // May crash if not on main thread
    }
}

// ✅ CORRECT - @MainActor for UI updates
@MainActor
class ViewModel: ObservableObject {
    @Published var isLoading = false
    
    func loadData() async {
        isLoading = true
        let data = try? await service.fetchData()
        isLoading = false
    }
}
```

### ❌ NEVER: Unhandled Async Errors
```swift
// ❌ AVOID - Swallowing async errors
func fetchData() async {
    let data = try? await networkService.getData() // Silently ignoring errors
    // Process data...
}

// ✅ CORRECT - Proper error handling
func fetchData() async throws {
    let data = try await networkService.getData()
    // Process data...
}

// Or handle errors appropriately:
func fetchData() async {
    do {
        let data = try await networkService.getData()
        // Process data...
    } catch {
        // Log error and show user-friendly message
        logger.error("Failed to fetch data: \(error)")
        await showError(error)
    }
}
```

### ❌ NEVER: Blocking Main Thread with Sync Operations
```swift
// ❌ AVOID - Blocking main thread
@MainActor
func loadData() {
    let data = NetworkService.fetchDataSynchronously() // Blocks UI
    updateUI(with: data)
}

// ✅ CORRECT - Use async operations
@MainActor
func loadData() async {
    let data = try await NetworkService.fetchData() // Non-blocking
    updateUI(with: data)
}
```

## Memory Management Anti-patterns

### ❌ NEVER: Strong Reference Cycles in Closures
```swift
// ❌ AVOID - Strong reference cycle
class ViewController: UIViewController {
    private var timer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateUI() // Strong reference cycle - ViewController won't be deallocated
        }
    }
}

// ✅ CORRECT - Weak self to break cycle
class ViewController: UIViewController {
    private var timer: Timer?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateUI()
        }
    }
    
    deinit {
        timer?.invalidate()
    }
}
```

### ❌ NEVER: Retaining View Controllers in Cache
```swift
// ❌ AVOID - Caching view controllers without cleanup
class NavigationManager {
    private var cachedViewControllers: [String: UIViewController] = [:]
    
    func getViewController(for identifier: String) -> UIViewController {
        if let cached = cachedViewControllers[identifier] {
            return cached // May contain stale data and strong references
        }
        let vc = createViewController(for: identifier)
        cachedViewControllers[identifier] = vc
        return vc
    }
}

// ✅ CORRECT - Cache view models, not view controllers
class NavigationManager {
    private var cachedViewModels: [String: ViewModel] = [:]
    
    func getViewController(for identifier: String) -> UIViewController {
        let viewModel = getOrCreateViewModel(for: identifier)
        return createViewController(with: viewModel)
    }
    
    private func getOrCreateViewModel(for identifier: String) -> ViewModel {
        if let cached = cachedViewModels[identifier] {
            return cached
        }
        let viewModel = createViewModel(for: identifier)
        cachedViewModels[identifier] = viewModel
        return viewModel
    }
}
```

## Error Handling Anti-patterns

### ❌ NEVER: Force Unwrapping Without Justification
```swift
// ❌ AVOID - Force unwrapping
func processUser() {
    let user = getCurrentUser()!  // Will crash if no user
    let name = user.name!         // Will crash if no name
    displayName(name)
}

// ✅ CORRECT - Safe unwrapping
func processUser() {
    guard let user = getCurrentUser(),
          let name = user.name else {
        showErrorMessage("User information unavailable")
        return
    }
    displayName(name)
}
```

### ❌ NEVER: Generic Error Messages
```swift
// ❌ AVOID - Generic error handling
func handleError(_ error: Error) {
    print("Something went wrong") // Not helpful for debugging
    showAlert("Error occurred")   // Not helpful for users
}

// ✅ CORRECT - Specific error handling
enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case unauthorized
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection. Please check your network settings."
        case .timeout:
            return "Request timed out. Please try again."
        case .unauthorized:
            return "You are not authorized to access this resource."
        case .serverError(let code):
            return "Server error (\(code)). Please try again later."
        }
    }
}

func handleNetworkError(_ error: NetworkError) {
    logger.error("Network error: \(error)")
    showAlert(error.localizedDescription)
}
```

## SwiftUI Anti-patterns

### ❌ NEVER: Heavy Computation in View Body
```swift
// ❌ AVOID - Expensive operations in body
struct ContentView: View {
    let items: [Item]
    
    var body: some View {
        List {
            ForEach(items) { item in
                Text(expensiveProcessing(item)) // Computed every view update
            }
        }
    }
    
    private func expensiveProcessing(_ item: Item) -> String {
        // Heavy computation
        return item.data.complexProcessing()
    }
}

// ✅ CORRECT - Pre-compute or use lazy loading
struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    
    var body: some View {
        List {
            ForEach(viewModel.processedItems) { item in
                Text(item.displayText)
            }
        }
        .onAppear {
            viewModel.processItems()
        }
    }
}
```

### ❌ NEVER: Direct State Mutation from View
```swift
// ❌ AVOID - Direct state mutation in view
struct ContentView: View {
    @State private var items: [Item] = []
    
    var body: some View {
        List {
            ForEach(items) { item in
                ItemRow(item: item) { updatedItem in
                    // Don't mutate state directly in view
                    if let index = items.firstIndex(where: { $0.id == updatedItem.id }) {
                        items[index] = updatedItem
                    }
                }
            }
        }
    }
}

// ✅ CORRECT - Use ViewModel for state management
struct ContentView: View {
    @StateObject private var viewModel: ContentViewModel
    
    var body: some View {
        List {
            ForEach(viewModel.items) { item in
                ItemRow(item: item) { updatedItem in
                    viewModel.updateItem(updatedItem)
                }
            }
        }
    }
}
```

## Design System Anti-patterns

### ❌ NEVER: Hardcoded Colors or Icons
```swift
// ❌ AVOID - Hardcoded colors and system icons
struct FeatureView: View {
    var body: some View {
        VStack {
            Image(systemName: "star.fill") // Use DesignResourcesKit icons
                .foregroundColor(.blue)   // Use semantic colors
            
            Text("Title")
                .foregroundColor(.black)  // Doesn't adapt to dark mode
        }
        .background(.gray)               // Use semantic colors
    }
}

// ✅ CORRECT - Design system integration
struct FeatureView: View {
    var body: some View {
        VStack {
            Image(uiImage: DesignSystemImages.Color.Size16.star)
                .foregroundColor(Color(designSystemColor: .accent))
            
            Text("Title")
                .foregroundColor(Color(designSystemColor: .textPrimary))
        }
        .background(Color(designSystemColor: .surface))
    }
}
```

## Network and API Anti-patterns

### ❌ NEVER: Hardcoded URLs or API Keys
```swift
// ❌ AVOID - Hardcoded values
func fetchData() async throws -> Data {
    let url = URL(string: "https://api.example.com/data")! // Hardcoded URL
    let apiKey = "abc123xyz"                               // Hardcoded API key
    
    var request = URLRequest(url: url)
    request.addValue(apiKey, forHTTPHeaderField: "Authorization")
    
    let (data, _) = try await URLSession.shared.data(for: request)
    return data
}

// ✅ CORRECT - Configuration-based approach
struct APIConfiguration {
    let baseURL: URL
    let apiKey: String
    
    static let production = APIConfiguration(
        baseURL: URL(string: "https://api.duckduckgo.com")!,
        apiKey: Bundle.main.object(forInfoDictionaryKey: "API_KEY") as! String
    )
}

func fetchData() async throws -> Data {
    let config = APIConfiguration.production
    let url = config.baseURL.appendingPathComponent("data")
    
    var request = URLRequest(url: url)
    request.addValue(config.apiKey, forHTTPHeaderField: "Authorization")
    
    let (data, _) = try await URLSession.shared.data(for: request)
    return data
}
```

## Testing Anti-patterns

### ❌ NEVER: Testing Implementation Details
```swift
// ❌ AVOID - Testing private implementation
class ViewModelTests: XCTestCase {
    func testPrivateMethod() {
        let viewModel = ViewModel()
        
        // Don't test private methods directly
        let result = viewModel.privateHelperMethod()
        XCTAssertEqual(result, expected)
    }
}

// ✅ CORRECT - Test public behavior
class ViewModelTests: XCTestCase {
    func testLoadDataUpdatesState() async {
        let mockService = MockDataService()
        let viewModel = ViewModel(service: mockService)
        
        await viewModel.loadData()
        
        // Test the observable behavior, not implementation
        XCTAssertFalse(viewModel.isLoading)
        XCTAssertNotNil(viewModel.data)
        XCTAssertNil(viewModel.error)
    }
}
```

### ❌ NEVER: Tests That Don't Test Anything
```swift
// ❌ AVOID - Tests without assertions
func testInitialization() {
    let viewModel = ViewModel()
    // Test does nothing
}

// ❌ AVOID - Tests that can't fail
func testAlwaysTrue() {
    XCTAssertTrue(true) // This test is meaningless
}

// ✅ CORRECT - Meaningful tests with specific assertions
func testInitializationSetsDefaultState() {
    let viewModel = ViewModel()
    
    XCTAssertEqual(viewModel.state, .idle)
    XCTAssertTrue(viewModel.items.isEmpty)
    XCTAssertFalse(viewModel.isLoading)
}
```

## Performance Anti-patterns

### ❌ NEVER: Synchronous Operations on Main Thread
```swift
// ❌ AVOID - Blocking main thread
@MainActor
func processLargeDataSet() {
    let result = heavyComputation() // Blocks UI
    updateUI(with: result)
}

// ✅ CORRECT - Background processing
@MainActor
func processLargeDataSet() async {
    let result = await Task.detached(priority: .userInitiated) {
        return heavyComputation()
    }.value
    
    updateUI(with: result)
}
```

## Communication Anti-patterns

### ❌ NEVER: Celebrate Partial Results or Progress
```
// ❌ AVOID - Celebrating when work is incomplete
"✅ MISSION ACCOMPLISHED!" (when tests still failing)
"🎯 Outstanding Achievement:" (when task isn't finished)
"📊 FINAL RESULTS:" (when results aren't final)
"✅ Successfully achieved X" (when Y tests still failing)

// ✅ CORRECT - Focus on what's left to do
"7 tests still failing. Continuing to fix remaining issues."
"Progress made but task incomplete. Working on remaining failures."
"X tests now passing, Y still need work."
```

**Never celebrate or summarize achievements when:**
- Tests are still failing
- Tasks are incomplete
- User's request hasn't been fully satisfied
- Work is in progress

**Only summarize results when:**
- ALL tests pass (100% success rate)
- Task is completely finished
- User's request is fully satisfied
- No work remaining

These anti-patterns should be actively avoided to maintain code quality, testability, and performance in the DuckDuckGo browser codebase.