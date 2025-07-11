---
alwaysApply: false
title: "Architecture Patterns & Guidelines"
description: "Architecture patterns and best practices for DuckDuckGo browser including MVVM, dependency injection, and code organization"
keywords: ["architecture", "MVVM", "dependency injection", "coordinator pattern", "ObservableObject", "privacy-first design"]
---

# DuckDuckGo Browser Architecture Guidelines

## Overall Architecture
- This is a multi-platform monorepo supporting iOS and macOS browsers
- Shared code lives in `SharedPackages/` directory
- Platform-specific code in `iOS/` and `macOS/` directories
- Follow modular architecture with clear separation of concerns

## Architecture Patterns

### MVVM for SwiftUI Views
- Use MVVM pattern for all SwiftUI views
- ViewModels should conform to `ObservableObject`
- Use `@Published` properties for reactive updates
- Keep ViewModels testable and free from UI concerns

Example:
```swift
class FeatureViewModel: ObservableObject {
    @Published var state: FeatureState = .idle
    private let service: FeatureServiceProtocol
    
    init(service: FeatureServiceProtocol) {
        self.service = service
    }
}
```

### Coordinator Pattern
- Use coordinators for navigation and flow control
- Main app flow managed by `MainCoordinator`
- Create feature-specific coordinators as needed
- Coordinators handle navigation logic, not views

### Dependency Injection
- Use constructor injection for dependencies
- Define protocols for all dependencies
- Use `AppDependencyProvider` for shared dependencies
- Keep dependencies explicit and testable

## Code Organization

### Feature-Based Structure
- Organize code by features, not layers
- Each feature should have its own folder containing:
  - Views (SwiftUI/UIKit)
  - ViewModels
  - Services
  - Models
  - Tests

### File Naming Conventions
- ViewModels: `FeatureNameViewModel.swift`
- Views: `FeatureNameView.swift` (SwiftUI) or `FeatureNameViewController.swift` (UIKit)
- Services: `FeatureNameService.swift`
- Protocols: `FeatureNameProtocol.swift` or embed in main file

### Extension Organization
- Split large classes into focused extensions
- Name extensions descriptively: `MainViewController+Email.swift`
- Group related functionality in extensions

## Privacy-First Design
- All features must consider privacy implications
- Use secure storage for sensitive data
- Implement proper data clearing mechanisms
- Follow fireproofing patterns where applicable

## Testing Requirements
- Write unit tests for all ViewModels and Services
- Test files should mirror source structure
- Use mock objects for dependencies
- Test async code with Combine publishers