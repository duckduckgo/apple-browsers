---
alwaysApply: true
title: "Swift Code Style Guide"
description: "Swift code style and conventions for DuckDuckGo browser development including naming, formatting, and best practices"
keywords: ["Swift", "code style", "naming conventions", "formatting", "best practices", "async/await", "property wrappers", "SwiftLint"]
---

# Swift Code Style Guide

*This style guide is based on the [official iOS style guide](iOS/styleguide/STYLEGUIDE.md) and incorporates DuckDuckGo-specific patterns and requirements.*

## Correctness

**Strive to make your code compile without warnings.** This rule informs many style decisions such as using `#selector` types instead of string literals.

## SwiftLint

We use [SwiftLint](https://github.com/realm/SwiftLint) for enforcing Swift style and conventions. See the [SwiftLint configuration](.swiftlint.yml) for specific rules.

**Key SwiftLint settings**:
- Line length: 150 characters (not the default 100)
- Force cast/try: warnings (not errors for pragmatic development)
- Identifier naming: flexible for single-letter variables in closures

## Naming Conventions

Follow the [Swift API Design Guidelines](https://swift.org/documentation/api-design-guidelines/) with these key principles:

### Core Principles
- **Clarity at the call site** over brevity
- **Use camelCase** (not snake_case)
- **UpperCamelCase** for types and protocols
- **lowerCamelCase** for everything else
- **Include all needed words** while omitting needless words
- **Use names based on roles**, not types

### Type Names
Use **UpperCamelCase** for classes, structs, enums, and protocols. Names should be descriptive and avoid generic terms.

📖 **[See detailed examples →](code-style.examples.md#type-names-examples)**

### Variable and Function Names
Use **lowerCamelCase** for variables, functions, and methods. Names should be descriptive and boolean properties should read like assertions.

📖 **[See detailed examples →](code-style.examples.md#variable-and-function-names-examples)**

### Protocol Naming
- **Capability protocols**: end in `-able`, `-ible`, `-ing`
- **Type protocols**: use nouns

📖 **[See detailed examples →](code-style.examples.md#protocol-naming-examples)**

### Method Naming Patterns
- **Factory methods**: begin with "make"
- **Non-mutating methods**: use `-ed`, `-ing` forms
- **Boolean methods**: read like assertions

📖 **[See detailed examples →](code-style.examples.md#method-naming-examples)**

### Delegate Methods
When creating custom delegate methods, the **unnamed first parameter should be the delegate source**:

```swift
// ✅ CORRECT: Delegate pattern
func namePickerView(_ namePickerView: NamePickerView, didSelectName name: String)
func namePickerViewShouldReload(_ namePickerView: NamePickerView) -> Bool

// ❌ INCORRECT: Missing source parameter
func didSelectName(namePicker: NamePickerViewController, name: String)
func namePickerShouldReload() -> Bool
```

### Use Type Inferred Context
Use compiler inferred context to write shorter, clear code:

```swift
// ✅ CORRECT: Type inferred context
let selector = #selector(viewDidLoad)
view.backgroundColor = .red
let toView = context.view(forKey: .to)
let view = UIView(frame: .zero)

// ❌ INCORRECT: Redundant type information
let selector = #selector(ViewController.viewDidLoad)
view.backgroundColor = UIColor.red
let toView = context.view(forKey: UITransitionContextViewKey.to)
let view = UIView(frame: CGRect.zero)
```

### Generics
Generic type parameters should be **descriptive, UpperCamelCase names**:

```swift
// ✅ CORRECT: Descriptive generic names
struct Stack<Element> { ... }
func write<Target: OutputStream>(to target: inout Target)
func swap<T>(_ a: inout T, _ b: inout T)  // T is acceptable when no meaningful relationship

// ❌ INCORRECT: Non-descriptive or wrong case
struct Stack<T> { ... }
func write<target: OutputStream>(to target: inout target)
```

### Language
Use **US English spelling** to match Apple's API:

```swift
// ✅ CORRECT: US English
let color = "red"

// ❌ INCORRECT: British English
let colour = "red"
```

## Code Organization

### File Structure
```swift
// 1. Import statements (minimal - only what's needed)
import UIKit
import Combine

// 2. Protocol definitions
protocol FeatureDelegate: AnyObject {
    func featureDidUpdate()
}

// 3. Main type declaration
class FeatureViewController: UIViewController {
    // Properties first
    private let viewModel: FeatureViewModel
    
    // Lifecycle methods
    override func viewDidLoad() {
        super.viewDidLoad()
        setupUI()
    }
    
    // Private methods
    private func setupUI() { }
}

// 4. Extensions for protocol conformance
// MARK: - UITableViewDataSource
extension FeatureViewController: UITableViewDataSource {
    // Protocol methods
}
```

### Protocol Conformance
**Prefer separate extensions** for protocol conformance to keep related methods grouped:

```swift
// ✅ CORRECT: Separate extensions
class MyViewController: UIViewController {
    // class implementation
}

// MARK: - UITableViewDataSource
extension MyViewController: UITableViewDataSource {
    // table view data source methods
}

// MARK: - UIScrollViewDelegate
extension MyViewController: UIScrollViewDelegate {
    // scroll view delegate methods
}

// ❌ INCORRECT: All in main class declaration
class MyViewController: UIViewController, UITableViewDataSource, UIScrollViewDelegate {
    // all methods mixed together
}
```

### Minimal Imports
**Import only the modules a source file requires**:

```swift
// ✅ CORRECT: Minimal imports
import UIKit
var view: UIView
var deviceModels: [String]

// ✅ CORRECT: Foundation when UIKit not needed
import Foundation
var deviceModels: [String]

// ❌ INCORRECT: Unnecessary imports
import UIKit
import Foundation  // UIKit already includes Foundation
var view: UIView
var deviceModels: [String]
```

### Remove Unused Code
**Remove unused (dead) code**, including Xcode template code:

```swift
// ✅ CORRECT: Keep only implemented methods
override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
    return Database.contacts.count
}

// ❌ INCORRECT: Template code and unused methods
override func didReceiveMemoryWarning() {
    super.didReceiveMemoryWarning()
    // Dispose of any resources that can be recreated.
}

override func numberOfSections(in tableView: UITableView) -> Int {
    // #warning Incomplete implementation, return the number of sections
    return 1
}
```

## Formatting and Style

### Line Breaks and Length
- **Line margin: 150 characters** (not the default 100)
- **Long lines should be wrapped** at around 150 characters
- **Avoid trailing whitespace** at ends of lines
- **Add single newline** at end of each file

### Spacing
- **Indent using 4 spaces** rather than tabs
- **Method braces open on same line**, close on new line
- **One blank line between methods**
- **No blank lines after opening brace or before closing brace**

```swift
// ✅ CORRECT: Spacing and braces
if user.isHappy {
    // Do something
} else {
    // Do something else
}

// ❌ INCORRECT: Wrong brace placement
if user.isHappy
{
    // Do something
}
else {
    // Do something else
}
```

### Colons
**Colons have no space on left, one space on right**. Exceptions: ternary operator `? :`, empty dictionary `[:]`, `#selector` syntax:

```swift
// ✅ CORRECT: Colon spacing
class TestDatabase: Database {
    var data: [String: CGFloat] = ["A": 1.2, "B": 3.2]
}

// ❌ INCORRECT: Wrong colon spacing
class TestDatabase : Database {
    var data :[String:CGFloat] = ["A" : 1.2, "B":3.2]
}
```

### Function Parameters
**Closing parentheses should not appear on line by themselves**:

```swift
// ✅ CORRECT: Closing parenthesis placement
let user = try await getUser(
    for: userID,
    on: connection)

// ❌ INCORRECT: Closing parenthesis on own line
let user = try await getUser(
    for: userID,
    on: connection
)
```

## Function Declarations

### Short Functions
**Keep short function declarations on one line**:

```swift
// ✅ CORRECT: Short function on one line
func reticulateSplines(spline: [Double]) -> Bool {
    // implementation
}
```

### Long Function Signatures
**For functions with long signatures, put each parameter on new line**:

```swift
// ✅ CORRECT: Long signature formatting
func reticulateSplines(spline: [Double],
                      adjustmentFactor: Double,
                      translateConstant: Int,
                      comment: String) -> Bool {
    // implementation
}
```

### Return Types
**Use `Void` for closure/function outputs, `()` for inputs**:

```swift
// ✅ CORRECT: Return type formatting
func updateConstraints() -> Void {
    // implementation
}

typealias CompletionHandler = (result) -> Void

// ❌ INCORRECT: Wrong return type syntax
func updateConstraints() -> () {
    // implementation
}

typealias CompletionHandler = (result) -> ()
```

## Function Calls

**Mirror function declaration style at call sites**:

```swift
// ✅ CORRECT: Single line when it fits
let success = reticulateSplines(splines)

// ✅ CORRECT: Multi-line when wrapped
let success = reticulateSplines(
    spline: splines,
    adjustmentFactor: 1.3,
    translateConstant: 2,
    comment: "normalize the display")
```

## Closure Expressions

### Trailing Closure Syntax
**Use trailing closure syntax only for single closure at end**:

```swift
// ✅ CORRECT: Trailing closure usage
UIView.animate(withDuration: 1.0) {
    self.myView.alpha = 0
}

UIView.animate(withDuration: 1.0, animations: {
    self.myView.alpha = 0
}, completion: { finished in
    self.myView.removeFromSuperview()
})

// ❌ INCORRECT: Trailing closure with multiple closures
UIView.animate(withDuration: 1.0, animations: {
    self.myView.alpha = 0
}) { f in
    self.myView.removeFromSuperview()
}
```

### Single-Expression Closures
**Use implicit returns for single-expression closures**:

```swift
// ✅ CORRECT: Implicit return
attendeeList.sort { a, b in
    a > b
}
```

### Chained Methods
**Format chained methods for clarity**:

```swift
// ✅ CORRECT: Chained methods - compact when clear
let value = numbers.map { $0 * 2 }.filter { $0 % 3 == 0 }.index(of: 90)

// ✅ CORRECT: Chained methods - multi-line when complex
let value = numbers
    .map { $0 * 2 }
    .filter { $0 > 50 }
    .map { $0 + 10 }
```

## Types and Constants

### Native Types
**Always use Swift's native types** when available:

```swift
// ✅ CORRECT: Native Swift types
let width = 120.0                    // Double
let widthString = "\(width)"         // String

// ❌ INCORRECT: Objective-C types
let width: NSNumber = 120.0          // NSNumber
let widthString: NSString = width.stringValue  // NSString
```

### Constants vs Variables
**Use `let` by default, change to `var` only when compiler complains**:

```swift
// ✅ CORRECT: Type properties for constants
enum Math {
    static let e = 2.718281828459045235360287
    static let root2 = 1.41421356237309504880168872
}

let hypotenuse = side * Math.root2

// ❌ INCORRECT: Global constants
let e = 2.718281828459045235360287  // pollutes global namespace
let root2 = 1.41421356237309504880168872
```

### Type Inference
**Prefer compact code and let compiler infer types**:

```swift
// ✅ CORRECT: Type inference
let message = "Click the button"
let currentBounds = computeViewBounds()
var names = ["Mic", "Sam", "Christine"]
let maximumWidth: CGFloat = 106.5  // Specify when needed

// ❌ INCORRECT: Unnecessary type annotations
let message: String = "Click the button"
let currentBounds: CGRect = computeViewBounds()
```

### Empty Collections
**Use type annotation for empty arrays and dictionaries**:

```swift
// ✅ CORRECT: Type annotation for empty collections
var names: [String] = []
var lookup: [String: Int] = [:]

// ❌ INCORRECT: Constructor syntax
var names = [String]()
var lookup = [String: Int]()
```

### Syntactic Sugar
**Prefer shortcut type declarations**:

```swift
// ✅ CORRECT: Syntactic sugar
var deviceModels: [String]
var employees: [Int: String]
var faxNumber: Int?

// ❌ INCORRECT: Full generics syntax
var deviceModels: Array<String>
var employees: Dictionary<Int, String>
var faxNumber: Optional<Int>
```

## Optionals

### Optional Declarations
**Use `?` for optional types, `!` only when you know initialization timing**:

```swift
// ✅ CORRECT: Optional usage
var subview: UIView?
var volume: Double?

// Use ! only for outlets that initialize in viewDidLoad
@IBOutlet weak var tableView: UITableView!
```

### Optional Binding
**Shadow original names in optional binding**:

```swift
// ✅ CORRECT: Shadow original name
if let subview = subview, let volume = volume {
    // do something with unwrapped subview and volume
}

// ❌ INCORRECT: Different names for unwrapped values
if let unwrappedSubview = optionalSubview {
    if let realVolume = volume {
        // do something with unwrappedSubview and realVolume
    }
}
```

### Optional Chaining vs Binding
**Use optional chaining for single access, binding for multiple operations**:

```swift
// ✅ CORRECT: Optional chaining for single access
textContainer?.textLabel?.setNeedsDisplay()

// ✅ CORRECT: Optional binding for multiple operations
if let textContainer = textContainer {
    // do many things with textContainer
}
```

## Memory Management

### Reference Cycles
**Prevent reference cycles with `weak` and `unowned` references**:

```swift
// ✅ CORRECT: Weak self pattern
resource.request().onComplete { [weak self] response in
    guard let self = self else { return }
    let model = self.updateModel(response)
    self.updateUI(model)
}

// ❌ INCORRECT: Potential crash with unowned
resource.request().onComplete { [unowned self] response in
    let model = self.updateModel(response)  // Might crash
    self.updateUI(model)
}

// ❌ INCORRECT: Optional chaining can cause issues
resource.request().onComplete { [weak self] response in
    let model = self?.updateModel(response)  // Self might be nil here
    self?.updateUI(model)                    // And here, causing inconsistency
}
```

### Lazy Initialization
**Use lazy initialization for fine-grained control**:

```swift
// ✅ CORRECT: Lazy initialization
lazy var locationManager = makeLocationManager()

private func makeLocationManager() -> CLLocationManager {
    let manager = CLLocationManager()
    manager.desiredAccuracy = kCLLocationAccuracyBest
    manager.delegate = self
    manager.requestAlwaysAuthorization()
    return manager
}
```

## Access Control

### Access Control Order
**Access control comes first, except for `static` and attributes**:

```swift
// ✅ CORRECT: Access control ordering
private let message = "Great Scott!"

class TimeMachine {
    private dynamic lazy var fluxCapacitor = FluxCapacitor()
    @IBAction private func activate() { }
    static private let timeConstant = 88.0
}

// ❌ INCORRECT: Wrong ordering
fileprivate let message = "Great Scott!"

class TimeMachine {
    lazy dynamic private var fluxCapacitor = FluxCapacitor()
}
```

### Private vs Fileprivate
**Prefer `private` to `fileprivate`**; use `fileprivate` only when compiler requires it.

## Control Flow

### Loop Style
**Prefer `for-in` style over `while-condition-increment`**:

```swift
// ✅ CORRECT: for-in style
for _ in 0..<3 {
    print("Hello three times")
}

for (index, person) in attendeeList.enumerated() {
    print("\(person) is at position #\(index)")
}

// ❌ INCORRECT: while style
var i = 0
while i < 3 {
    print("Hello three times")
    i += 1
}
```

### Ternary Operator
**Use ternary operator only when it increases clarity**:

```swift
// ✅ CORRECT: Simple ternary usage
let value = 5
result = value != 0 ? x : y

let isHorizontal = true
result = isHorizontal ? x : y

// ❌ INCORRECT: Complex nested ternary
result = a > b ? x = c > d ? c : d : y
```

### Golden Path
**Use the "golden path" pattern - don't nest `if` statements**:

```swift
// ✅ CORRECT: Golden path with guard
func computeFFT(context: Context?, inputData: InputData?) throws -> Frequencies {
    guard let context = context else {
        throw FFTError.noContext
    }
    guard let inputData = inputData else {
        throw FFTError.noInputData
    }
    
    // use context and input to compute the frequencies
    return frequencies
}

// ❌ INCORRECT: Nested if statements
func computeFFT(context: Context?, inputData: InputData?) throws -> Frequencies {
    if let context = context {
        if let inputData = inputData {
            // use context and input to compute the frequencies
            return frequencies
        } else {
            throw FFTError.noInputData
        }
    } else {
        throw FFTError.noContext
    }
}
```

### Compound Guard Statements
**Use compound guard for multiple optionals**:

```swift
// ✅ CORRECT: Compound guard
guard 
    let number1 = number1,
    let number2 = number2,
    let number3 = number3 
else {
    fatalError("impossible")
}

// ❌ INCORRECT: Nested optional binding
if let number1 = number1 {
    if let number2 = number2 {
        if let number3 = number3 {
            // do something with numbers
        }
    }
}
```

## Class and Struct Definitions

### Example Well-Styled Class
```swift
final class Circle: Shape {
    var x: Int, y: Int
    var radius: Double
    var diameter: Double {
        get {
            radius * 2
        }
        set {
            radius = newValue / 2
        }
    }
    
    init(x: Int, y: Int, radius: Double) {
        self.x = x
        self.y = y
        self.radius = radius
    }
    
    convenience init(x: Int, y: Int, diameter: Double) {
        self.init(x: x, y: y, radius: diameter / 2)
    }
    
    override func area() -> Double {
        Double.pi * radius * radius
    }
}

extension Circle: CustomStringConvertible {
    var description: String {
        "center = \(centerString) area = \(area())"
    }
    
    private var centerString: String {
        "(\(x),\(y))"
    }
}
```

### Use of Self
**Avoid using `self` unless required by compiler**:

```swift
// ✅ CORRECT: Self only when required
class PhotoViewController: UIViewController {
    var image: UIImage
    
    init(image: UIImage) {
        self.image = image  // Required to disambiguate
        super.init(nibName: nil, bundle: nil)
    }
    
    func setupImageView() {
        imageView.image = image  // self not needed
    }
}
```

### Computed Properties
**Omit get clause for read-only computed properties**:

```swift
// ✅ CORRECT: Implicit get for read-only
var diameter: Double {
    radius * 2
}

// ❌ INCORRECT: Unnecessary get clause
var diameter: Double {
    get {
        return radius * 2
    }
}
```

### Final
**Use `final` when inheritance is not intended**:

```swift
// ✅ CORRECT: Final for utility classes
final class Box<T> {
    let value: T
    init(_ value: T) {
        self.value = value
    }
}
```

## DuckDuckGo-Specific Patterns

### Design System Integration (MANDATORY)

**ALWAYS use DesignResourcesKit** for colors, typography, and icons:

```swift
// ✅ REQUIRED: Use DesignResourcesKit colors
label.textColor = UIColor(designSystemColor: .textPrimary)
view.backgroundColor = UIColor(designSystemColor: .background)

// ✅ REQUIRED: Use DesignResourcesKit typography
titleLabel.font = UIFont.daxTitle1()
bodyLabel.font = UIFont.daxBody()

// ✅ REQUIRED: Use DesignResourcesKit icons
let image = DesignSystemImages.Color.Size24.bookmark

// ❌ FORBIDDEN: Hardcoded colors/fonts/icons
label.textColor = UIColor.black
titleLabel.font = UIFont.systemFont(ofSize: 24)
let image = UIImage(systemName: "bookmark")
```

### Dependency Injection Pattern
**Use AppDependencyProvider for dependency injection**:

```swift
// ✅ CORRECT: Dependency injection pattern
final class FeatureViewModel: ObservableObject {
    private let service: FeatureServiceProtocol
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.service = dependencies.featureService
    }
}
```

### Async/Await Patterns
```swift
// ✅ CORRECT: Modern async/await with proper error handling
@MainActor
class FeatureViewModel: ObservableObject {
    @Published var state: FeatureState = .idle
    
    func loadData() async {
        state = .loading
        
        do {
            let data = try await service.fetchData()
            state = .loaded(data)
        } catch {
            state = .error(error)
        }
    }
}
```

### Property Wrappers
```swift
// ✅ CORRECT: Use custom property wrappers
final class SettingsManager {
    @UserDefaultsWrapper(key: .showBookmarksBar, defaultValue: true)
    var showBookmarksBar: Bool
    
    @UserDefaultsWrapper(key: .homePageURL, defaultValue: "https://duckduckgo.com")
    var homePageURL: String
}
```

## Comments and Documentation

### When to Comment
**Use comments to explain WHY, not WHAT**:

```swift
// ✅ CORRECT: Explains why
// We delay the animation to avoid conflicting with the previous transition
DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
    self.animateTransition()
}

// ❌ INCORRECT: Explains what (obvious from code)
// Set the background color to red
view.backgroundColor = .red
```

### Comment Style
**Prefer double/triple-slash over C-style comments**:

```swift
// ✅ CORRECT: Swift-style comments
// This is a comment
/// This is a documentation comment

// ❌ INCORRECT: C-style comments
/* This is a comment */
```

## String Literals

### Multi-line Strings
**Use multi-line string syntax for long strings**:

```swift
// ✅ CORRECT: Multi-line string formatting
let message = """
    You cannot charge the flux \
    capacitor with a 9V battery.
    You must use a super-charger \
    which costs 10 credits. You currently \
    have \(credits) credits available.
    """

// ❌ INCORRECT: Concatenation or inline text
let message = """You cannot charge the flux \
    capacitor with a 9V battery.
    You must use a super-charger \
    which costs 10 credits. You currently \
    have \(credits) credits available.
    """
```

## Prohibited Patterns

### No Emoji
**Do not use emoji in code** - it creates unnecessary friction:

```swift
// ❌ FORBIDDEN: Emoji in code
let isHappy = true 😀
func celebrate() 🎉 { }

// ✅ CORRECT: Clear, text-based names
let isHappy = true
func celebrate() { }
```

### No Color/Image Literals
**Do not use `#colorLiteral` or `#imageLiteral`** - they're hard to read and maintain:

```swift
// ❌ FORBIDDEN: Literals
let color = #colorLiteral(red: 1, green: 0, blue: 0, alpha: 1)
let image = #imageLiteral(resourceName: "icon")

// ✅ CORRECT: Explicit constructors (but prefer DesignResourcesKit)
let color = UIColor(red: 1, green: 0, blue: 0, alpha: 1)
let image = UIImage(named: "icon")

// ✅ BEST: DesignResourcesKit
let color = UIColor(designSystemColor: .accent)
let image = DesignSystemImages.Color.Size24.bookmark
```

### No Parentheses Around Conditionals
**Don't use unnecessary parentheses**:

```swift
// ✅ CORRECT: No parentheses needed
if name == "Hello" {
    print("World")
}

// ❌ INCORRECT: Unnecessary parentheses
if (name == "Hello") {
    print("World")
}
```

### No Semicolons
**Swift doesn't require semicolons** - don't use them:

```swift
// ✅ CORRECT: No semicolons
let swift = "not a scripting language"

// ❌ INCORRECT: Unnecessary semicolons
let swift = "not a scripting language";
```

## Error Handling and Assertions

### Fatal Errors
**Use `fatalError()` when app reaches unrecoverable state**:

```swift
// ✅ CORRECT: Fatal error for impossible states
guard let viewController = storyboard.instantiateViewController(withIdentifier: "Main") as? MainViewController else {
    fatalError("Failed to instantiate MainViewController from storyboard")
}
```

### Assertions
**Use `assert()` and `assertionFailure()` for recoverable but unexpected states**:

```swift
// ✅ CORRECT: Assert for development debugging
func processItems(_ items: [Item]) {
    assert(!items.isEmpty, "Items array should not be empty")
    
    // Handle empty array gracefully in release builds
    guard !items.isEmpty else { return }
    
    // Process items...
}
```

## Logging

**Use unified logging system** for all logging:

```swift
import os

// ✅ CORRECT: Unified logging
private let logger = Logger(subsystem: "com.duckduckgo.browser", category: "FeatureManager")

func performAction() {
    logger.debug("Starting action with parameter: \(parameter, privacy: .public)")
    
    // Perform action...
    
    if success {
        logger.info("Action completed successfully")
    } else {
        logger.error("Action failed: \(error.localizedDescription, privacy: .public)")
    }
}
```

**See [Logging Guidelines](logging-guidelines.md) for comprehensive logging patterns.**

## Unit Test Naming

**Use "when/then" convention for test names**:

```swift
// ✅ CORRECT: When/then test naming
func testWhenUrlIsNotATrackerThenMatchesIsFalse() { }
func testWhenUserTapsBookmarkButtonThenBookmarkIsAdded() { }
func testWhenNetworkFailsThenErrorIsDisplayed() { }

// ❌ INCORRECT: Unclear test names
func testBookmarks() { }
func testNetworking() { }
```

## Functions vs Methods

**Prefer methods over free functions** for discoverability:

```swift
// ✅ CORRECT: Methods are easily discoverable
let sorted = items.mergeSorted()
rocket.launch()

// ❌ INCORRECT: Free functions are hard to discover
let sorted = mergeSort(items)
launch(&rocket)

// ✅ ACCEPTABLE: Free functions that feel natural
let tuples = zip(a, b)
let value = max(x, y, z)
```

---

**Remember**: This style guide ensures consistency across the DuckDuckGo browser codebase. When in doubt, prioritize clarity and follow the patterns established in existing code.