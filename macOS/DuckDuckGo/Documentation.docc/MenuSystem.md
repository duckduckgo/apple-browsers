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
- ``MainMenuActions`` — action method implementations; responder chain integration and coordination with ``FireCoordinator``, ``TabCollectionViewModel``, and other app components.

### Dynamic Menus

- ``HistoryMenu`` — history menu construction from ``HistoryCoordinator`` data; grouped by date with submenus and clear-history options.
- Bookmarks menu — constructed within ``MainMenu`` from ``BookmarkManager``; folders become submenus and favorites appear in a dedicated section. The menu rebuilds itself in response to bookmark store changes.

### Menu Item Extensions

- `NSMenuItem+Common` — builder pattern extensions providing a fluent API for menu construction and keyboard shortcut helpers.

## Common Tasks

### Adding a New Menu Item

Add menu items in ``MainMenu`` within the appropriate menu-building method (such as `buildFileMenu` or `buildEditMenu`). Use the builder pattern with `NSMenuItem` and assign actions with selectors targeting ``MainMenuActions``.

### Implementing Menu Actions

Implement action methods in ``MainMenuActions`` as `@objc` functions taking an `Any?` sender. Access the window controller and tab collection through the responder chain.

### Adding Submenus

Create submenus by attaching an `NSMenu` to a parent `NSMenuItem`, building its items with the same fluent builder used in ``MainMenu``. Use `NSMenuItem.separator()` for dividers.

### Feature-Flagged Menu Items

Check the relevant feature flag through ``FeatureFlagger`` and return the menu item or `nil` to conditionally include items in the menu structure.

### Dynamic Menu Updates

Override ``MainMenu``'s `update()` to refresh menu-item state (hidden, enabled, title) based on application state.

### Menu Validation

Implement `validateMenuItem(_:)` in your view controller or action handler to enable or disable menu items based on current state.

Refer to ``MainMenu`` and ``MainMenuActions`` for implementation patterns.

## Patterns & Best Practices

### Menu Builder Pattern

The codebase uses a fluent builder pattern (`NSMenu.buildItems {}`) for declarative menu construction. Benefits: clean structure, easy maintenance, optional items integrate cleanly (nil items ignored).

### Responder Chain Integration

Actions route through the responder chain using selectors. The action is sent to the first responder and travels up the chain until handled.

### Keyboard Shortcuts

Assign keyboard shortcuts using `keyEquivalent` and `withModifierMask()`. Common modifiers: `.command` (⌘), `.shift` (⇧), `.option` (⌥), `.control` (⌃).

### Separators

Use `NSMenuItem.separator()` for horizontal lines between menu item groups.

### Hidden vs. Nil Items

Use `nil` when a feature is not available at all. Use `isHidden` when temporarily unavailable.

### Menu Item State

Control menu item state with `isEnabled`, `state` (.on/.off for checkmarks), and `title` properties.

### Bookmark and History Menus

These menus rebuild dynamically by subscribing to data-change publishers from ``BookmarkManager`` and ``HistoryCoordinator``. The bookmarks menu is built inline within ``MainMenu``; the history menu lives in ``HistoryMenu``.

## Common Menu Structure

### DuckDuckGo Menu (App Menu)
- About DuckDuckGo
- Preferences
- Services
- Hide/Show
- Quit

### File Menu
- New Tab / Window
- Open File / Location
- Close Tab / Window
- Save / Print
- Email Page

### Edit Menu
- Undo / Redo
- Cut / Copy / Paste
- Find
- Speech

### View Menu
- Show/Hide Toolbar
- Show/Hide Bookmarks
- Zoom In / Out
- Enter Full Screen

### History Menu
- Back / Forward
- Home
- Recently Closed
- History entries (grouped by date)
- Clear History

### Bookmarks Menu
- Add Bookmark
- Manage Bookmarks
- Bookmarks Bar toggle
- Favorites
- Bookmark folders (as submenus)

### Window Menu
- Minimize
- Zoom
- Window list

### Debug Menu (Internal Only)
- Various debug options
- Feature flags
- Testing tools

## Testing

Test menu structure and feature-flagged items using mock dependencies. Use `NSMenu.item(withTitle:)` to verify menu item presence and properties.

## Related Topics

- ``MainMenuActions`` - Action implementations
- ``HistoryMenu`` - Dynamic history menu
- ``MainMenu`` - Hosts the inline bookmarks menu construction
- ``NSMenuItem`` - AppKit menu item class
- ``NSMenu`` - AppKit menu class

