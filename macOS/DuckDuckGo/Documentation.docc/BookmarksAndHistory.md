# Bookmarks & History

Persistent storage, sync coordination, and cross-platform data models for browsing data.

## Overview

Bookmarks and history are fundamental features of the DuckDuckGo browser, providing users with ways to save and revisit their favorite sites and track their browsing activity. Both systems are built on Core Data, support cross-platform synchronization via Sync, and implement encryption for privacy protection.

The architecture separates concerns between the macOS-specific UI and interaction layers (``BookmarkManager``, ``HistoryCoordinating``) and shared cross-platform data models and sync logic that live in packages. This design enables code reuse between macOS and iOS while allowing platform-specific optimizations and UI patterns.

## Architecture

### Bookmarks Architecture

```
macOS UI Layer
├── BookmarkManager (protocol & LocalBookmarkManager)
├── BookmarkListViewController
└── BookmarkDragDropManager
    ↓
Storage Layer (Bookmarks package)
├── LocalBookmarkStore
├── BookmarkDatabase (CoreData)
└── Bookmark/BookmarkFolder models
    ↓
Sync Layer (BrowserServicesKit)
├── BookmarksProvider (SyncDataProvider)
├── BookmarksResponseHandler
└── Sync encryption & conflict resolution
```

### History Architecture

```
macOS UI Layer
├── HistoryCoordinator (coordinator protocol)
└── History views & controllers
    ↓
Coordinator Layer (BrowserServicesKit)
└── HistoryCoordinator
    ├── historyDictionary (in-memory cache)
    └── BrowsingHistory (structured output)
        ↓
Storage Layer
├── HistoryStoring protocol (BrowserServicesKit)
├── EncryptedHistoryStore (macOS)
└── BrowsingHistoryEntryManagedObject (CoreData)
```

### Cross-Platform Data Models

Both bookmarks and history use shared data models defined in packages:

- **Bookmark**: Core bookmark entity with URL, title, favorite status
- **BookmarkFolder**: Hierarchical folder structure
- **HistoryEntry**: URL visit with metadata and tracking info
- **Visit**: Individual page visit with timestamp

## Key Components

### Bookmarks - macOS Implementation

- ``BookmarkManager`` / ``LocalBookmarkManager`` — protocol defining CRUD operations and its concrete implementation, plus sync request coordination and search.
- ``BookmarkListViewController`` — main bookmarks sidebar UI with drag & drop and context menu actions.
- ``BookmarkDragDropManager`` — drag and drop coordination and pasteboard integration.

### Bookmarks - Shared Components

- ``LocalBookmarkStore`` — Core Data operations, transaction management, validation, and constraints.
- ``BookmarkDatabase`` — Core Data stack setup and migration management.
- ``BookmarksProvider`` — sync integration, conflict resolution, and response handling (in BrowserServicesKit).

### History - macOS Implementation

- ``HistoryCoordinator`` — in-memory history dictionary management, visit tracking, periodic cleaning, and published updates via Combine. Defined in BrowserServicesKit and used by the macOS app.
- ``EncryptedHistoryStore`` — macOS-specific encrypted storage with Core Data context management and encryption/decryption of URLs and titles.

### History - Shared Components

- ``HistoryStoring`` — history storage protocol covering Core Data operations and visit persistence.
- ``HistoryEntry`` — history entry model with visit tracking and tracker statistics.

### Tab Extensions

- ``HistoryTabExtension`` — per-tab history tracking that integrates with ``HistoryCoordinator`` and handles navigation events.

## Common Tasks

### Using BookmarkManager

The ``BookmarkManager`` protocol provides CRUD operations (`makeBookmark`, `makeFolder`, `move`, `search`, `isUrlBookmarked`) and triggers sync after mutations. Refer to the protocol in the Bookmarks package for the complete API and parameter shapes.

### Using HistoryCoordinator

The ``HistoryCoordinating`` protocol provides visit tracking (`addVisit`), privacy data (`addBlockedTracker`, `updateTitleIfNeeded`), and history queries (`history`, `allHistoryVisits`). Refer to the protocol in BrowserServicesKit for the complete API.

## Patterns & Best Practices

### Sync Integration

Both bookmarks and history trigger sync after modifications. ``BookmarkManager`` calls `requestSync()` after successful operations, which notifies the sync service. Best practices:
- Always call sync after successful data modifications
- Let the sync scheduler decide when to actually sync
- Handle sync conflicts at the data provider level (``BookmarksProvider``)
- Use timestamps to resolve conflicts (last-write-wins for most fields)

### Undo Support

Bookmarks support undo/redo operations. Pass an `UndoManager` to mutation methods like `remove(bookmark:undoManager:)` and `restore(_:undoManager:)`. The manager registers undo operations with entity snapshots.

### Core Data Threading

Both systems use Core Data with proper concurrency:
- Use `.privateQueueConcurrencyType` for background operations
- Always call `context.perform()` or `context.performAndWait()`
- Don't pass managed objects between threads — use object IDs

See ``LocalBookmarkStore`` and ``HistoryStoring`` implementations for patterns.

### History Memory Management

``HistoryCoordinator`` maintains an in-memory dictionary for performance (O(1) lookup) and reactive updates via Combine. Subscribe to `historyDictionaryPublisher` for change notifications. The coordinator handles periodic persistence to Core Data and regular cleaning.

### Encryption (macOS History)

History is encrypted at rest on macOS via ``EncryptedHistoryStore``. Encryption happens transparently in the store layer using system keychain-managed keys and Core Data transformers.

## Data Models

Data models are defined in packages:

- ``Bookmark`` — URL, title, favorite status (inherits from `BaseBookmarkEntity`)
- ``BookmarkFolder`` — hierarchical folder with children array
- ``HistoryEntry`` — URL visit with metadata, tracker statistics, and visits array
- ``Visit`` — individual page visit with timestamp

Refer to the Bookmarks and BrowserServicesKit package documentation for the complete definitions.

## Sync Coordination

### Bookmark Sync Flow

1. **Local Change**: User adds/modifies/deletes bookmark
2. **Persist to Core Data**: ``LocalBookmarkStore`` saves change
3. **Request Sync**: ``BookmarkManager`` notifies sync service via `requestSync()`
4. **Sync Scheduler**: Determines when to sync (debounces rapid changes)
5. **BookmarksProvider**: Prepares syncable entities
6. **Encryption**: Sensitive data encrypted before transmission
7. **Server Communication**: Sync engine sends/receives data
8. **Response Handling**: ``BookmarksResponseHandler`` processes server response
9. **Conflict Resolution**: Merge conflicts using timestamps and rules
10. **Apply Changes**: Update local Core Data with merged state

### Conflict Resolution Strategy

- **Bookmarks**: Last-write-wins based on `modifiedAt` timestamp
- **Deletions**: Tombstones prevent resurrection of deleted items
- **Favorites**: User intent (favorite toggle) takes precedence
- **Folders**: Structural changes reconciled carefully to maintain hierarchy

## Testing

Test bookmarks and history using mock implementations of ``BookmarkStore`` and ``HistoryStoring`` to verify data persistence and retrieval.

## Related Topics

- <doc:TabManagement> - How tabs track history via HistoryTabExtension
- <doc:Sync> - Cross-platform sync architecture
- ``BookmarkManager`` - Bookmark management protocol
- ``HistoryCoordinating`` - History coordination protocol
- ``LocalBookmarkStore`` - Bookmark persistence
- ``EncryptedHistoryStore`` - Encrypted history storage
