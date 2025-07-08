---
alwaysApply: false
title: "User Defaults Storage Patterns"
description: "Modern user defaults storage patterns using KVO with KeyValueStore (formerly property wrappers)"
keywords: ["user defaults", "KVO", "KeyValueStore", "settings", "storage", "persistor", "UserDefaults", "property wrappers", "deprecated"]
---

# User Defaults Settings Storage and Reading

## ✅ RECOMMENDED - KVO Pattern with KeyValueStore

Use the KVO pattern with KeyValueStore for all new persistent settings:

```swift
// ✅ CORRECT - KVO pattern with KeyValueStore
struct AppearancePreferencesUserDefaultsPersistor: AppearancePreferencesPersistor {

    enum Key: String {
        case newTabPageIsOmnibarVisible = "new-tab-page.omnibar.is-visible"
        case newTabPageIsProtectionsReportVisible = "new-tab-page.protections-report.is-visible"
        case userPreferences = "user.preferences"
        case lastUpdateCheck = "last.update.check"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var isOmnibarVisible: Bool {
        get { (try? keyValueStore.object(forKey: Key.newTabPageIsOmnibarVisible.rawValue) as? Bool) ?? true }
        set { try? keyValueStore.set(newValue, forKey: Key.newTabPageIsOmnibarVisible.rawValue) }
    }

    var isProtectionsReportVisible: Bool {
        get { (try? keyValueStore.object(forKey: Key.newTabPageIsProtectionsReportVisible.rawValue) as? Bool) ?? false }
        set { try? keyValueStore.set(newValue, forKey: Key.newTabPageIsProtectionsReportVisible.rawValue) }
    }

    var userPreferences: [String: String] {
        get { (try? keyValueStore.object(forKey: Key.userPreferences.rawValue) as? [String: String]) ?? [:] }
        set { try? keyValueStore.set(newValue, forKey: Key.userPreferences.rawValue) }
    }

    var lastUpdateCheck: Date {
        get { (try? keyValueStore.object(forKey: Key.lastUpdateCheck.rawValue) as? Date) ?? Date.distantPast }
        set { try? keyValueStore.set(newValue, forKey: Key.lastUpdateCheck.rawValue) }
    }
}
```

## Key Guidelines for KVO Pattern

1. **Use struct conforming to protocol** - Follow the persistor pattern
2. **Define keys as enum with String raw values** - Use kebab-case for key names
3. **Use KeyValueStoring protocol** - Not direct UserDefaults access
4. **Computed properties with get/set** - Handle storage operations in accessors
5. **Use try? for error handling** - KeyValueStore operations can throw
6. **Provide default values** - Use nil coalescing operator (??) for defaults
7. **Inject KeyValueStore in init** - Enable dependency injection and testing

## Advanced Pattern for Optional Values

```swift
// ✅ CORRECT - Optional values pattern
struct SettingsUserDefaultsPersistor: SettingsPersistor {

    enum Key: String {
        case optionalUserName = "user.name"
        case optionalTheme = "app.theme"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var optionalUserName: String? {
        get { try? keyValueStore.object(forKey: Key.optionalUserName.rawValue) as? String }
        set { 
            if let value = newValue {
                try? keyValueStore.set(value, forKey: Key.optionalUserName.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.optionalUserName.rawValue)
            }
        }
    }

    var selectedTheme: Theme? {
        get { 
            guard let rawValue = try? keyValueStore.object(forKey: Key.optionalTheme.rawValue) as? String else { return nil }
            return Theme(rawValue: rawValue)
        }
        set { 
            if let value = newValue {
                try? keyValueStore.set(value.rawValue, forKey: Key.optionalTheme.rawValue)
            } else {
                try? keyValueStore.removeObject(forKey: Key.optionalTheme.rawValue)
            }
        }
    }
}
```

## Platform-Specific Storage

```swift
// ✅ CORRECT - Platform-specific KeyValueStore usage
struct PlatformSettingsUserDefaultsPersistor: PlatformSettingsPersistor {

    enum Key: String {
        case platformSpecificSetting = "platform.specific.setting"
    }

    private let keyValueStore: KeyValueStoring

    init(keyValueStore: KeyValueStoring) {
        self.keyValueStore = keyValueStore
    }

    var platformSpecificSetting: Bool {
        get { 
            #if os(iOS)
            return (try? keyValueStore.object(forKey: Key.platformSpecificSetting.rawValue) as? Bool) ?? false
            #elseif os(macOS)
            return (try? keyValueStore.object(forKey: Key.platformSpecificSetting.rawValue) as? Bool) ?? true
            #endif
        }
        set { 
            try? keyValueStore.set(newValue, forKey: Key.platformSpecificSetting.rawValue)
        }
    }
}
```

## 🚫 DEPRECATED - @UserDefaultsWrapper Pattern

The following pattern is deprecated and should not be used for new code:

```swift
// ❌ DEPRECATED - Do not use @UserDefaultsWrapper for new code
extension AppUserDefaults {
    @UserDefaultsWrapper(key: .newFeatureEnabled, defaultValue: false)
    var newFeatureEnabled: Bool
    
    @UserDefaultsWrapper(key: .lastUpdateCheck, defaultValue: Date.distantPast)
    var lastUpdateCheck: Date
}
```

## Migration from Property Wrappers

When migrating from `@UserDefaultsWrapper` to the KVO pattern:

1. **Create a new persistor struct** - Following the naming convention `*UserDefaultsPersistor`
2. **Define keys enum** - Convert string keys to enum cases
3. **Convert properties** - Transform @UserDefaultsWrapper properties to computed properties
4. **Update injection** - Pass KeyValueStore through dependency injection
5. **Preserve key names** - Ensure existing UserDefaults keys remain unchanged

## Testing Pattern

```swift
// ✅ CORRECT - Testing with mock KeyValueStore
class MockKeyValueStore: KeyValueStoring {
    private var storage: [String: Any] = [:]
    
    func object(forKey key: String) throws -> Any? {
        return storage[key]
    }
    
    func set(_ value: Any, forKey key: String) throws {
        storage[key] = value
    }
    
    func removeObject(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }
}

// In tests
let mockStore = MockKeyValueStore()
let persistor = AppearancePreferencesUserDefaultsPersistor(keyValueStore: mockStore)
persistor.isOmnibarVisible = true
XCTAssertTrue(persistor.isOmnibarVisible)
```

## What NOT to Do

```swift
// ❌ INCORRECT - Direct UserDefaults access
var newFeatureEnabled: Bool {
    get { return UserDefaults.standard.bool(forKey: "newFeature") }
    set { UserDefaults.standard.set(newValue, forKey: "newFeature") }
}

// ❌ INCORRECT - Using @UserDefaultsWrapper for new code
@UserDefaultsWrapper(key: .newFeatureEnabled, defaultValue: false)
var newFeatureEnabled: Bool

// ❌ INCORRECT - Not handling errors
var setting: Bool {
    get { keyValueStore.object(forKey: "key") as? Bool ?? false } // Missing try?
    set { keyValueStore.set(newValue, forKey: "key") } // Missing try?
}

// ❌ INCORRECT - Not using enum for keys
var setting: Bool {
    get { (try? keyValueStore.object(forKey: "hardcoded-key") as? Bool) ?? false }
    set { try? keyValueStore.set(newValue, forKey: "hardcoded-key") }
}
```

The KVO pattern with KeyValueStore provides better testability, error handling, and dependency injection while maintaining type safety and consistency across the codebase.