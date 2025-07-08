---
alwaysApply: false
title: "New Tab Page Widget Development Guidelines"
description: "Detailed patterns for developing individual NTP widgets with comprehensive testing strategies"
keywords: ["macOS only", "NTP widgets", "favorites widget", "privacy stats widget", "recent activity", "remote messages", "widget testing", "mocks", "capturing pattern", "NewTabPageFavoritesClient", "widget development"]
---
# NTP Widget Development Patterns

## Favorites Widget Implementation

### Data Model
```swift
extension NewTabPageDataModel {
    struct Favorites: Codable {
        struct Favorite: Codable {
            let id: String
            let title: String
            let url: URL
            let domain: String
            let favicon: FaviconInfo?
        }
        
        let items: [Favorite]
        let supportsReordering: Bool
        let maxItems: Int
    }
}
```

### Client Implementation
```swift
// ✅ CORRECT - Favorites client pattern
final class NewTabPageFavoritesClient: NewTabPageClient {
    typealias Model = NewTabPageDataModel.Favorites
    
    private let favoritesProvider: FavoritesProviding
    private let actionsHandler: NewTabPageFavoritesActionsHandler
    
    func handle(message: Message) async throws -> Model {
        switch message.name {
        case "favorites_getData":
            return try await favoritesProvider.fetchFavorites()
            
        case "favorites_add":
            let url = try message.decodeParam("url", as: URL.self)
            try await actionsHandler.handleAddFavorite(url)
            return try await favoritesProvider.fetchFavorites()
            
        case "favorites_delete":
            let id = try message.decodeParam("id", as: String.self)
            try await actionsHandler.handleDeleteFavorite(id)
            return try await favoritesProvider.fetchFavorites()
            
        case "favorites_reorder":
            let ids = try message.decodeParam("ids", as: [String].self)
            try await actionsHandler.handleReorderFavorites(ids)
            return try await favoritesProvider.fetchFavorites()
            
        default:
            throw ClientError.unhandledMessage
        }
    }
}
```

### Actions Handler
```swift
// ✅ CORRECT - Separate actions from data provision
protocol NewTabPageFavoritesActionsHandler {
    func handleAddFavorite(_ url: URL) async throws
    func handleEditFavorite(_ favorite: Favorite) async throws
    func handleDeleteFavorite(_ id: String) async throws
    func handleReorderFavorites(_ ids: [String]) async throws
    func handleOpenFavorite(_ url: URL, target: LinkOpenTarget)
}
```

## Privacy Stats Widget

### Model with Computed Properties
```swift
extension NewTabPageDataModel {
    struct PrivacyStats: Codable {
        let trackersBlocked: Int
        let adsBlocked: Int
        let companiesBlocked: Set<String>
        let estimatedTrackingAttemptsBlocked: Int
        
        var companiesBlockedCount: Int {
            companiesBlocked.count
        }
        
        var formattedStats: FormattedStats {
            FormattedStats(
                trackers: NumberFormatter.abbreviated(trackersBlocked),
                ads: NumberFormatter.abbreviated(adsBlocked),
                companies: NumberFormatter.abbreviated(companiesBlockedCount)
            )
        }
    }
}
```

### Client with Event Handling
```swift
// ✅ CORRECT - Privacy stats with analytics
final class NewTabPagePrivacyStatsClient: NewTabPageClient {
    private let statsProvider: PrivacyStatsTrackerDataProviding
    private let eventHandler: PrivacyStatsEventHandling
    
    func handle(message: Message) async throws -> Model {
        switch message.name {
        case "privacyStats_getData":
            return try await statsProvider.fetchStats()
            
        case "privacyStats_showDetails":
            await eventHandler.handleShowDetails()
            // Return current stats after event
            return try await statsProvider.fetchStats()
            
        default:
            throw ClientError.unhandledMessage
        }
    }
}
```

## Recent Activity Widget

### Complex Data Model
```swift
extension NewTabPageDataModel {
    struct RecentActivity: Codable {
        enum ItemType: String, Codable {
            case visit = "visit"
            case download = "download"
            case bookmark = "bookmark"
        }
        
        struct Item: Codable {
            let id: String
            let type: ItemType
            let title: String
            let url: URL?
            let timestamp: Date
            let metadata: [String: String]
        }
        
        let items: [Item]
        let hasMore: Bool
        let lastClearedDate: Date?
    }
}
```

### Visibility Control
```swift
// ✅ CORRECT - Widget visibility provider
protocol NewTabPageRecentActivityVisibilityProvider {
    var isVisible: Bool { get }
    func setVisibility(_ visible: Bool)
}

// Usage in client
final class NewTabPageRecentActivityClient {
    private let visibilityProvider: NewTabPageRecentActivityVisibilityProvider
    
    func handle(message: Message) async throws -> Model? {
        guard visibilityProvider.isVisible else {
            return nil // Widget hidden
        }
        // Handle message...
    }
}
```

## Remote Messages (RMF) Widget

### Active Message Provider
```swift
// ✅ CORRECT - Remote message integration
protocol NewTabPageActiveRemoteMessageProviding {
    func activeMessage() async -> RemoteMessage?
    func dismissMessage(_ id: String) async
    func recordImpression(_ id: String) async
}

final class NewTabPageRMFClient: NewTabPageClient {
    private let messageProvider: NewTabPageActiveRemoteMessageProviding
    
    func handle(message: Message) async throws -> Model {
        switch message.name {
        case "rmf_getData":
            if let activeMessage = await messageProvider.activeMessage() {
                await messageProvider.recordImpression(activeMessage.id)
                return NewTabPageDataModel.RemoteMessage(from: activeMessage)
            }
            return nil
            
        case "rmf_dismiss":
            let id = try message.decodeParam("id", as: String.self)
            await messageProvider.dismissMessage(id)
            return nil
            
        default:
            throw ClientError.unhandledMessage
        }
    }
}
```

## Testing Patterns

### 1. Capturing Mock Pattern
```swift
// ✅ CORRECT - Comprehensive capturing mock
final class CapturingNewTabPageFavoritesActionsHandler: NewTabPageFavoritesActionsHandler {
    // Capture all method calls
    var capturedAddFavoriteURLs: [URL] = []
    var capturedDeleteFavoriteIds: [String] = []
    var capturedReorderFavoriteIds: [[String]] = []
    var capturedOpenFavorites: [(url: URL, target: LinkOpenTarget)] = []
    
    // Control responses
    var addFavoriteError: Error?
    var deleteFavoriteError: Error?
    
    func handleAddFavorite(_ url: URL) async throws {
        capturedAddFavoriteURLs.append(url)
        if let error = addFavoriteError {
            throw error
        }
    }
    
    func handleDeleteFavorite(_ id: String) async throws {
        capturedDeleteFavoriteIds.append(id)
        if let error = deleteFavoriteError {
            throw error
        }
    }
    
    func handleReorderFavorites(_ ids: [String]) async throws {
        capturedReorderFavoriteIds.append(ids)
    }
    
    func handleOpenFavorite(_ url: URL, target: LinkOpenTarget) {
        capturedOpenFavorites.append((url, target))
    }
}
```

### 2. Message Test Helpers
```swift
// ✅ CORRECT - Type-safe message builders
extension Message {
    // Favorites messages
    static func favoritesGetData() -> Message {
        Message(name: "favorites_getData", params: [:])
    }
    
    static func favoritesAdd(url: URL) -> Message {
        Message(name: "favorites_add", params: ["url": url.absoluteString])
    }
    
    static func favoritesDelete(id: String) -> Message {
        Message(name: "favorites_delete", params: ["id": id])
    }
    
    static func favoritesReorder(ids: [String]) -> Message {
        Message(name: "favorites_reorder", params: ["ids": ids])
    }
    
    // Privacy stats messages
    static func privacyStatsGetData() -> Message {
        Message(name: "privacyStats_getData", params: [:])
    }
}
```

### 3. Mock Data Builders
```swift
// ✅ CORRECT - Test data builders
extension NewTabPageDataModel.Favorites {
    static var mock: Self {
        Self(
            items: [
                .init(id: "1", title: "DuckDuckGo", url: URL(string: "https://duckduckgo.com")!, domain: "duckduckgo.com", favicon: nil),
                .init(id: "2", title: "Example", url: URL(string: "https://example.com")!, domain: "example.com", favicon: nil)
            ],
            supportsReordering: true,
            maxItems: 12
        )
    }
}

extension NewTabPageDataModel.PrivacyStats {
    static var mock: Self {
        Self(
            trackersBlocked: 1234,
            adsBlocked: 567,
            companiesBlocked: ["Google", "Facebook", "Amazon"],
            estimatedTrackingAttemptsBlocked: 8901
        )
    }
}
```

### 4. Integration Testing
```swift
// ✅ CORRECT - Full widget integration test
func testFavoritesWidgetFullFlow() async throws {
    // Arrange
    let favoritesProvider = MockFavoritesProvider()
    let actionsHandler = CapturingNewTabPageFavoritesActionsHandler()
    let client = NewTabPageFavoritesClient(
        favoritesProvider: favoritesProvider,
        actionsHandler: actionsHandler
    )
    
    // Act - Get initial data
    let initialData = try await client.handle(message: .favoritesGetData())
    XCTAssertEqual(initialData.items.count, 2)
    
    // Act - Add favorite
    let newURL = URL(string: "https://new.example.com")!
    _ = try await client.handle(message: .favoritesAdd(url: newURL))
    
    // Assert
    XCTAssertEqual(actionsHandler.capturedAddFavoriteURLs, [newURL])
    XCTAssertEqual(favoritesProvider.fetchFavoritesCalls, 2)
}
```

## Performance Optimization

### 1. Debouncing Updates
```swift
// ✅ CORRECT - Debounced widget updates
final class NewTabPageActionsManager {
    private var updateTask: Task<Void, Never>?
    
    func scheduleWidgetUpdate(_ widget: Widget) {
        updateTask?.cancel()
        updateTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 100_000_000) // 100ms
            guard !Task.isCancelled else { return }
            await updateWidget(widget)
        }
    }
}
```

### 2. Caching Strategy
```swift
// ✅ CORRECT - Widget data caching
final class CachedWidgetDataProvider<T: Codable> {
    private var cache: (data: T, timestamp: Date)?
    private let cacheDuration: TimeInterval = 300 // 5 minutes
    
    func getData(fetcher: () async throws -> T) async throws -> T {
        if let cache = cache,
           Date().timeIntervalSince(cache.timestamp) < cacheDuration {
            return cache.data
        }
        
        let data = try await fetcher()
        cache = (data, Date())
        return data
    }
}
```