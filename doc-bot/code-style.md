---
alwaysApply: true
title: "Swift Code Style Guide"
description: "Swift code style and conventions for DuckDuckGo browser development including naming, formatting, and best practices"
keywords: ["Swift", "code style", "naming conventions", "formatting", "best practices", "async/await", "property wrappers"]
---

# Swift Code Style Guide

## Naming Conventions

### Type Names
```swift
// Use UpperCamelCase for types and protocols
class UserAuthenticationManager { }
struct BookmarkItem { }
enum NavigationState { }
protocol DataSourceProtocol { }

// Use descriptive names
// Bad
class Manager { }
struct Data { }

// Good
class BookmarkManager { }
struct UserData { }
```

### Variable and Function Names
```swift
// Use lowerCamelCase
let maximumRetryCount = 3
var isLoading = false
func fetchUserData() { }

// Boolean properties should read like assertions
var isEnabled: Bool
var hasCompleted: Bool
var canDelete: Bool

// Avoid abbreviations
// Bad
let usrMgr = UserManager()
func calcTotal() { }

// Good
let userManager = UserManager()
func calculateTotal() { }
```

### Protocol Naming
```swift
// Protocols describing capability should end in -able, -ible, or -ing
protocol Loadable { }
protocol Refreshable { }
protocol UserAuthenticating { }

// Protocols describing a type should be nouns
protocol DataSource { }
protocol Delegate { }
```

## Code Organization

### File Structure
```swift
// 1. Import statements
import UIKit
import Combine

// 2. Protocol conformance
protocol FeatureDelegate: AnyObject {
    func featureDidUpdate()
}

// 3. Main type declaration
class FeatureViewController: UIViewController {
    
    // MARK: - Types
    enum State {
        case idle
        case loading
        case loaded([Item])
        case error(Error)
    }
    
    // MARK: - Properties
    // Public properties first
    weak var delegate: FeatureDelegate?
    
    // Private properties
    private let viewModel: FeatureViewModel
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - UI Elements
    private lazy var tableView: UITableView = {
        let table = UITableView()
        table.delegate = self
        table.dataSource = self
        return table
    }()
    
    // MARK: - Lifecycle
    init(viewModel: FeatureViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
        bindViewModel()
    }
    
    // MARK: - Setup
    private func setupUI() {
        // UI setup code
    }
    
    private func bindViewModel() {
        // Binding code
    }
    
    // MARK: - Actions
    @objc private func refreshButtonTapped() {
        viewModel.refresh()
    }
}

// MARK: - UITableViewDataSource
extension FeatureViewController: UITableViewDataSource {
    // DataSource methods
}

// MARK: - UITableViewDelegate
extension FeatureViewController: UITableViewDelegate {
    // Delegate methods
}
```

## Swift Idioms

### Optionals
```swift
// Use optional binding
if let value = optionalValue {
    use(value)
}

// Use guard for early returns
guard let user = currentUser else {
    return
}

// Use nil-coalescing operator
let name = user.name ?? "Anonymous"

// Chain optionals
let street = user.address?.street?.name
```

### Error Handling
```swift
// Define clear error types
enum NetworkError: LocalizedError {
    case noConnection
    case timeout
    case serverError(Int)
    
    var errorDescription: String? {
        switch self {
        case .noConnection:
            return "No internet connection"
        case .timeout:
            return "Request timed out"
        case .serverError(let code):
            return "Server error: \(code)"
        }
    }
}

// Use do-try-catch
do {
    let data = try await networkClient.fetchData()
    process(data)
} catch NetworkError.noConnection {
    showOfflineMessage()
} catch {
    showGenericError(error)
}
```

### Closures
```swift
// Use trailing closure syntax
items.map { item in
    return item.name
}

// Shorthand for simple closures
items.map(\.name)
items.filter { $0.isEnabled }

// Capture lists to avoid retain cycles
viewModel.loadData { [weak self] result in
    guard let self = self else { return }
    self.handleResult(result)
}
```

## Modern Swift Features

### Async/Await
```swift
// Prefer async/await over completion handlers
// Bad
func fetchData(completion: @escaping (Result<Data, Error>) -> Void) {
    // Implementation
}

// Good
func fetchData() async throws -> Data {
    // Implementation
}

// Use TaskGroup for concurrent operations
func fetchMultipleItems(ids: [String]) async throws -> [Item] {
    try await withThrowingTaskGroup(of: Item.self) { group in
        for id in ids {
            group.addTask {
                try await self.fetchItem(id: id)
            }
        }
        
        var items: [Item] = []
        for try await item in group {
            items.append(item)
        }
        return items
    }
}
```

### Property Wrappers
```swift
// Use built-in property wrappers appropriately
class ViewModel: ObservableObject {
    @Published var items: [Item] = []
    @Published private(set) var isLoading = false
}

struct SettingsView: View {
    @AppStorage("theme") private var theme = Theme.automatic
    @StateObject private var viewModel = SettingsViewModel()
    @Environment(\.dismiss) private var dismiss
}
```

### Result Builders
```swift
// Use result builders for DSL-style APIs
@resultBuilder
struct PredicateBuilder {
    static func buildBlock(_ components: Predicate...) -> [Predicate] {
        components
    }
}

func filter(@PredicateBuilder _ builder: () -> [Predicate]) -> [Item] {
    let predicates = builder()
    return items.filter { item in
        predicates.allSatisfy { $0.evaluate(item) }
    }
}
```

## Comments and Documentation

### Documentation Comments
```swift
/// Manages user authentication and session handling.
///
/// This class handles login, logout, and session refresh operations.
/// It maintains the current user session and provides methods for
/// checking authentication status.
///
/// - Note: This class is thread-safe.
public class AuthenticationManager {
    
    /// Authenticates a user with the provided credentials.
    ///
    /// - Parameters:
    ///   - username: The user's username or email.
    ///   - password: The user's password.
    /// - Returns: The authenticated user object.
    /// - Throws: `AuthenticationError` if authentication fails.
    public func authenticate(
        username: String,
        password: String
    ) async throws -> User {
        // Implementation
    }
}
```

### Inline Comments
```swift
// Use comments to explain "why", not "what"
// Bad
// Increment counter by 1
counter += 1

// Good
// Retry count includes the initial attempt
retryCount += 1

// Use MARK comments to organize code
// MARK: - Properties
// MARK: - Lifecycle
// MARK: - Private Methods
// MARK: - Actions
```

## Code Formatting

### Indentation and Spacing
```swift
// Use 4 spaces for indentation (not tabs)
// Opening braces on the same line
if condition {
    doSomething()
} else {
    doSomethingElse()
}

// Space after colons in type declarations
let name: String
func configure(with model: Model)

// No space before colons
class MyClass: BaseClass {
    // Implementation
}
```

### Line Length
```swift
// Keep lines under 120 characters
// Break long function calls
let result = performComplexOperation(
    withParameter: parameter1,
    andAnotherParameter: parameter2,
    options: [.option1, .option2]
)

// Break long conditionals
if userIsLoggedIn &&
   hasValidSubscription &&
   !isInTrialPeriod {
    showPremiumContent()
}
```

### Function Declarations
```swift
// Short functions can be on one line
func isEmpty() -> Bool { items.count == 0 }

// Longer functions should be multi-line
func configure(
    title: String,
    subtitle: String? = nil,
    image: UIImage? = nil
) {
    self.title = title
    self.subtitle = subtitle
    self.image = image
}

// Omit void return types
// Bad
func doSomething() -> Void { }

// Good
func doSomething() { }
```

## Access Control

### Explicit Access Levels
```swift
// Be explicit about access control
public class PublicClass {
    public var publicProperty: String
    internal var internalProperty: String
    fileprivate var fileprivateProperty: String
    private var privateProperty: String
    
    public init() {
        // Initialize properties
    }
    
    private func helperMethod() {
        // Private implementation
    }
}

// Use private(set) for read-only properties
public class DataManager {
    public private(set) var items: [Item] = []
    
    public func addItem(_ item: Item) {
        items.append(item)
    }
}
```

## Constants

### Global Constants
```swift
// Group related constants in enums
enum Constants {
    enum Animation {
        static let defaultDuration: TimeInterval = 0.3
        static let springDamping: CGFloat = 0.8
    }
    
    enum Networking {
        static let timeout: TimeInterval = 30
        static let maxRetries = 3
    }
}

// Use static let for type-level constants
extension UIColor {
    static let brandPrimary = UIColor(hex: "#5B40FF")
    static let brandSecondary = UIColor(hex: "#00BAD1")
}
```

## Best Practices

### Prefer Value Types
```swift
// Use structs for simple data holders
struct UserProfile {
    let id: String
    let name: String
    var email: String
}

// Use classes only when you need reference semantics
class NetworkManager {
    static let shared = NetworkManager()
    private init() { }
}
```

### Avoid Force Unwrapping
```swift
// Bad
let name = user.name!

// Good
guard let name = user.name else {
    return
}

// Or use default values
let name = user.name ?? "Unknown"
```

### Use Extensions
```swift
// Organize code with extensions
extension String {
    var isValidEmail: Bool {
        // Email validation logic
    }
}

// Conform to protocols in extensions
extension ViewController: UITableViewDelegate {
    // Delegate methods
}
```