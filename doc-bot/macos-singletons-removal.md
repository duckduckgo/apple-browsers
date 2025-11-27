---
alwaysApply: false
title: "macOS Singleton Removal Rules"
description: "Pattern for removing .shared singletons in the macOS app by replacing them with AppDelegate-owned instances and dependency injection"
keywords: ["macOS", "singletons", "dependency injection", "AppDelegate", "NSApp.delegateTyped"]
---

## macOS Singleton Removal Rules

### Purpose

Define a concrete pattern for removing `.shared` singletons in the macOS app by replacing them with app-owned instances and dependency injection. The `AIChatPreferences` and `AboutPreferences` refactors in `AppDelegate` are canonical examples.

### Rules

1. **Do not introduce new singletons**
   - Never add new `static let shared` or similar global singletons.
   - New dependencies must be passed in via initializers or factory methods, not fetched from global state.

2. **Move ownership to the composition root (AppDelegate)**
   - Add a stored property on the macOS composition root (currently `AppDelegate`) for the dependency, for example:
     - `let aiChatPreferences: AIChatPreferences`
   - Construct the instance during app setup using real dependencies:
     - Inject storage (e.g. `DefaultAIChatPreferencesStorage`)
     - Inject configuration objects (e.g. `AIChatMenuVisibilityConfigurable`)
     - Inject window managers via protocols (e.g. `WindowControllersManagerProtocol`)
     - Inject feature flaggers and other services as needed
   - Prefer protocol-typed properties in `AppDelegate` when the dependency has a clear protocol (to keep testing and substitution easy).

3. **Thread the dependency through initializers**
   - For view controllers and models that need the former singleton, add initializer parameters and store them as non-optional properties. Example:
     - `init(..., aiChatPreferences: AIChatPreferences = NSApp.delegateTyped.aiChatPreferences, ...)`
   - Avoid using `NSApp.delegateTyped` or `Application.appDelegate` and prefer to pass the dependency down from a parent object.
     - If a parent object doesn't contain the dependency, it should be updated to have it passed down from its own parent object, observing the exceptions mentioned below.
   - It is explicitly allowed to use `NSApp.delegateTyped`:
     - In the `Tab` initializer (following the existing pattern for other dependencies)
     - In default parameter values for the `MainViewController` initializer (this is the entry point for the dependency chain)
     - In default parameter values for the `TabCollectionViewModel` initializer (following the existing pattern for other dependencies)
     - In default parameter values for the `TabViewModel` initializer (temporary exception, will be refactored later)
     - **Exception**: For `@MainActor` initializers, use optional parameters with `nil` defaults and assign from `NSApp.delegateTyped` in the initializer body.
   - **Important: Main actor isolation**: If an initializer is marked `@MainActor` and you need to default a parameter from `NSApp.delegateTyped`, use an optional parameter with `nil` default instead of accessing `NSApp.delegateTyped` in the default value. Then assign the value inside the initializer body:
     - ❌ `init(savedZoomLevelsCoordinating: SavedZoomLevelsCoordinating = NSApp.delegateTyped.accessibilityPreferences)` (causes main actor isolation warning)
     - ✅ `init(savedZoomLevelsCoordinating: SavedZoomLevelsCoordinating? = nil)` with `self.savedZoomLevelsCoordinating = savedZoomLevelsCoordinating ?? NSApp.delegateTyped.accessibilityPreferences` in the body
   - When creating child objects from a parent that already has the dependency, pass the property down rather than re-reading from `NSApp.delegateTyped`.
   - **For preferences models that need to reach SwiftUI views**, thread through the entire chain:
     - `MainViewController` (with default parameter) → `BrowserTabViewController` → `PreferencesViewController` → `PreferencesSidebarModel` → `PreferencesRootView`
     - Follow the existing pattern used by other preferences (e.g., `searchPreferences`, `tabsPreferences`, `aiChatPreferences`)
     - When adding to `PreferencesSidebarModel`, add the property alongside existing preferences and update both the main `init` and convenience `init`
   - **For dependencies that need to reach UserScripts initialization** (e.g., `DuckPlayerPreferences`), thread through the content blocking infrastructure:
     - `AppDelegate` → `AppContentBlocking` → `UserContentUpdating` → `ScriptSourceProvider` (via `ScriptSourceProviding` protocol) → `UserScripts`
     - Add the dependency to `ScriptSourceProviding` protocol as a property
     - Add it to `ScriptSourceProvider` struct (property and initializer parameter)
     - Add it to `UserContentUpdating` initializer and pass to `ScriptSourceProvider` in `makeValue` closure
     - Add it to `AppContentBlocking` initializers (both convenience and main) and pass to `UserContentUpdating`
     - Pass it from `AppDelegate` to `AppContentBlocking` initialization
     - In `UserScripts`, access via `sourceProvider.duckPlayerPreferences` instead of using a default parameter
     - This follows the same pattern as `WebTrackingProtectionPreferences` and `CookiePopupProtectionPreferences`

4. **Update utility code and extensions carefully**
   - For helpers like `URL` extensions where dependency injection is impractical, read the instance from the composition root instead of a singleton:
     - `NSApp.delegateTyped.aiChatPreferences` instead of `AIChatPreferences.shared`.
   - Keep these usages minimal; prefer passing dependencies into call sites where it's feasible.
   - **In AppDelegate extensions**: When the code is in an extension of `AppDelegate` (e.g., `extension AppDelegate`), access properties directly via `self.propertyName` rather than `NSApp.delegateTyped.propertyName`:
     - ✅ `duckPlayerPreferences.reset()` (in `extension AppDelegate`)
     - ❌ `NSApp.delegateTyped.duckPlayerPreferences.reset()` (unnecessary indirection)
   - **For protocol-typed dependencies**: If a class conforms to a protocol (e.g., `AccessibilityPreferences` conforms to `SavedZoomLevelsCoordinating`), you can use the protocol type in initializers. The dependency can be passed as the protocol type while still being owned as the concrete type in `AppDelegate`.
   - **In SwiftUI views**, once a dependency is available on a model (e.g., `PreferencesSidebarModel`), use the model's property rather than accessing via `NSApp.delegateTyped`:
     - ✅ `AboutView(model: model.aboutPreferences)`
     - ❌ `AboutView(model: NSApp.delegateTyped.aboutPreferences)`
   - This ensures the view uses the injected instance and maintains proper dependency flow.

5. **Simplify protocol wrappers that only exist for the singleton**
   - If a protocol exists solely to hide a singleton (e.g. a minimal `AIFeaturesStatusProviding` that just wraps `AIChatPreferences.shared`), prefer depending directly on the concrete type once it is injectible.
   - Update initializers and stored properties to use the concrete type (`AIChatPreferences`) when it already exposes the required API and publishers.

6. **Update tests to construct their own instances**
   - In tests, build the dependency explicitly instead of using global state. For example:
     - `AIChatPreferences(storage: MockAIChatPreferencesStorage(), aiChatMenuConfiguration: MockAIChatConfig(), windowControllersManager: WindowControllersManagerMock(), featureFlagger: MockFeatureFlagger())`
   - Pass these instances into the subject under test via its initializer (e.g. `PreferencesSidebarModel`, `BrowserTabViewController`, `PreferencesViewController`).
   - Remove ad-hoc singleton-like test doubles (e.g. `MockAIChatPreferences.shared`) once real instances are injected.
   - **Update all test helper methods**: When a test file has helper methods that create instances (e.g., `PreferencesSidebarModel` factory methods), update all of them to include the new dependency parameter.
   - **Reuse existing mocks**: When initializing the dependency in tests, reuse existing mock objects from the test setup:
     - Use `mockFeatureFlagger.internalUserDecider` if `MockFeatureFlagger` is already available
     - Use existing `windowControllersManager` instances (e.g., `WindowControllersManagerMock()`)
     - Example: `AboutPreferences(internalUserDecider: mockFeatureFlagger.internalUserDecider, featureFlagger: mockFeatureFlagger, windowControllersManager: windowControllersManager)`
   - **Create shared test instances**: For test classes that have many tests using the dependency, create a shared instance as a property:
     - `let accessibilityPreferences = AccessibilityPreferences()` at the class level
     - Reuse this instance across multiple test methods to avoid creating duplicate instances
   - **Update helper methods in test extensions**: Don't forget to update helper methods in extensions (e.g., `TabViewModel.aTabViewModel` static property) that create instances
   - **Search comprehensively**: Use `grep` to find all test files that instantiate classes requiring the dependency, including:
     - Direct instantiations in test methods
     - Helper/factory methods that create instances
     - Integration tests that create full object graphs
     - Static helper properties/methods in test extensions

7. **Remove the singleton API last**
   - After all production code and tests use the injected instance or the app-owned property, delete `static let shared` and any remaining references to it.
   - Ensure you do not leave a mixed state where some call sites use the injected instance and others still use `.shared` for the same type within the modified area.
   - Change `private init` to `init` to make the initializer publicly accessible once the singleton is removed.

### Example: AboutPreferences Refactoring

The `AboutPreferences.shared` singleton removal demonstrates the complete pattern:

1. **AppDelegate**: Added `let aboutPreferences: AboutPreferences` and initialized it with dependencies (`internalUserDecider`, `featureFlagger`, `windowControllersManager`)

2. **MainViewController**: Added `aboutPreferences: AboutPreferences = NSApp.delegateTyped.aboutPreferences` parameter (with default) and passed it to `BrowserTabViewController`

3. **BrowserTabViewController**: Added `aboutPreferences` property and parameter, stored it, and passed it to `PreferencesViewController`

4. **PreferencesViewController**: Added `aboutPreferences` parameter and passed it to `PreferencesSidebarModel`

5. **PreferencesSidebarModel**: Added `let aboutPreferences: AboutPreferences` property and updated both initializers to accept and store it

6. **PreferencesRootView**: Updated to use `model.aboutPreferences` instead of `NSApp.delegateTyped.aboutPreferences`

7. **Test files**: Updated all test files that create instances in the dependency chain:
   - `PreferencesSidebarModelTests.swift`: Updated 3 helper methods to include `aboutPreferences` parameter
   - `BrowserTabViewControllerOnboardingTests.swift`: Added `aboutPreferences` to `BrowserTabViewController` initialization
   - `RootViewV2Tests.swift`: Added `aboutPreferences` to `PreferencesSidebarModel` initialization
   - All tests reuse existing mocks: `AboutPreferences(internalUserDecider: mockFeatureFlagger.internalUserDecider, featureFlagger: mockFeatureFlagger, windowControllersManager: windowControllersManager)`

8. **AboutPreferences**: Removed `static let shared` and changed `private init` to `init`

This pattern ensures the dependency flows through the entire chain while maintaining testability and avoiding global state access in views.

### Example: AccessibilityPreferences Refactoring

The `AccessibilityPreferences.shared` singleton removal demonstrates additional patterns:

1. **AppDelegate**: Added `let accessibilityPreferences: AccessibilityPreferences` and initialized it with default dependencies

2. **Dependency chain**: Threaded through `MainViewController` → `BrowserTabViewController` → `PreferencesViewController` → `PreferencesSidebarModel` → `PreferencesRootView`

3. **TabViewModel**: Updated existing `accessibilityPreferences` parameter default from `.shared` to `NSApp.delegateTyped.accessibilityPreferences`

4. **Fire initializer (Main actor isolation)**: Used optional parameter pattern to avoid main actor isolation warning:
   ```swift
   @MainActor
   init(savedZoomLevelsCoordinating: SavedZoomLevelsCoordinating? = nil, ...) {
       self.savedZoomLevelsCoordinating = savedZoomLevelsCoordinating ?? NSApp.delegateTyped.accessibilityPreferences
   }
   ```

5. **Protocol conformance**: `AccessibilityPreferences` conforms to `SavedZoomLevelsCoordinating`, allowing it to be passed as a protocol type where needed

6. **Test patterns**: Created shared `accessibilityPreferences` instance in test classes:
   ```swift
   final class TabViewModelTests: XCTestCase {
       let accessibilityPreferences = AccessibilityPreferences()
       // ... tests reuse this instance
   }
   ```

7. **Test helper methods**: Updated all helper methods including static properties in extensions (e.g., `TabViewModel.aTabViewModel`)

### Example: DuckPlayerPreferences Refactoring

The `DuckPlayerPreferences.shared` singleton removal demonstrates the pattern for dependencies that need to reach `UserScripts` initialization:

1. **AppDelegate**: Added `let duckPlayerPreferences: DuckPlayerPreferences` and initialized it with dependencies (`privacyConfigurationManager`, `internalUserDecider`)

2. **Dependency chain for UserScripts**: Threaded through:
   - `AppDelegate` → `AppContentBlocking` → `UserContentUpdating` → `ScriptSourceProvider` (via `ScriptSourceProviding` protocol) → `UserScripts`
   - This follows the same pattern as `WebTrackingProtectionPreferences` and `CookiePopupProtectionPreferences`

3. **ScriptSourceProviding protocol**: Added `var duckPlayerPreferences: DuckPlayerPreferences { get }` property

4. **ScriptSourceProvider**: Added `duckPlayerPreferences` property and parameter to initializer

5. **UserContentUpdating**: Added `duckPlayerPreferences` parameter and passed it to `ScriptSourceProvider` in the `makeValue` closure

6. **AppContentBlocking**: Added `duckPlayerPreferences` to both convenience and main initializers, passed it to `UserContentUpdating`

7. **AppDelegate**: Passed `duckPlayerPreferences` to `AppContentBlocking` initialization (both DEBUG and release paths)

8. **UserScripts**: Removed default parameter `duckPlayerPreferences: DuckPlayerPreferences = NSApp.delegateTyped.duckPlayerPreferences` and accessed it via `sourceProvider.duckPlayerPreferences` instead

9. **Preferences view chain**: Also threaded through `MainViewController` → `BrowserTabViewController` → `PreferencesViewController` → `PreferencesSidebarModel` → `PreferencesRootView` for SwiftUI views

10. **MainMenuActions**: Updated to use `duckPlayerPreferences` directly (since it's in `extension AppDelegate`)

This pattern ensures dependencies that need to reach `UserScripts` initialization are properly injected through the content blocking infrastructure, avoiding default parameters that access `NSApp.delegateTyped` during initialization.

### Test Updates Checklist

When removing a singleton, ensure all tests are updated:

1. **Find all test files** that instantiate classes in the dependency chain:
   ```bash
   grep -r "ClassName(" macOS/UnitTests macOS/IntegrationTests
   ```

2. **Update helper methods**: If test files have helper/factory methods that create instances, update all of them:
   - Look for `private func` methods that return the type
   - Look for `create*` or `make*` helper methods
   - Example: `PreferencesSidebarModelTests.swift` had 3 helper methods that all needed `aboutPreferences`

3. **Reuse existing mocks**: When creating the dependency instance in tests:
   - Check what mocks are already available in `setUp()` or test properties
   - Use `mockFeatureFlagger.internalUserDecider` if available
   - Reuse `WindowControllersManagerMock()` instances already created
   - Avoid creating duplicate mock instances

4. **Verify compilation**: After updates, ensure:
   - No linting errors
   - All test files compile successfully
   - Run tests to verify they pass

### Enforcement

- **Never approve PRs that add new `.shared`-style singletons in macOS code.**
- **When reviewing singleton removals, require:**
  - A clearly owned instance on the composition root (`AppDelegate`).
  - Dependencies threaded via initializers with sensible defaults from `NSApp.delegateTyped`.
  - Tests constructing their own instances without relying on global state.
  - No remaining usages of the removed `TypeName.shared` in the modified scope.


