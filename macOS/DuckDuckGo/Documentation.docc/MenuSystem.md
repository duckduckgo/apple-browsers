# Menu System

Application menu construction, dynamic updates, and action handling using AppKit patterns.

## Overview

The DuckDuckGo macOS browser uses a custom menu system built on AppKit's `NSMenu` and `NSMenuItem`. The `MainMenu` class constructs the entire menu bar structure, handles menu validation and updates, and coordinates with various app components to provide context-sensitive menu items and actions.

The menu system follows AppKit conventions while adding custom functionality like dynamic bookmark menus, history menus, and feature-flagged menu items. Menu actions are implemented through the responder chain and dedicated action classes.

## Architecture

```
MainMenu (NSMenu)
├── DuckDuckGo Menu (App menu)
├── File Menu
├── Edit Menu
├── View Menu
├── History Menu (HistoryMenu)
├── Bookmarks Menu (built inline in MainMenu)
├── Window Menu
├── Debug Menu (feature-flagged)
└── Help Menu

MainMenuActions (Action Handlers)
├── Navigation actions
├── Tab management actions
├── History actions
└── Fire button actions
```

### Key Components

- **Menu Construction**: Declarative menu building using builder pattern
- **Dynamic Menus**: Bookmarks and history menus update based on data
- **Validation**: Menu items enable/disable based on application state
- **Responder Chain**: Actions route through first responder
- **Feature Flags**: Conditional menu items based on feature flags

## Key Components

### Core Implementation

- ``MainMenu`` — main menu construction and management; menu item lifecycle, updates, and feature flag integration. The bookmarks menu is constructed inside ``MainMenu`` via a `buildBookmarksMenu` method rather than a separate type, and the resulting `NSMenu` is updated in place as bookmarks change.
- `MainMenuActions.swift` — `@objc` action methods declared as extensions on `AppDelegate`; responder chain integration and coordination with ``TabCollectionViewModel`` and other app components.

### Dynamic Menus

- ``HistoryMenu`` — history menu construction from `HistoryCoordinator` data; grouped by date with submenus and clear-history options.
- Bookmarks menu — constructed within ``MainMenu`` from ``BookmarkManager``; folders become submenus and favorites appear in a dedicated section. The menu rebuilds itself in response to bookmark store changes.

### Menu Item Extensions

- `NSMenuItemExtension` — builder pattern extensions providing a fluent API for menu construction and keyboard shortcut helpers.

## Common Tasks

### Adding a New Menu Item

Add menu items in ``MainMenu`` within the appropriate menu-building method (such as `buildFileMenu` or `buildEditMenu`). Use the builder pattern with `NSMenuItem` and assign actions with selectors targeting methods in `MainMenuActions.swift`.

### Implementing Menu Actions

Implement action methods as `@objc` functions on `AppDelegate` extensions in `MainMenuActions.swift`, taking an `Any?` sender. Access the window controller and tab collection through the responder chain.

### Adding Submenus

Create submenus by attaching an `NSMenu` to a parent `NSMenuItem`, building its items with the same fluent builder used in ``MainMenu``. Use `NSMenuItem.separator()` for dividers.

### Feature-Flagged Menu Items

Check the relevant feature flag through `FeatureFlagger` and return the menu item or `nil` to conditionally include items in the menu structure.

### Dynamic Menu Updates

Override ``MainMenu``'s `update()` to refresh menu-item state (hidden, enabled, title) based on application state.

### Menu Validation

Implement `validateMenuItem(_:)` in your view controller or action handler to enable or disable menu items based on current state.

Refer to ``MainMenu`` and `MainMenuActions.swift` for implementation patterns.

## Patterns & Best Practices

### Bookmark and History Menus

These menus rebuild dynamically by subscribing to data-change publishers from `BookmarkManager` and `HistoryCoordinator`. The bookmarks menu is built inline within ``MainMenu``; the history menu lives in ``HistoryMenu``.

## Topics

### Core

- ``MainMenu``
- ``HistoryMenu``

