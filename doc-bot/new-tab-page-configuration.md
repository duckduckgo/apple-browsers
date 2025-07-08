---
alwaysApply: false
title: "New Tab Page Configuration Management"
description: "Configuration patterns for New Tab Page widgets including visibility and settings management"
keywords: ["macOS only","NTP configuration", "widget visibility", "NewTabPageConfigurationClient", "widget settings", "configuration persistence", "widget availability", "configuration migration"]
---

# NTP Configuration Management

## Configuration Client Architecture

Based on the reference implementation at `NewTabPageConfigurationClient.swift`, the configuration system manages widget visibility and availability.

### Core Configuration Model
```swift
// ✅ CORRECT - Configuration data structure
struct NewTabPageConfiguration: Codable {
    struct WidgetConfig: Codable {
        let isEnabled: Bool
        let isVisible: Bool
        let position: Int?
        let customSettings: [String: Any]?
    }
    
    let widgets: [String: WidgetConfig]
    let theme: ThemeConfiguration?
    let lastUpdated: Date
}
```

### Configuration Client Implementation
```swift
// ✅ CORRECT - Configuration client pattern
final class NewTabPageConfigurationClient: NewTabPageClient {
    typealias Model = NewTabPageConfiguration
    
    private let configurationProvider: ConfigurationProviding
    private let persistor: ConfigurationPersisting
    
    func handle(message: Message) async throws -> Model {
        switch message.name {
        case "configuration_getAll":
            return try await configurationProvider.getCurrentConfiguration()
            
        case "configuration_updateWidget":
            let widgetId = try message.decodeParam("widgetId", as: String.self)
            let config = try message.decodeParam("config", as: WidgetConfig.self)
            try await persistor.updateWidgetConfiguration(widgetId, config: config)
            return try await configurationProvider.getCurrentConfiguration()
            
        case "configuration_resetToDefaults":
            try await persistor.resetToDefaults()
            return try await configurationProvider.getCurrentConfiguration()
            
        default:
            throw ClientError.unhandledMessage
        }
    }
}
```

## Widget Visibility Management

### Visibility Provider Pattern
```swift
// ✅ CORRECT - Widget visibility control
protocol NewTabPageSectionsVisibilityProviding {
    func isWidgetVisible(_ widgetId: String) -> Bool
    func setWidgetVisibility(_ widgetId: String, isVisible: Bool)
    func availableWidgets() -> Set<String>
}

final class DefaultSectionsVisibilityProvider: NewTabPageSectionsVisibilityProviding {
    @UserDefaultsWrapper(key: .ntpWidgetVisibility, defaultValue: [:])
    private var widgetVisibility: [String: Bool]
    
    func isWidgetVisible(_ widgetId: String) -> Bool {
        widgetVisibility[widgetId] ?? defaultVisibility(for: widgetId)
    }
    
    func setWidgetVisibility(_ widgetId: String, isVisible: Bool) {
        widgetVisibility[widgetId] = isVisible
        NotificationCenter.default.post(
            name: .ntpWidgetVisibilityChanged,
            object: nil,
            userInfo: ["widgetId": widgetId, "isVisible": isVisible]
        )
    }
    
    private func defaultVisibility(for widgetId: String) -> Bool {
        switch widgetId {
        case "favorites", "privacyStats": return true
        case "recentActivity": return false
        default: return false
        }
    }
}
```

### Widget Availability
```swift
// ✅ CORRECT - Feature-based widget availability
protocol WidgetAvailabilityProviding {
    func isWidgetAvailable(_ widgetId: String) -> Bool
}

final class FeatureBasedWidgetAvailability: WidgetAvailabilityProviding {
    private let featureFlagger: FeatureFlagger
    
    func isWidgetAvailable(_ widgetId: String) -> Bool {
        switch widgetId {
        case "favorites":
            return true // Always available
        case "privacyStats":
            return true // Always available
        case "recentActivity":
            return featureFlagger.isFeatureOn(.recentActivityWidget)
        case "nextStepsCards":
            return featureFlagger.isFeatureOn(.onboardingCards)
        case "freemiumDBP":
            return featureFlagger.isFeatureOn(.freemiumDBPBanner)
        default:
            return false
        }
    }
}
```

## Settings Persistence

### UserDefaults-based Persistence
```swift
// ✅ CORRECT - Configuration persistence
protocol ConfigurationPersisting {
    func saveConfiguration(_ config: NewTabPageConfiguration) async throws
    func loadConfiguration() async throws -> NewTabPageConfiguration?
    func updateWidgetConfiguration(_ widgetId: String, config: WidgetConfig) async throws
    func resetToDefaults() async throws
}

final class UserDefaultsConfigurationPersistor: ConfigurationPersisting {
    @UserDefaultsWrapper(key: .ntpConfiguration, defaultValue: nil)
    private var storedConfiguration: Data?
    
    func saveConfiguration(_ config: NewTabPageConfiguration) async throws {
        let encoder = JSONEncoder()
        storedConfiguration = try encoder.encode(config)
    }
    
    func loadConfiguration() async throws -> NewTabPageConfiguration? {
        guard let data = storedConfiguration else { return nil }
        let decoder = JSONDecoder()
        return try decoder.decode(NewTabPageConfiguration.self, from: data)
    }
}
```

### Migration Support
```swift
// ✅ CORRECT - Configuration migration
final class ConfigurationMigrator {
    func migrateIfNeeded(from oldVersion: Int, to newVersion: Int) async throws {
        guard oldVersion < newVersion else { return }
        
        switch (oldVersion, newVersion) {
        case (1, 2):
            try await migrateV1ToV2()
        case (2, 3):
            try await migrateV2ToV3()
        default:
            // Handle other migrations
            break
        }
    }
    
    private func migrateV1ToV2() async throws {
        // Example: Add new widget to existing configuration
        var config = try await loadConfiguration()
        config.widgets["nextStepsCards"] = WidgetConfig(
            isEnabled: true,
            isVisible: false,
            position: nil,
            customSettings: nil
        )
        try await saveConfiguration(config)
    }
}
```

## Dynamic Widget Registration

### Widget Registry
```swift
// ✅ CORRECT - Dynamic widget management
final class WidgetRegistry {
    private var registeredWidgets: [String: WidgetDescriptor] = [:]
    
    struct WidgetDescriptor {
        let id: String
        let displayName: String
        let defaultConfig: WidgetConfig
        let requiresFeatureFlag: FeatureFlag?
    }
    
    func registerWidget(_ descriptor: WidgetDescriptor) {
        registeredWidgets[descriptor.id] = descriptor
    }
    
    func availableWidgets(for user: User?) -> [WidgetDescriptor] {
        registeredWidgets.values.filter { descriptor in
            // Check feature flag if required
            if let flag = descriptor.requiresFeatureFlag {
                return featureFlagger.isFeatureOn(flag)
            }
            return true
        }
    }
}
```

## Configuration Change Notifications

### Reactive Updates
```swift
// ✅ CORRECT - Configuration change propagation
extension Notification.Name {
    static let ntpConfigurationChanged = Notification.Name("NTPConfigurationChanged")
    static let ntpWidgetVisibilityChanged = Notification.Name("NTPWidgetVisibilityChanged")
}

final class ConfigurationObserver {
    private var cancellables = Set<AnyCancellable>()
    
    func observeConfigurationChanges() {
        NotificationCenter.default.publisher(for: .ntpConfigurationChanged)
            .sink { [weak self] notification in
                self?.handleConfigurationChange(notification)
            }
            .store(in: &cancellables)
    }
    
    private func handleConfigurationChange(_ notification: Notification) {
        // Update all active NTP tabs
        NewTabPageActionsManager.shared.refreshAllTabs()
    }
}
```

## Testing Configuration

### Mock Configuration Provider
```swift
// ✅ CORRECT - Test configuration provider
final class MockConfigurationProvider: ConfigurationProviding {
    var configuration: NewTabPageConfiguration = .default
    var getCurrentConfigurationCalls = 0
    
    func getCurrentConfiguration() async throws -> NewTabPageConfiguration {
        getCurrentConfigurationCalls += 1
        return configuration
    }
}

extension NewTabPageConfiguration {
    static var `default`: Self {
        Self(
            widgets: [
                "favorites": WidgetConfig(isEnabled: true, isVisible: true, position: 0, customSettings: nil),
                "privacyStats": WidgetConfig(isEnabled: true, isVisible: true, position: 1, customSettings: nil)
            ],
            theme: nil,
            lastUpdated: Date()
        )
    }
}
```

### Configuration Client Tests
```swift
// ✅ CORRECT - Configuration testing
func testWidgetVisibilityUpdate() async throws {
    // Arrange
    let provider = MockConfigurationProvider()
    let persistor = MockConfigurationPersistor()
    let client = NewTabPageConfigurationClient(
        configurationProvider: provider,
        persistor: persistor
    )
    
    // Act
    let message = Message(
        name: "configuration_updateWidget",
        params: [
            "widgetId": "favorites",
            "config": [
                "isEnabled": true,
                "isVisible": false
            ]
        ]
    )
    
    let result = try await client.handle(message: message)
    
    // Assert
    XCTAssertEqual(persistor.updateWidgetConfigurationCalls.count, 1)
    XCTAssertEqual(persistor.updateWidgetConfigurationCalls.first?.widgetId, "favorites")
    XCTAssertFalse(persistor.updateWidgetConfigurationCalls.first?.config.isVisible ?? true)
}
```

## Best Practices

### 1. Default Configuration
```swift
// ✅ CORRECT - Provide sensible defaults
struct DefaultConfiguration {
    static let widgets: [String: WidgetConfig] = [
        "favorites": WidgetConfig(
            isEnabled: true,
            isVisible: true,
            position: 0,
            customSettings: ["maxItems": 12]
        ),
        "privacyStats": WidgetConfig(
            isEnabled: true,
            isVisible: true,
            position: 1,
            customSettings: nil
        ),
        "recentActivity": WidgetConfig(
            isEnabled: true,
            isVisible: false,
            position: 2,
            customSettings: ["maxDays": 7]
        )
    ]
}
```

### 2. Validation
```swift
// ✅ CORRECT - Validate configuration updates
extension WidgetConfig {
    func validate() throws {
        if let position = position, position < 0 {
            throw ConfigurationError.invalidPosition
        }
        
        if let customSettings = customSettings {
            try validateCustomSettings(customSettings)
        }
    }
}
```