---
alwaysApply: false
title: "New Tab Page Architecture & Implementation Guide"
description: "Comprehensive guide for New Tab Page implementation including widget architecture and multi-tab synchronization"
keywords: ["macOS", "New Tab Page", "NTP", "widgets", "user script", "favorites", "privacy stats", "recent activity", "remote messages", "macOS", "NewTabPageActionsManager", "widget architecture"]
---

# New Tab Page (NTP) Architecture

## Overview
The New Tab Page provides communication between the NTP user script and native macOS browser code, managing multiple widgets and ensuring synchronization across multiple NTP tabs.

## Core Architecture Components

### 1. NewTabPageActionsManager
Central coordinator for all NTP functionality:
```swift
// ✅ CORRECT - Use NewTabPageActionsManager for coordination
final class NewTabPageActionsManager {
    // Manages synchronization across multiple NTP tabs
    // Coordinates all widget updates
    // Handles messaging between native and JavaScript
}
```

### 2. User Script Architecture
Single dedicated web view with one user script:
```swift
// ✅ CORRECT - NewTabPageUserScript pattern
final class NewTabPageUserScript: NSObject, WKScriptMessageHandler {
    // Handles all communication with NTP frontend
    // Routes messages to appropriate clients
}

// ✅ CORRECT - NewTabPageUserContentController
final class NewTabPageUserContentController: WKUserContentController {
    // Manages script injection and message handlers
}
```

### 3. Widget Client Pattern
Each widget has its own client for modularity:
```swift
// ✅ CORRECT - Individual widget clients
protocol NewTabPageClient {
    associatedtype Model
    func handle(message: Message) async throws -> Model
}

// Examples:
final class NewTabPageFavoritesClient: NewTabPageClient { }
final class NewTabPagePrivacyStatsClient: NewTabPageClient { }
final class NewTabPageRecentActivityClient: NewTabPageClient { }
final class NewTabPageRMFClient: NewTabPageClient { }
final class NewTabPageNextStepsCardsClient: NewTabPageClient { }
final class NewTabPageFreemiumDBPClient: NewTabPageClient { }
final class NewTabPageProtectionsReportClient: NewTabPageClient { }
```

## Widget Implementation Patterns

### 1. Data Model Integration
Each widget extends the main data model:
```swift
// ✅ CORRECT - Extension pattern for data models
extension NewTabPageDataModel {
    struct Favorites: Codable {
        let items: [Favorite]
        let supportsReordering: Bool
    }
    
    struct PrivacyStats: Codable {
        let trackersBlocked: Int
        let adsBlocked: Int
        let companiesBlocked: Int
    }
}
```

### 2. Configuration Management
Centralized configuration for widget visibility:
```swift
// ✅ CORRECT - Configuration client pattern
final class NewTabPageConfigurationClient {
    func updateConfiguration(_ config: Configuration) async
    func handleVisibilityChange(for widget: Widget, isVisible: Bool)
}

// ❌ INCORRECT - Direct widget manipulation
widget.isHidden = true  // Don't bypass configuration
```

### 3. Actions Handler Pattern
Separate action handling from data provision:
```swift
// ✅ CORRECT - Actions handler pattern
protocol NewTabPageFavoritesActionsHandler {
    func handleAddFavorite(_ url: URL) async
    func handleEditFavorite(_ favorite: Favorite) async
    func handleDeleteFavorite(_ id: String) async
    func handleReorderFavorites(_ ids: [String]) async
}

protocol NewTabPageRecentActivityActionsHandling {
    func handleOpenLink(_ url: URL)
    func handleDeleteItem(_ id: String)
}
```

## Adding New Widgets

### 1. Create Widget Client
```swift
// ✅ CORRECT - New widget implementation
final class NewTabPageMyWidgetClient: NewTabPageClient {
    typealias Model = NewTabPageDataModel.MyWidget
    
    private let dataProvider: MyWidgetDataProviding
    private let actionsHandler: MyWidgetActionsHandling
    
    func handle(message: Message) async throws -> Model {
        switch message.name {
        case "myWidget_getData":
            return try await dataProvider.fetchData()
        case "myWidget_performAction":
            try await actionsHandler.performAction(message.params)
            return try await dataProvider.fetchData()
        default:
            throw ClientError.unhandledMessage
        }
    }
}
```

### 2. Extend Data Model
```swift
extension NewTabPageDataModel {
    struct MyWidget: Codable {
        let title: String
        let items: [Item]
        let configuration: WidgetConfig
    }
}
```

### 3. Register with Actions Manager
```swift
// In NewTabPageActionsManager initialization
let myWidgetClient = NewTabPageMyWidgetClient(
    dataProvider: myWidgetProvider,
    actionsHandler: myWidgetHandler
)
userScript.registerClient(myWidgetClient, for: "myWidget")
```

## Testing Patterns

### 1. Mock Providers
```swift
// ✅ CORRECT - Capturing mock pattern
final class CapturingMyWidgetDataProvider: MyWidgetDataProviding {
    var capturedFetchDataCalls = 0
    var fetchDataResult: Result<MyWidget, Error> = .success(.mock)
    
    func fetchData() async throws -> MyWidget {
        capturedFetchDataCalls += 1
        return try fetchDataResult.get()
    }
}
```

### 2. Test Helpers
```swift
// ✅ CORRECT - Message helper for testing
extension Message {
    static func myWidgetGetData() -> Message {
        Message(name: "myWidget_getData", params: [:])
    }
}
```

## Performance Considerations

### 1. Lazy Loading
Only load widget data when visible:
```swift
// ✅ CORRECT - Lazy loading pattern
func loadWidgetIfNeeded(_ widget: Widget) async {
    guard widgetIsVisible(widget) else { return }
    let data = try await fetchWidgetData(widget)
    await updateWidget(widget, with: data)
}
```

### 2. Synchronization
Ensure updates propagate to all NTP tabs:
```swift
// ✅ CORRECT - Multi-tab synchronization
final class NewTabPageActionsManager {
    func notifyAllTabs(update: WidgetUpdate) {
        for tab in activeNTPTabs {
            tab.apply(update)
        }
    }
}
```

## Common Patterns

### 1. Link Opening
```swift
// ✅ CORRECT - Centralized link handling
final class LinkOpenSender {
    func openLink(_ url: URL, target: LinkOpenTarget) {
        // Handles all link opening from NTP
    }
}
```

### 2. Context Menu Integration
```swift
// ✅ CORRECT - Context menu presenter
protocol NewTabPageContextMenuPresenting {
    func presentContextMenu(for item: ContextMenuItem, at point: CGPoint)
}
```

### 3. Custom Background Support
```swift
// ✅ CORRECT - Custom background client
final class NewTabPageCustomBackgroundClient {
    func updateBackground(_ background: CustomBackground) async
    func handleCustomizerOpen() async
}
```

## Directory Structure
```
macOS/LocalPackages/NewTabPage/
├── Package.swift
├── Sources/NewTabPage/
│   ├── Common/                    # Shared utilities
│   ├── Configuration/             # Widget configuration
│   ├── CustomBackground/          # Background customization
│   ├── Favorites/                 # Favorites widget
│   ├── FreemiumDBP/              # Freemium DBP banner
│   ├── NextStepsCards/           # Onboarding cards
│   ├── Omnibar/                  # Search integration
│   ├── PrivacyStats/             # Privacy statistics
│   ├── ProtectionsReport/        # Protection metrics
│   ├── RMF/                      # Remote messages
│   ├── RecentActivity/           # Recent browsing
│   └── NewTabPageActionsManager.swift
└── Tests/NewTabPageTests/        # Comprehensive tests
```