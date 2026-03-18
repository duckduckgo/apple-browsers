# Lazy Menu Rebuild

## The Problem

A spindump from a user experiencing a 127-second hang revealed the following stack on the main thread:

```
swift_job_runImpl
  → DuckDuckGo (bookmarkManager.listPublisher sink)
    → [NSMenu setItemArray:]
      → _recursivelyNoteChangedIsInMainMenu:   ← deeply recursive
        → WKdm_decompress_new                  ← page fault / memory decompression
```

The user's process had a **7.66 GB memory footprint** — far exceeding physical RAM. macOS had compressed and paged out large portions of the menu tree. When `bookmarkManager.listPublisher` fired, the app called `[NSMenu setItemArray:]`, which triggered `_recursivelyNoteChangedIsInMainMenu:` — an internal AppKit walk that visits every item in every menu attached to the main menu bar. Under memory pressure, each node touched caused a page fault and a decompression cycle. With hundreds of nodes, this compounded into a full hang.

**Root cause:** The app was rebuilding the entire bookmark menu tree (including all nested folder submenus) eagerly on the main thread, outside of any AppKit menu lifecycle callback. `NSMenu.setItemArray:` is not just a data store — it synchronously walks the entire menu hierarchy to update internal state. Under normal memory conditions this is fast. Under pressure, it blocks indefinitely.

---

## The Solution: Lazy Menu Rebuild

The fix defers all menu population to `NSMenuDelegate.menuNeedsUpdate(_:)`, which AppKit calls on the main thread **just before a menu is displayed** — never proactively.

### Core pattern

Three pieces work together on every menu and submenu:

1. **Dirty flag** — when data changes (e.g. `listPublisher` fires), store the new data and set a `Bool` flag. No menu mutation happens here.
2. **`menuNeedsUpdate(_:)`** — AppKit calls the menu's delegate just before display. Check the flag, rebuild if dirty, clear the flag.
3. **Placeholder item** — AppKit only shows the ▶ disclosure arrow and calls `menuNeedsUpdate` on a submenu if it has ≥ 1 item. Every lazy submenu is initialised with one invisible `NSMenuItem()` placeholder that is replaced on first open.

### What changed

**Feature flag:** `lazyMenuRebuild` (`MacOSBrowserConfigSubfeature`), enabled by default, supports local override. All changes are gated behind it so the old path remains reachable.

**`MainMenu` — bookmarks and favicons:**
- `subscribeToBookmarkList` no longer calls `updateBookmarksMenu` directly. Instead it stores `pendingFavoriteViewModels` / `pendingTopLevelViewModels` and sets `bookmarksMenuNeedsRebuild = true`.
- `subscribeToFavicons` sets `bookmarkFaviconsNeedUpdate = true` instead of walking the menu tree.
- A new `menuNeedsUpdate(_:)` on `MainMenu` (its existing `NSMenuDelegate` conformance) handles both `bookmarksMenu` and `favoritesMenu`: full rebuild if dirty, favicon-only pass otherwise.
- `bookmarksMenu.delegate = self` and `favoritesMenu.delegate = self` are set at init time.

**`LazyBookmarkFolderMenuDelegate`:**
A new `NSObject & NSMenuDelegate` class handles folder submenus lazily. Each `BookmarkFolder` item gets a submenu with one placeholder item and this delegate. On first hover, `menuNeedsUpdate` fires, the placeholder is replaced with real items, and any nested folders get their own `LazyBookmarkFolderMenuDelegate` instances. Sub-delegates are retained in a `childDelegates` array on their parent (since `NSMenu.delegate` is a weak reference). Top-level folder delegates are retained in `MainMenu.folderDelegates`, cleared on each full rebuild.

**`MoreOptionsMenu` submenus:**
`FeedbackSubMenu`, `ZoomSubMenu`, `BookmarksSubMenu`, `LoginsSubMenu`, and `HelpSubMenu` each gained `NSMenuDelegate` conformance and an `isPopulated` flag. Construction is now a cheap shell (one placeholder item); item building runs in `menuNeedsUpdate` on first hover. `MoreOptionsMenu` is already created fresh on every button click, so no caching was introduced.

---

## Approaches We Considered But Didn't Use

### Debounce on `listPublisher`

Adding `.debounce(for: .milliseconds(300), scheduler: DispatchQueue.main)` to the `bookmarkManager.listPublisher` pipeline would reduce the number of times `updateBookmarksMenu` fires during rapid edits, but does nothing about the cost of each rebuild. Under memory pressure a single `setItemArray:` call is enough to hang the app. Debouncing delays the pain, it doesn't remove it.

### Background thread item building

Build `NSMenuItem` objects on a background thread, then swap them onto the main thread via `setItemArray:`. This doesn't help — `_recursivelyNoteChangedIsInMainMenu:` fires on whatever thread calls `setItemArray:`, and all AppKit work must happen on the main thread anyway. The bottleneck is the recursive walk triggered by attaching items to a live main menu, not the construction of the items themselves.

### Caching `MoreOptionsMenu`

Reuse the same `MoreOptionsMenu` instance across button clicks instead of constructing a new one each time. This would require invalidating state on tab changes, navigation, and subscription changes. The lazy delegate approach is strictly better: construction remains cheap, and stale-state bugs are avoided entirely because the menu is still fresh on each click.

### Hard cap with overflow item

Cap the bookmark menu at N items (e.g. 150) and append a "Show all bookmarks in manager" item. This would eliminate the problem for users with large collections but degrades the feature. It was noted as a future escape hatch if the lazy approach proves insufficient at extreme scale (the spindump user had 30k+ bookmarks and slow performance was still observed after this fix, since building 30k top-level `NSMenuItem` objects synchronously in `menuNeedsUpdate` still blocks the main thread).

### Async build with loading placeholder

Show a "Loading bookmarks…" disabled item immediately, dispatch the real build to a background thread, then swap items once ready. AppKit menus don't officially support being mutated while displayed. Swapping items on a live open menu produces undefined visual behaviour and is difficult to test reliably. Rejected in favour of the simpler synchronous lazy approach.
