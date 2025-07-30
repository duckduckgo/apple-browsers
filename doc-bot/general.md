---
alwaysApply: true
title: "DuckDuckGo Browser Development Overview"
description: "General project overview and development guidelines for DuckDuckGo browser development across iOS and macOS platforms"
keywords: ["Swift", "iOS", "macOS", "MVVM", "SwiftUI", "privacy", "architecture", "dependency injection", "design system"]
---

# DuckDuckGo Browser Development Rules Overview

## Project Context
This is the DuckDuckGo browser for iOS and macOS, built with privacy-first principles, modern Swift patterns, and cross-platform architecture.

**Key Directories:**
- `iOS/` - iOS browser app (UIKit + SwiftUI hybrid)
- `macOS/` - macOS browser app (AppKit + SwiftUI hybrid) 
- `SharedPackages/` - Cross-platform Swift packages
- `doc-bot/` - Development rules and guidelines

## Architecture Summary
- **Pattern**: MVVM + Coordinators + Dependency Injection
- **UI**: SwiftUI preferred, UIKit/AppKit for legacy
- **Storage**: Core Data + GRDB + Keychain for sensitive data
- **Design**: DesignResourcesKit for colors/icons (MANDATORY)
- **Testing**: >80% coverage required

## Rule Files Reference

### Core Development Rules (Apply to All Code)
- `anti-patterns.md` - What NOT to do (memory leaks, force unwrapping, etc.)
- `code-style.md` - Swift style guide and conventions
- `privacy-security.md` - Privacy requirements (ALWAYS applies)

### Architecture & Patterns
- `architecture.md` - MVVM, DI, and structural patterns
- `property-wrappers.md` - @UserDefaultsWrapper and custom property wrappers
- `feature-flags.md` - Type-safe feature flags and A/B testing

### UI Development
- `swiftui-style.md` - SwiftUI + DesignResourcesKit integration
- `swiftui-advanced.md` - Advanced SwiftUI patterns and techniques
- `webkit-browser.md` - WebView and browser-specific patterns

### Platform-Specific Rules
- `ios-architecture.md` - iOS AppDependencyProvider, MainCoordinator, UIKit patterns
- `macos-window-management.md` - macOS window management and AppKit patterns
- `macos-system-integration.md` - macOS system services and extensions

### Specialized Development
- `testing.md` - Testing patterns and requirements
- `performance-optimization.md` - Performance best practices
- `shared-packages.md` - Cross-platform package development
- `analytics-patterns.md` - Pixel analytics and event tracking

## Quick Start Checklist

### Before Writing Any Code:
1. ✅ Read `privacy-security.md` - Privacy is non-negotiable
2. ✅ Check platform rules (`ios-architecture.md` or `macos-architecture.md`)
3. ✅ Review `anti-patterns.md` - Avoid common mistakes
4. ✅ REMEMBER: NEVER commit, push, or run tests without explicit user permission or unless explicitly asked to

### For UI Development:
1. ✅ Use `swiftui-style.md` for SwiftUI components
2. ✅ MUST use DesignResourcesKit colors: `Color(designSystemColor: .textPrimary)`
3. ✅ MUST use DesignResourcesKit icons: `DesignSystemImages.Glyphs.Size16.add`

### For New Features:
1. ✅ Follow `architecture.md` for MVVM + DI patterns
2. ✅ Use AppDependencyProvider (iOS) or equivalent (macOS)
3. ✅ Write tests per `testing.md` requirements

## Critical Don'ts (from anti-patterns.md)
- ❌ NEVER commit, push changes, create or delete branches on git or trigger github actions without EXPLICIT user permission
- ❌ NEVER run tests without EXPLICIT user permission or if user explicitly asked to in their prompt
- ❌ NEVER use singletons except for truly global state
- ❌ NEVER hardcode colors/icons (use DesignResourcesKit)
- ❌ NEVER update UI without @MainActor
- ❌ NEVER ignore privacy implications
- ❌ NEVER force unwrap without justification

## Dependency Injection Pattern (iOS)
```swift
// ✅ CORRECT pattern used throughout codebase
final class FeatureViewModel: ObservableObject {
    private let service: FeatureServiceProtocol
    
    init(dependencies: DependencyProvider = AppDependencyProvider.shared) {
        self.service = dependencies.featureService
    }
}
```

## Design System Usage (MANDATORY)
```swift
// ✅ REQUIRED - Use DesignResourcesKit
Text("Title")
    .foregroundColor(Color(designSystemColor: .textPrimary))

Image(uiImage: DesignSystemImages.Color.Size24.bookmark)

// ❌ FORBIDDEN - Hardcoded colors/icons
Text("Title").foregroundColor(.black)
Image(systemName: "bookmark")
```

## When to Consult Specific Rules
- **New ViewModels**: `architecture.md` + `swiftui-style.md`
- **Network calls**: `performance-optimization.md` + `privacy-security.md`
- **Settings/Preferences**: Platform-specific rules + `property-wrappers.md`
- **Feature flags**: `feature-flags.md`
- **Analytics/Tracking**: `analytics-patterns.md` + `privacy-security.md`
- **Advanced SwiftUI**: `swiftui-advanced.md`
- **Testing**: `testing.md` + `anti-patterns.md`
- **Cross-platform code**: `shared-packages.md`
- **WebView integration**: `webkit-browser.md`
- **macOS windows**: `macos-window-management.md`
- **macOS system features**: `macos-system-integration.md`

## Code Review Checklist
1. Privacy implications assessed (`privacy-security.md`)
2. Design system properly used (`swiftui-style.md`)
3. Architecture patterns followed (platform-specific rules)
4. Anti-patterns avoided (`anti-patterns.md`)
5. Tests written and passing (`testing.md`)
6. Performance considered (`performance-optimization.md`)

## Git & Testing Workflow Rules

### 🚨 MANDATORY: Never Auto-Execute Commands
**NEVER commit, push, or run tests without EXPLICIT user permission.**

#### Git Workflow:
1. Make file changes as requested
2. **STOP** before any `git add`, `git commit`, or `git push` commands  
3. **ASK** the user: "Should I commit/push these changes?"
4. **WAIT** for explicit permission (e.g., "yes", "commit it", "push it", "go ahead")
5. Only then execute git commands

#### Testing Workflow:
1. Write or modify code as requested
2. **STOP** before running any tests (`swift test`, `npm test`, `xcodebuild test`, etc.)
3. **ASK** the user: "Should I run the tests?"
4. **WAIT** for explicit permission (e.g., "yes", "run tests", "test it")
5. Only then execute test commands

#### What NOT to Do:
```bash
# ❌ WRONG - Never do these automatically
git add .
git commit -m "Updated files"
git push origin main
swift test
npm test
xcodebuild test
```

#### What TO Do:
```bash
# ✅ CORRECT - Ask first
echo "I've made the requested changes. Would you like me to:"
echo "1. Commit these changes?"
echo "2. Run the tests?" 
echo "3. Push to remote?"
# Wait for user response before any commands
```

**These rules have NO exceptions. Always ask before executing git or test commands.**

---

This overview ensures you understand the project context and know which specific rules to consult for your development task.