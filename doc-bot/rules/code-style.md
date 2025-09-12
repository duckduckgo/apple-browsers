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
The **unnamed first parameter should be the delegate source**.

📖 **[See detailed examples →](code-style.examples.md#delegate-method-naming)**

### Use Type Inferred Context
Use compiler inferred context to write shorter, clear code.

📖 **[See detailed examples →](code-style.examples.md#type-inferred-context-examples)**

### Generics
When using generics, use descriptive names when the purpose isn't clear from context.

📖 **[See detailed examples →](code-style.examples.md#generics-examples)**

### Language
Use US English spelling to match Swift API guidelines.

## Code Organization

### File Structure
**Order within files**:
1. Imports
2. Protocols 
3. Class/Struct definition
4. Properties (IBOutlets → stored → computed)
5. Lifecycle methods
6. Public methods
7. Private methods 
8. Extensions

📖 **[See detailed examples →](code-style.examples.md#file-organization-example)**

### Protocol Conformance
When adding protocol conformance to a model, prefer adding a separate extension for the protocol methods.

### Minimal Imports
Import only the modules a source file requires. For example, don't import `UIKit` when importing `Foundation` will suffice.

### Remove Unused Code
Unused (dead) code should be removed. Don't comment out code - use version control.

## Formatting and Style

### Line Breaks and Length
- **Maximum line length**: 150 characters
- **Break after operators**: Place operators at the beginning of continuation lines

### Spacing
- **Method braces**: Opening brace on same line as definition
- **Control flow braces**: Opening brace on same line as statement
- **Indent with 4 spaces** (not tabs)

### Colons
Colons always have no space on the left and one space on the right (except in ternary operator).

### Function Parameters
When parameter lists are too long, break after each parameter with proper indentation.

📖 **[See detailed examples →](code-style.examples.md#function-declaration-examples)**

## Function Declarations

### Short Functions
Keep functions short and focused on a single task.

### Long Function Signatures
Break long signatures across multiple lines with proper indentation.

### Return Types
Be explicit about return types for public functions.

## Function Calls

Use trailing closure syntax when appropriate and the closure is the last parameter.

📖 **[See detailed examples →](code-style.examples.md#closure-expression-examples)**

## Types and Constants

### Native Types
Always use Swift's native types when available (prefer `String` over `NSString`).

### Constants vs Variables
Prefer `let` over `var` whenever possible.

### Type Inference
Rely on Swift's type inference when the type is obvious from context.

### Empty Collections
Use empty collection literals over explicit constructors.

### Syntactic Sugar
Use syntactic sugar for Array, Dictionary, and Optional types.

## Optionals

### Optional Declarations
Prefer optional binding over comparing to `nil`.

### Optional Binding
Use `if let` and `guard let` for optional binding.

### Optional Chaining vs Binding
Use optional chaining for simple property access, optional binding for complex operations.

📖 **[See detailed examples →](code-style.examples.md#control-flow-examples)**

## Memory Management

### Reference Cycles
Use `[weak self]` and `[unowned self]` to prevent retain cycles in closures.

### Lazy Initialization
Use lazy initialization for expensive properties.

📖 **[See detailed examples →](code-style.examples.md#memory-management-examples)**

## Access Control

### Access Control Order
Order access modifiers consistently: `private` → `fileprivate` → `internal` → `public` → `open`.

### Private vs Fileprivate
Prefer `private` over `fileprivate` when possible.

## Control Flow

### Loop Style
Prefer `for-in` loops over `while` loops.

### Ternary Operator
Use ternary operator for simple value assignments only.

### Golden Path
Use guard statements to exit early and avoid nesting.

### Compound Guard Statements
Combine multiple conditions in guard statements when appropriate.

## Class and Struct Definitions

📖 **[See complete well-organized class example →](code-style.examples.md#class-definition-examples)**

### Use of Self
Avoid using `self` unless required by the compiler.

### Computed Properties
Use computed properties when appropriate instead of methods.

### Final
Mark classes as `final` when they're not designed for inheritance.

## DuckDuckGo-Specific Patterns

### Design System Integration (MANDATORY)
**ALWAYS use DesignResourcesKit** - never hardcode colors, fonts, or icons.

📖 **[See design system examples →](code-style.examples.md#design-system-integration-examples)**

### Dependency Injection Pattern
**ALWAYS use dependency injection** - avoid singletons.

📖 **[See dependency injection examples →](code-style.examples.md#dependency-injection-examples)**

### Async/Await Patterns
Use modern Swift concurrency patterns appropriately.

📖 **[See async/await examples →](code-style.examples.md#asyncawait-examples)**

### Property Wrappers
Use property wrappers for common patterns like UserDefaults.

📖 **[See property wrapper examples →](code-style.examples.md#property-wrapper-examples)**

## Comments and Documentation

### When to Comment
Write comments for complex algorithms, business logic, and non-obvious decisions.

### Comment Style
Use `// MARK:` for organizing code sections.

## String Literals

### Multi-line Strings
Use multi-line string literals for long strings.

## Prohibited Patterns

### No Emoji
Never use emoji in code or comments.

### No Color/Image Literals
Never use Xcode color or image literals - use DesignResourcesKit.

### No Parentheses Around Conditionals
Don't use unnecessary parentheses around conditionals.

### No Semicolons
Don't use semicolons except when required for multiple statements on one line.

## Error Handling and Assertions

### Fatal Errors
Use `fatalError()` for truly unrecoverable conditions only.

### Assertions
Use assertions for debugging and development validation.

## Logging

**NEVER use `print()` in production code.** Always use appropriate Logger extensions.

📖 **[See logging examples →](code-style.examples.md#logging-examples)**

## Unit Test Naming

Test method names should describe what they test and the expected outcome.

## Functions vs Methods

Prefer methods over free functions when operating on instances.

---

📖 **For comprehensive code examples demonstrating all these patterns, see [code-style.examples.md](code-style.examples.md)**