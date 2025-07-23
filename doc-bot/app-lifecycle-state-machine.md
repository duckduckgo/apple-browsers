---
alwaysApply: false
title: "App Lifecycle State Machine Architecture"
description: "App lifecycle state machine architecture for DuckDuckGo browser including Launching, Foreground, and Background states with transition methods and code placement patterns"
keywords: ["app lifecycle", "state machine", "Launching", "Foreground", "Background", "AppDelegate", "Services", "MainCoordinator", "AppConfiguration", "iOS"]
---

# App Lifecycle State Machine Architecture

## Overview

The DuckDuckGo browser has moved away from traditional AppDelegate-based lifecycle handling to a **state machine architecture**. While AppDelegate still exists, it has been significantly thinned out and now delegates responsibility to a structured state machine.

This approach ensures that lifecycle handling is **predictable, organized, and easy to maintain**.

## Architecture Components

### Three Core States

The architecture revolves around a state machine with three major states:

#### 1. **Launching** (Transient State)
- **Associated with**: `application(_:didFinishLaunchingWithOptions:)`
- **File**: `Launching.swift`
- **Purpose**: App's initial setup and dependency configuration
- **Responsibilities**:
  - Initialize all services and objects
  - Configure dependencies
  - Prepare UI components
  - Create `MainViewController` and set as `rootViewController`

#### 2. **Foreground** (Permanent State)
- **Associated with**: `applicationDidBecomeActive(_:)`
- **File**: `Foreground.swift`
- **Purpose**: App is fully interactive and user can engage with UI
- **Responsibilities**:
  - Resume suspended work
  - Handle user interactions
  - Manage active UI state

#### 3. **Background** (Permanent State)
- **Associated with**: `applicationDidEnterBackground(_:)`
- **File**: `Background.swift`
- **Purpose**: App is not active and UI is not visible
- **Responsibilities**:
  - Suspend ongoing work that doesn't need background execution
  - Prepare for potential termination
  - Handle background tasks

## State Machine Methods

### Core Transition Methods

All states implement specific methods for handling transitions:

#### `onTransition()`
- **When**: Called whenever the app enters that state from another state
- **Purpose**: Setup or cleanup during state transitions
- **Available in**: Foreground, Background

#### `willLeave()`
- **When**: Called before transitioning away from current state
- **Purpose**: Prepare for potential state change
- **Note**: Transition may be cancelled, in which case `didReturn()` is called
- **Available in**: Foreground, Background

#### `didReturn()`
- **When**: Called after successful transition to destination state OR when transition is cancelled
- **Purpose**: Finalize state entry or handle cancelled transition
- **Available in**: Foreground, Background

## Common Lifecycle Scenarios

### Cold App Start

```swift
// Flow: Launching → Foreground
1. Launching.init()                    // Initial setup
2. Foreground.onTransition()           // Enter foreground
3. Foreground.didReturn()              // Finalize foreground entry
```

### App Backgrounding

```swift
// Flow: Foreground → Background
1. Foreground.willLeave()              // Prepare to leave foreground
2. Background.onTransition()           // Enter background
3. Background.didReturn()              // Finalize background entry
```

### App Foregrounding

```swift
// Flow: Background → Foreground
1. Background.willLeave()              // Prepare to leave background
2. Foreground.onTransition()           // Enter foreground
3. Foreground.didReturn()              // Finalize foreground entry
```

### Interrupted Foreground (Alert/App Switcher)

```swift
// User receives alert but dismisses it
1. Foreground.willLeave()              // Attempt to leave
2. Foreground.didReturn()              // Cancelled - stay in foreground

// User opens App Switcher
1. Foreground.willLeave()              // Attempt to leave
// Two possible outcomes:
// A. User returns directly:
2. Foreground.didReturn()              // Return to foreground
// B. User switches to another app:
2. Background.onTransition()           // Actually transition to background
3. Background.didReturn()              // Finalize background entry
```

## Special iOS 18+ Scenarios

### Face ID Authentication on Cold Start

#### Successful Authentication
```swift
1. Launching.init()
2. Foreground.onTransition()
3. Foreground.didReturn()
```

#### Failed Authentication
```swift
1. Launching.init()
2. Background.onTransition()           // Goes to background on auth failure
3. Background.didReturn()
```

### DuckDuckGo Face ID Lock

#### Cold Start with DDG Face ID
```swift
1. Launching.init()
2. Foreground.onTransition()
3. Foreground.didReturn()
4. Foreground.willLeave()              // DDG auth triggers
5. Foreground.didReturn()              // User passes auth
```

### Critical Setup Failure

```swift
1. Launching.init() throws             // Setup fails (e.g., disk space)
2. Terminating.init()                  // App terminates
```

## Code Placement Patterns

### ⚙️ One-time Setup → `AppConfiguration`

**Location**: Inside `Launching.swift`

For setup that happens once and doesn't need ongoing lifecycle management:

```swift
class AppConfiguration {
    func start() {
        // Basic setup that doesn't require dependencies
        setupGlobalUserAgent()
        configureLogging()
    }
    
    func finalize() {
        // Setup that requires access to services or MainCoordinator
        configureWithDependencies()
    }
}
```

**Use Cases**:
- Setting global user agents
- Initial configuration
- One-time system setup

### 🔄 Lifecycle-Reactive Logic → `Service`

For code that needs to react to app lifecycle events:

```swift
class MyLifecycleService {
    func resumeWork() {
        // Called from Foreground.onTransition() or didReturn()
    }
    
    func suspendWork() {
        // Called from Background.onTransition() or Foreground.willLeave()
    }
}

// In Launching.swift
let myService = MyLifecycleService()
services.myService = myService  // Store in services for lifecycle access
```

**Service Patterns**:
- **Initialize**: In `Launching.init()`
- **Resume work**: In `Foreground` methods
- **Suspend work**: In `Background` methods
- **Assign to services**: Make available to other states

**Use Cases**:
- Network managers
- Timer services
- Data synchronization
- Background task management

### 🖼️ UI-Related Logic → `MainCoordinator`

**Location**: MainCoordinator initialization and management

For logic that involves creating or modifying the main view:

```swift
class MainCoordinator {
    func setupMainViewController() {
        // UI setup and configuration
    }
    
    func handleDeepLink(_ url: URL) {
        // Navigation and UI state changes
    }
}
```

**Use Cases**:
- View controller creation
- Navigation management
- UI state configuration
- Deep link handling

## Practical Examples

### 📊 Example 1: Pixel Analytics Service

**Requirement**: Send "Hello" pixel on foreground, "Goodbye" pixel on background

```swift
// 1. Create Service
class PixelService {
    func sendHelloPixel() {
        // Send hello pixel
    }
    
    func sendGoodbyePixel() {
        // Send goodbye pixel
    }
}

// 2. Initialize in Launching
class Launching {
    func init() {
        let pixelService = PixelService()
        services.pixelService = pixelService
    }
}

// 3. Use in Foreground
class Foreground {
    func onTransition() {
        services.pixelService.sendHelloPixel()
    }
}

// 4. Use in Background
class Background {
    func onTransition() {
        services.pixelService.sendGoodbyePixel()
    }
}
```

### ⏱️ Example 2: Session Timer Service

**Requirement**: Track session time, pause on interruptions, resume on return

```swift
class SessionTimeService {
    private var timer: Timer?
    
    func startTimer() {
        // Start session timing
    }
    
    func pauseTimer() {
        // Pause session timing
    }
    
    func resumeTimer() {
        // Resume session timing
    }
}

// Launching
class Launching {
    func init() {
        let sessionService = SessionTimeService()
        services.sessionService = sessionService
    }
}

// Foreground - Handle interruptions
class Foreground {
    func didReturn() {
        // Start/resume timer when entering or returning to foreground
        services.sessionService.resumeTimer()
    }
    
    func willLeave() {
        // Pause timer when potentially leaving foreground
        services.sessionService.pauseTimer()
    }
}

// Background
class Background {
    func onTransition() {
        // Timer already paused by Foreground.willLeave()
    }
}
```

### 🧹 Example 3: Auto-Clear Data Service

**Requirement**: Clear data immediately on app wake to avoid UI glitches

```swift
class AutoClearService {
    func startDataClearing() async {
        // Clear user data
    }
    
    func waitForCompletion() async {
        // Wait for clearing to complete
    }
}

// Launching - Start clearing immediately
class Launching {
    func init() {
        let autoClearService = AutoClearService()
        services.autoClearService = autoClearService
        
        // Start clearing immediately on cold start
        Task {
            await autoClearService.startDataClearing()
        }
    }
}

// Foreground - Wait for completion before proceeding
class Foreground {
    func onTransition() async {
        // Wait for data clearing before loading URLs or handling deep links
        await services.autoClearService.waitForCompletion()
        handlePendingDeepLinks()
    }
}

// Background - Start clearing before transitioning to foreground
class Background {
    func willLeave() {
        // Start clearing early to be ready for foreground transition
        Task {
            await services.autoClearService.startDataClearing()
        }
    }
    
    func didReturn() {
        // If transition was cancelled, clearing is still beneficial
        // No action needed as clearing is irreversible
    }
}
```

## State Context and Services

### Service Management

```swift
// Services are stored in StateContext for cross-state access
class StateContext {
    var pixelService: PixelService!
    var sessionService: SessionTimeService!
    var autoClearService: AutoClearService!
    // ... other services
}

// Access pattern in states
class Foreground {
    func onTransition() {
        services.pixelService.sendHelloPixel()
        services.sessionService.resumeTimer()
    }
}
```

### Service Lifecycle Best Practices

```swift
// ✅ CORRECT: Service with proper lifecycle management
class MyService {
    private var isActive = false
    
    func activate() {
        guard !isActive else { return }
        isActive = true
        startWork()
    }
    
    func deactivate() {
        guard isActive else { return }
        isActive = false
        stopWork()
    }
    
    private func startWork() {
        // Begin service operations
    }
    
    private func stopWork() {
        // Clean up service operations
    }
}

// Usage in states
class Foreground {
    func didReturn() {
        services.myService.activate()
    }
    
    func willLeave() {
        services.myService.deactivate()
    }
}
```

## Decision Tree: Where Should My Code Go?

```
📋 What type of code are you adding?

├── 🔧 One-time setup that doesn't need lifecycle management?
│   └── ➡️ AppConfiguration (in Launching.swift)
│       ├── start() for basic setup
│       └── finalize() for dependency-requiring setup
│
├── 🔄 Logic that reacts to app state changes?
│   └── ➡️ Create a Service
│       ├── Initialize in Launching.init()
│       ├── Store in services for cross-state access
│       ├── Resume work in Foreground methods
│       └── Suspend work in Background methods
│
├── 🖼️ UI setup or view management?
│   └── ➡️ MainCoordinator
│       ├── View controller creation
│       ├── Navigation setup
│       └── Deep link handling
│
└── 🤔 Something else?
    └── ➡️ Let's discuss through tech design
```

## Best Practices

### ✅ DO

```swift
// Store services for cross-state access
services.myService = MyService()

// Use proper lifecycle methods
func didReturn() {
    resumeWork()
}

func willLeave() {
    pauseWork()
}

// Handle state transitions gracefully
func onTransition() {
    await waitForCriticalWork()
    proceedWithStateLogic()
}
```

### ❌ DON'T

```swift
// Don't bypass the state machine
AppDelegate.shared.doSomething() // ❌

// Don't create services without storing them
let service = MyService() // ❌ Will be deallocated

// Don't ignore willLeave/didReturn patterns
func onTransition() {
    // Only using onTransition misses important interrupt scenarios
}

// Don't block UI with long operations
func onTransition() {
    performLongRunningTask() // ❌ Should be async
}
```

### 🔒 Memory Management

```swift
// Services are retained by StateContext
class StateContext {
    var services: [String: AnyObject] = [:]
    
    func addService<T: AnyObject>(_ service: T, for key: String) {
        services[key] = service
    }
}

// Clean up resources in state transitions
class MyService {
    func cleanup() {
        // Release resources, cancel operations
    }
}
```

## Debugging and Monitoring

### State Transition Logging

```swift
class Foreground {
    func onTransition() {
        Logger.lifecycle.info("Entering Foreground state")
        // State logic
    }
    
    func willLeave() {
        Logger.lifecycle.info("Will leave Foreground state")
        // Cleanup logic
    }
    
    func didReturn() {
        Logger.lifecycle.info("Returned to Foreground state")
        // Resume logic
    }
}
```

### Performance Monitoring

```swift
class Launching {
    func init() {
        let startTime = CFAbsoluteTimeGetCurrent()
        
        // Initialization logic
        
        let duration = CFAbsoluteTimeGetCurrent() - startTime
        Logger.performance.info("Launching completed in \(duration)s")
    }
}
```

---

This state machine architecture provides a robust, maintainable approach to app lifecycle management that scales with the complexity of the DuckDuckGo browser while maintaining clear separation of concerns. 