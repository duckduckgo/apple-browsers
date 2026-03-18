# Lazy Menu Rebuild Design

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate expensive eager menu rebuilds on the main thread by deferring all menu population to `NSMenuDelegate.menuNeedsUpdate(_:)`, called by AppKit just before display.

**Architecture:** Dirty flags decouple data changes from menu mutation. Each menu (and submenu) holds a placeholder item and a delegate that populates items lazily on first open. Bookmark folder submenus use a small reusable delegate class that recurses lazily into nested folders.

**Tech Stack:** AppKit (`NSMenu`, `NSMenuDelegate`), Combine, Swift

**Affected files:**
- `macOS/DuckDuckGo/Menus/MainMenu.swift`
- `macOS/DuckDuckGo/NavigationBar/View/MoreOptionsMenu.swift`

---

## Context: Why this matters

Spindump analysis of a 127-second hang showed the main thread blocked in `[NSMenu setItemArray:]` → `_recursivelyNoteChangedIsInMainMenu:` (recursive AppKit tree walk) triggered by `bookmarkManager.listPublisher`. Under memory pressure the walk causes hundreds of page-fault / decompression cycles per second. The fix is to never mutate menus outside of `menuNeedsUpdate`.

---

## Core Pattern

The same three-part mechanism applies to every surface:

1. **Dirty flag** — when data changes, store the new data as a property and set a `Bool` flag. No menu mutation happens here.
2. **`menuNeedsUpdate(_:)`** — AppKit calls the menu's delegate just before display. Check the flag, rebuild if dirty, clear the flag.
3. **Placeholder item** — AppKit only shows the ▶ arrow and calls `menuNeedsUpdate` on a submenu if it has ≥ 1 item. Every lazy submenu is initialised with one invisible `NSMenuItem()` placeholder that gets replaced on first open.

---

## Surface 1: MainMenu bookmarks & favicons

### New properties on `MainMenu`

```swift
private var pendingFavoriteViewModels: [BookmarkViewModel] = []
private var pendingTopLevelViewModels: [BookmarkViewModel] = []
private var bookmarksMenuNeedsRebuild = false
private var bookmarkFaviconsNeedUpdate = false
```

### `subscribeToBookmarkList` (updated)

```swift
bookmarkListCancellable = bookmarkManager.listPublisher
    .compactMap { list -> ([BookmarkViewModel], [BookmarkViewModel])? in
        let favorites = list?.favoriteBookmarks.compactMap(BookmarkViewModel.init(entity:)) ?? []
        let topLevel  = list?.topLevelEntities.compactMap(BookmarkViewModel.init(entity:)) ?? []
        return (favorites, topLevel)
    }
    .sink { [weak self] favorites, topLevel in
        // MainActor guaranteed at delegate call site — no Task needed
        self?.pendingFavoriteViewModels = favorites
        self?.pendingTopLevelViewModels = topLevel
        self?.bookmarksMenuNeedsRebuild = true
    }
```

`receive(on: DispatchQueue.main)` is removed; `@MainActor` is enforced at the `menuNeedsUpdate` call site.

### `subscribeToFavicons` (updated)

```swift
faviconsCancellable = faviconManager.faviconsLoadedPublisher
    .sink { [weak self] loaded in
        guard loaded else { return }
        self?.bookmarkFaviconsNeedUpdate = true
    }
```

### `NSMenuDelegate` on `bookmarksMenu` and `favoritesMenu`

`MainMenu` already conforms to `NSMenuDelegate` in places. Add:

```swift
func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu === bookmarksMenu || menu === favoritesMenu else { return }

    if bookmarksMenuNeedsRebuild {
        updateBookmarksMenu(
            favoriteViewModels: pendingFavoriteViewModels,
            topLevelBookmarkViewModels: pendingTopLevelViewModels
        )
        bookmarksMenuNeedsRebuild = false
        bookmarkFaviconsNeedUpdate = false  // fresh rebuild includes latest favicons
    } else if bookmarkFaviconsNeedUpdate {
        updateFavicons(in: menu)
        bookmarkFaviconsNeedUpdate = false
    }
}
```

Set `bookmarksMenu.delegate = self` and `favoritesMenu.delegate = self` after the menus are created.

---

## Surface 2: Lazy bookmark folder submenus

### `LazyBookmarkFolderMenuDelegate`

New class, lives in `MainMenu.swift` or a small companion file:

```swift
final class LazyBookmarkFolderMenuDelegate: NSObject, NSMenuDelegate {
    private let children: [BookmarkViewModel]
    private var isPopulated = false

    init(children: [BookmarkViewModel]) {
        self.children = children
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isPopulated else { return }
        isPopulated = true
        menu.removeAllItems()  // removes the placeholder
        buildItems(in: menu)
    }

    private func buildItems(in menu: NSMenu) {
        let bookmarks = children.compactMap { $0.entity as? Bookmark }
        if bookmarks.count > 1 {
            menu.addItem(NSMenuItem(bookmarkViewModels: children))
            menu.addItem(.separator())
        }
        for viewModel in children {
            let item = NSMenuItem(bookmarkViewModel: viewModel)
            if let folder = viewModel.entity as? BookmarkFolder {
                let subMenu = NSMenu(title: folder.title)
                subMenu.addItem(NSMenuItem())  // placeholder
                let childViewModels = folder.children.map(BookmarkViewModel.init)
                let delegate = LazyBookmarkFolderMenuDelegate(children: childViewModels)
                subMenu.delegate = delegate
                item.submenu = subMenu
                // retain delegate — caller is responsible
            }
            menu.addItem(item)
        }
    }
}
```

### `updateBookmarksMenu` (updated, folder branch only)

```swift
// Strong references so NSMenu's weak delegate doesn't dangle
private var folderDelegates: [LazyBookmarkFolderMenuDelegate] = []

func updateBookmarksMenu(...) {
    folderDelegates.removeAll()  // clear stale delegates from previous rebuild

    // ... existing top-level item building logic ...

    // For each folder item, replace eager build with lazy:
    if let folder = viewModel.entity as? BookmarkFolder {
        let subMenu = NSMenu(title: folder.title)
        subMenu.addItem(NSMenuItem())  // placeholder
        let childViewModels = folder.children.map(BookmarkViewModel.init)
        let delegate = LazyBookmarkFolderMenuDelegate(children: childViewModels)
        subMenu.delegate = delegate
        folderDelegates.append(delegate)  // retain
        if !childViewModels.isEmpty {
            menuItem.submenu = subMenu
        }
    }
}
```

`LazyBookmarkFolderMenuDelegate.buildItems` also appends to a local array it passes down recursively so all nested delegates are retained in the same flat `folderDelegates` array on `MainMenu`.

---

## Surface 3: MoreOptionsMenu submenus

Each submenu class (`FeedbackSubMenu`, `ZoomSubMenu`, `PasswordSubMenu`, `HelpSubMenu`, email submenu) gets the same treatment:

### Pattern per submenu

```swift
final class ZoomSubMenu: NSMenu, NSMenuDelegate {
    // dependencies stored as properties
    private weak var tabCollectionViewModel: TabCollectionViewModel?
    private let target: AnyObject
    private let moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding
    private var isPopulated = false

    init(tabCollectionViewModel: TabCollectionViewModel,
         targetting target: AnyObject,
         moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding) {
        self.tabCollectionViewModel = tabCollectionViewModel
        self.target = target
        self.moreOptionsMenuIconsProvider = moreOptionsMenuIconsProvider
        super.init(title: UserText.zoom)
        addItem(NSMenuItem())   // placeholder
        delegate = self
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isPopulated else { return }
        isPopulated = true
        removeAllItems()
        updateMenuItems(...)   // existing item-building logic, unchanged
    }
}
```

For submenus that track **live state** (e.g. `ZoomSubMenu` reflects current page zoom), set `isPopulated = false` when the underlying value changes so the next open rebuilds with fresh data. The existing Combine subscriptions inside those submenus handle this.

### `MoreOptionsMenu.setupMenuItems` impact

`setupMenuItems()` stays structurally the same. Each submenu call (`ZoomSubMenu(...)`, `FeedbackSubMenu(...)`, etc.) now returns a lightweight shell with a placeholder. Construction of `MoreOptionsMenu` becomes very cheap.

---

## What is NOT changing

- `MainMenu.update()` — already called by AppKit just before main menu bar display; its individual `updateXxx` calls are lightweight (set title/isHidden) and don't call `setItemArray:`. No change needed.
- `MoreOptionsMenu` construction cadence — still created fresh on each button click. No caching introduced.
- Action handlers, pixels, accessibility identifiers — untouched.
