---
alwaysApply: false
title: "Anti-patterns Examples"
description: "Detailed examples of anti-patterns to avoid in DuckDuckGo browser development"
keywords: ["anti-patterns", "examples", "memory leaks", "retain cycles", "singletons", "threading", "performance"]
---

# Anti-patterns Examples

## Singleton Anti-patterns Examples

```swift
// ❌ BAD - Singleton abuse
class NetworkManager {
    static let shared = NetworkManager()
    private init() {}
    
    func fetchData() { }
}

class UserManager {
    static let shared = UserManager()
    private init() {}
}

// Everything depends on global state
class ViewModel {
    func loadData() {
        NetworkManager.shared.fetchData()
        UserManager.shared.getCurrentUser()
    }
}

// ✅ GOOD - Dependency injection
protocol NetworkManaging {
    func fetchData() async throws -> Data
}

class NetworkManager: NetworkManaging {
    func fetchData() async throws -> Data { /* implementation */ }
}

class ViewModel {
    private let networkManager: NetworkManaging
    
    init(networkManager: NetworkManaging = AppDependencyProvider.shared.networkManager) {
        self.networkManager = networkManager
    }
    
    func loadData() async {
        do {
            let data = try await networkManager.fetchData()
            // Process data
        } catch {
            // Handle error
        }
    }
}
```

## Memory Leak Examples

### Retain Cycle Examples

```swift
// ❌ BAD - Closure retain cycle
class DataService {
    var onDataReceived: ((Data) -> Void)?
    
    func fetchData() {
        onDataReceived = { data in
            self.processData(data)  // Strong reference to self
        }
    }
}

// ✅ GOOD - Weak self
class DataService {
    var onDataReceived: ((Data) -> Void)?
    
    func fetchData() {
        onDataReceived = { [weak self] data in
            self?.processData(data)
        }
    }
}

// ❌ BAD - Delegate retain cycle
class ViewController: UIViewController {
    let service = NetworkService()
    
    override func viewDidLoad() {
        super.viewDidLoad()
        service.delegate = self  // Strong reference if delegate isn't weak
    }
}

// ✅ GOOD - Weak delegate
protocol NetworkServiceDelegate: AnyObject {
    func networkService(_ service: NetworkService, didReceive data: Data)
}

class NetworkService {
    weak var delegate: NetworkServiceDelegate?  // Weak reference
}
```

### Timer Retain Cycles

```swift
// ❌ BAD - Timer retains self
class PollingManager {
    var timer: Timer?
    
    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { _ in
            self.poll()  // Timer retains closure, closure retains self
        }
    }
}

// ✅ GOOD - Weak self in timer
class PollingManager {
    var timer: Timer?
    
    func startPolling() {
        timer = Timer.scheduledTimer(withTimeInterval: 5.0, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }
    
    deinit {
        timer?.invalidate()
        timer = nil
    }
}
```

## Async/Await Anti-patterns

```swift
// ❌ BAD - Blocking main thread
func loadData() {
    let semaphore = DispatchSemaphore(value: 0)
    var result: Data?
    
    URLSession.shared.dataTask(with: url) { data, _, _ in
        result = data
        semaphore.signal()
    }.resume()
    
    semaphore.wait()  // Blocks current thread
    return result
}

// ✅ GOOD - Proper async/await
func loadData() async throws -> Data {
    let (data, _) = try await URLSession.shared.data(from: url)
    return data
}

// ❌ BAD - Mixing completion handlers with async/await
func fetchUserData() async throws -> User {
    return try await withCheckedThrowingContinuation { continuation in
        NetworkManager.shared.fetchUser { result in  // Unnecessary wrapper
            switch result {
            case .success(let user):
                continuation.resume(returning: user)
            case .failure(let error):
                continuation.resume(throwing: error)
            }
        }
    }
}

// ✅ GOOD - Native async/await
func fetchUserData() async throws -> User {
    let userData = try await networkManager.fetchUserData()
    return try JSONDecoder().decode(User.self, from: userData)
}
```

## Force Unwrapping Anti-patterns

```swift
// ❌ BAD - Force unwrapping without safety
func openURL(_ urlString: String) {
    let url = URL(string: urlString)!  // Crash if invalid
    UIApplication.shared.open(url)
}

func processResponse(_ response: HTTPURLResponse) {
    let data = response.data!  // Properties don't exist
    let json = try! JSONSerialization.jsonObject(with: data)  // Can throw
}

// ✅ GOOD - Safe unwrapping
func openURL(_ urlString: String) {
    guard let url = URL(string: urlString) else {
        Logger.general.error("Invalid URL: \(urlString)")
        return
    }
    UIApplication.shared.open(url)
}

func processResponse(data: Data) {
    do {
        let json = try JSONSerialization.jsonObject(with: data)
        // Process JSON
    } catch {
        Logger.general.error("Failed to parse JSON: \(error)")
    }
}
```

## Threading Anti-patterns

```swift
// ❌ BAD - UI updates on background thread
func updateUI() {
    DispatchQueue.global().async {
        self.label.text = "Updated"  // Crash or undefined behavior
        self.imageView.image = processedImage
    }
}

// ✅ GOOD - UI updates on main thread
func updateUI() {
    DispatchQueue.global().async {
        let processedImage = self.processImage()
        
        DispatchQueue.main.async {
            self.label.text = "Updated"
            self.imageView.image = processedImage
        }
    }
}

// ✅ BETTER - Using MainActor
@MainActor
func updateUI() async {
    let processedImage = await processImageInBackground()
    label.text = "Updated"
    imageView.image = processedImage
}

func processImageInBackground() async -> UIImage {
    // Heavy processing on background thread
    await Task.detached {
        // Image processing
        return processedImage
    }.value
}
```

## Error Handling Anti-patterns

```swift
// ❌ BAD - Silently ignoring errors
func saveData() {
    do {
        try coreDataContext.save()
    } catch {
        // Silent failure - data loss!
    }
}

// ❌ BAD - Generic error messages
func authenticateUser() throws {
    guard isValidCredentials else {
        throw NSError(domain: "Error", code: 1, userInfo: nil)  // Useless error
    }
}

// ✅ GOOD - Proper error handling
func saveData() {
    do {
        try coreDataContext.save()
    } catch {
        Logger.general.error("Failed to save Core Data context: \(error)")
        // Show user-appropriate error message
        showErrorAlert("Unable to save your changes. Please try again.")
    }
}

// ✅ GOOD - Meaningful errors
enum AuthenticationError: LocalizedError {
    case invalidUsername
    case invalidPassword
    case accountLocked
    
    var errorDescription: String? {
        switch self {
        case .invalidUsername:
            return "Username not found"
        case .invalidPassword:
            return "Incorrect password"
        case .accountLocked:
            return "Account has been temporarily locked"
        }
    }
}
```

## Testing Anti-patterns

```swift
// ❌ BAD - Testing implementation details
func testViewControllerInternals() {
    let vc = ViewController()
    vc.loadView()
    
    // Testing private methods
    XCTAssertTrue(vc.validateInternalState())
    XCTAssertEqual(vc.privateCounter, 5)
}

// ❌ BAD - Flaky time-dependent tests
func testAsyncOperation() {
    service.performAsyncOperation()
    
    // Race condition - test might fail randomly
    Thread.sleep(forTimeInterval: 0.1)
    XCTAssertTrue(service.isComplete)
}

// ✅ GOOD - Testing behavior, not implementation
func testViewControllerDisplaysData() {
    let viewModel = MockViewModel()
    let vc = ViewController(viewModel: viewModel)
    
    viewModel.data = [testData]
    vc.loadView()
    
    // Test visible behavior
    XCTAssertEqual(vc.tableView.numberOfRows(inSection: 0), 1)
}

// ✅ GOOD - Deterministic async testing
func testAsyncOperation() async {
    let expectation = XCTestExpectation(description: "Operation completes")
    
    service.performAsyncOperation { result in
        XCTAssertNotNil(result)
        expectation.fulfill()
    }
    
    await fulfillment(of: [expectation], timeout: 5.0)
}
```

## Performance Anti-patterns

```swift
// ❌ BAD - Expensive operations on main thread
func processLargeDataSet() {
    let processedData = largeDataSet.map { expensiveOperation($0) }  // Blocks UI
    updateUI(with: processedData)
}

// ❌ BAD - Creating expensive objects repeatedly
func formatDates(_ dates: [Date]) -> [String] {
    return dates.map { date in
        let formatter = DateFormatter()  // Expensive creation in loop
        formatter.dateStyle = .medium
        return formatter.string(from: date)
    }
}

// ✅ GOOD - Background processing
func processLargeDataSet() async {
    let processedData = await Task.detached {
        largeDataSet.map { expensiveOperation($0) }
    }.value
    
    await MainActor.run {
        updateUI(with: processedData)
    }
}

// ✅ GOOD - Reuse expensive objects
private static let dateFormatter: DateFormatter = {
    let formatter = DateFormatter()
    formatter.dateStyle = .medium
    return formatter
}()

func formatDates(_ dates: [Date]) -> [String] {
    return dates.map { Self.dateFormatter.string(from: $0) }
}
```

## SwiftUI Anti-patterns

```swift
// ❌ BAD - Heavy computation in body
struct ExpensiveView: View {
    let items: [Item]
    
    var body: some View {
        let processedItems = items
            .filter { $0.isValid }
            .sorted { $0.priority > $1.priority }  // Runs on every render
        
        List(processedItems) { item in
            ItemRow(item: item)
        }
    }
}

// ❌ BAD - Wrong property wrapper usage
struct BadStateView: View {
    @State var viewModel: ViewModel  // Wrong - @State is for simple values
    
    var body: some View {
        Text(viewModel.title)
    }
}

// ✅ GOOD - Computed property for expensive operations
struct EfficientView: View {
    let items: [Item]
    
    private var processedItems: [ProcessedItem] {
        items
            .filter { $0.isValid }
            .sorted { $0.priority > $1.priority }
    }
    
    var body: some View {
        List(processedItems) { item in
            ItemRow(item: item)
        }
    }
}

// ✅ GOOD - Correct property wrapper
struct GoodStateView: View {
    @StateObject private var viewModel = ViewModel()  // For owned objects
    // OR @ObservedObject var viewModel: ViewModel    // For injected objects
    
    var body: some View {
        Text(viewModel.title)
    }
}
```