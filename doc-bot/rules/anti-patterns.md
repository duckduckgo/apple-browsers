---
alwaysApply: true
title: "Anti-patterns and Common Mistakes"
description: "Anti-patterns to avoid and common mistakes to prevent in DuckDuckGo browser development including singleton misuse, memory leaks, and performance issues"
keywords: ["anti-patterns", "common mistakes", "singletons", "memory leaks", "async/await", "error handling", "performance", "testing"]
---

# Anti-patterns and Common Mistakes to Avoid

## Singleton Anti-patterns

**❌ NEVER use singletons** - they create global state, make testing difficult, and violate dependency injection principles.

**✅ ALWAYS use dependency injection** through AppDependencyProvider.

📖 **[See singleton examples →](anti-patterns.examples.md#singleton-anti-patterns-examples)**

## Memory Management Anti-patterns

### Retain Cycles (Critical)
**❌ Common causes:**
- Closures capturing `self` strongly
- Delegate properties not marked `weak`
- Timer callbacks retaining objects
- Combine subscriptions without proper cleanup

**✅ Solutions:**
- Use `[weak self]` in closures
- Mark delegates as `weak`
- Invalidate timers in `deinit`
- Store cancellables properly

📖 **[See memory leak examples →](anti-patterns.examples.md#memory-leak-examples)**

### Strong Reference Cycles
**❌ NEVER create circular references** between objects.

**✅ ALWAYS use `weak` or `unowned` references** to break cycles.

## Async/Await Anti-patterns

### Blocking Operations
**❌ NEVER block threads** with semaphores or synchronous waits in async contexts.

**✅ ALWAYS use proper async/await** patterns for asynchronous operations.

### Mixing Paradigms
**❌ AVOID mixing** completion handlers with async/await unnecessarily.

**✅ PREFER native async/await** over wrapped completion handlers.

📖 **[See async/await anti-patterns →](anti-patterns.examples.md#asyncawait-anti-patterns)**

## Force Unwrapping Anti-patterns

**❌ NEVER force unwrap** without absolute certainty the value exists.

**✅ ALWAYS use safe unwrapping:**
- `guard let` for early returns
- `if let` for conditional execution  
- Nil coalescing (`??`) for defaults

📖 **[See force unwrapping examples →](anti-patterns.examples.md#force-unwrapping-anti-patterns)**

## Threading Anti-patterns

### UI Updates Off Main Thread
**❌ NEVER update UI** from background threads - causes crashes.

**✅ ALWAYS update UI on main thread** using:
- `DispatchQueue.main.async`
- `@MainActor` functions
- `MainActor.run`

### Race Conditions
**❌ AVOID unsynchronized** access to shared mutable state.

**✅ USE proper synchronization:**
- Serial queues for shared resources
- Actors for Swift concurrency
- Locks when necessary

📖 **[See threading anti-patterns →](anti-patterns.examples.md#threading-anti-patterns)**

## Error Handling Anti-patterns

### Silent Failures
**❌ NEVER ignore errors** silently - leads to data loss and bugs.

**✅ ALWAYS handle errors:**
- Log errors appropriately
- Show user-appropriate messages
- Implement recovery strategies

### Generic Error Messages  
**❌ AVOID vague errors** like "Error occurred".

**✅ PROVIDE specific, actionable** error messages.

📖 **[See error handling examples →](anti-patterns.examples.md#error-handling-anti-patterns)**

## Testing Anti-patterns

### Testing Implementation Details
**❌ DON'T test private methods** or internal implementation.

**✅ TEST public behavior** and observable outcomes.

### Flaky Tests
**❌ AVOID time-dependent** or order-dependent tests.

**✅ USE deterministic** test patterns with proper expectations.

### Real Network/Database
**❌ NEVER use real services** in unit tests.

**✅ ALWAYS use mocks** and dependency injection.

📖 **[See testing anti-patterns →](anti-patterns.examples.md#testing-anti-patterns)**

## Performance Anti-patterns

### Main Thread Blocking
**❌ NEVER perform expensive operations** on the main thread.

**✅ USE background queues** for heavy computation.

### Inefficient Object Creation
**❌ AVOID creating expensive objects** repeatedly in loops.

**✅ REUSE expensive objects** like formatters and regex patterns.

### Inefficient Collections
**❌ AVOID multiple passes** through collections unnecessarily.

**✅ USE lazy evaluation** and efficient algorithms.

📖 **[See performance anti-patterns →](anti-patterns.examples.md#performance-anti-patterns)**

## SwiftUI Anti-patterns

### Heavy Body Computation
**❌ NEVER perform expensive operations** in view body.

**✅ USE computed properties** or state management.

### Wrong Property Wrappers
**❌ DON'T misuse** `@State`, `@StateObject`, `@ObservedObject`.

**✅ UNDERSTAND the lifecycle** of each property wrapper.

📖 **[See SwiftUI anti-patterns →](anti-patterns.examples.md#swiftui-anti-patterns)**

## Git & Testing Anti-patterns

### Auto-Committing/Pushing
**❌ NEVER automatically commit** or push without explicit permission.

**✅ ALWAYS ask user first** before git operations.

### Auto-Running Tests  
**❌ NEVER run tests automatically** without user request.

**✅ ASK permission first** before executing test suites.

## Logging Anti-patterns

### Print Statements
**❌ NEVER use `print()`** for logging in production code.

**✅ ALWAYS use Logger extensions:**
- `Logger.general` for app functionality
- `Logger.network` for network operations  
- `Logger.ui` for UI updates

## Design System Anti-patterns

### Hardcoded Values
**❌ NEVER hardcode colors, fonts, or spacing.**

**✅ ALWAYS use DesignResourcesKit** tokens and design system.

### Manual Dark Mode
**❌ NEVER manually check** `colorScheme` or `userInterfaceStyle`.

**✅ USE semantic colors** that adapt automatically.

## Code Organization Anti-patterns

### Massive View Controllers
**❌ AVOID putting all logic** in view controllers.

**✅ USE MVVM pattern** with proper separation of concerns.

### Deep Nesting
**❌ AVOID deeply nested** conditional statements.

**✅ USE guard statements** for early returns (Golden Path pattern).

### Magic Numbers/Strings
**❌ NEVER use unexplained** magic numbers or string literals.

**✅ CREATE named constants** with clear purposes.

## Quick Anti-pattern Checklist

Before committing code, verify:
- [ ] No singletons used (use dependency injection)
- [ ] No retain cycles (use `[weak self]`)  
- [ ] No force unwrapping without safety
- [ ] No UI updates off main thread
- [ ] No `print()` statements (use Logger)
- [ ] No hardcoded colors/fonts (use DesignResourcesKit)
- [ ] No silent error handling
- [ ] No expensive operations in view bodies
- [ ] No auto git/test operations

---

📖 **For detailed examples of all these anti-patterns and their solutions, see [anti-patterns.examples.md](anti-patterns.examples.md)**