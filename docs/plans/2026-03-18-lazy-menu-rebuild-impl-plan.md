# Lazy Menu Rebuild Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Eliminate expensive eager menu rebuilds on the main thread by deferring all menu population to `NSMenuDelegate.menuNeedsUpdate(_:)`, called by AppKit just before display.

**Architecture:** Dirty flags decouple data changes from menu mutation. Each menu (and submenu) holds a placeholder item and a delegate that populates items lazily on first open. All changes are gated behind a `lazyMenuRebuild` feature flag enabled by default.

**Tech Stack:** AppKit (`NSMenu`, `NSMenuDelegate`), Combine, Swift

**Affected files:**
- `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift`
- `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift`
- `macOS/DuckDuckGo/Menus/MainMenu.swift`
- `macOS/DuckDuckGo/NavigationBar/View/MoreOptionsMenu.swift`
- `macOS/UnitTests/Menus/MainMenuTests.swift`

---

## Task 1: Add `lazyMenuRebuild` feature flag

**Files:**
- Modify: `SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift:183`
- Modify: `macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift:299`

### Step 1: Add the subfeature case to `MacOSBrowserConfigSubfeature`

In `PrivacyFeature.swift`, after line 183 (`case tabAnimations`), add:

```swift
    case lazyMenuRebuild
```

Result (lines 181-185):
```swift
    case semaphoreAlwaysVisible

    case tabAnimations

    case lazyMenuRebuild
}
```

### Step 2: Add the flag case to `FeatureFlag`

In `FeatureFlag.swift`, after line 299 (`case tabAnimations`), add:

```swift
    /// Defers menu population to NSMenuDelegate.menuNeedsUpdate(_:) to avoid expensive eager rebuilds
    case lazyMenuRebuild
```

### Step 3: Add to `defaultValue` — `.enabled` group

In `FeatureFlag.swift`, extend the `.enabled` case group (currently ends at `.promoQueue` on line 331):

```swift
        case .supportsAlternateStripePaymentFlow,
                .refactorOfSyncPreferences,
                // ... existing cases ...
                .promoQueue,
                .lazyMenuRebuild:
            .enabled
```

### Step 4: Add to `supportsLocalOverriding` — `return true` group

In `FeatureFlag.swift`, extend the `return true` case group (currently ends at `.tabAnimations` on line 433):

```swift
                .semaphoreAlwaysVisible,
                .tabAnimations,
                .lazyMenuRebuild:
            return true
```

### Step 5: Add to `source` switch

In `FeatureFlag.swift`, after line 618 (`case .tabAnimations: return .remoteReleasable(...)`), add:

```swift
        case .lazyMenuRebuild:
            return .remoteReleasable(.subfeature(MacOSBrowserConfigSubfeature.lazyMenuRebuild))
```

### Step 6: Build to verify

```bash
cd /Users/juanpereira/Repositories/apple-browsers
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" build 2>&1 | grep -E "error:|Build succeeded"
```

Expected: `Build succeeded`

### Step 7: Commit

```bash
git add SharedPackages/BrowserServicesKit/Sources/PrivacyConfig/Features/PrivacyFeature.swift
git add macOS/LocalPackages/FeatureFlags/Sources/FeatureFlags/FeatureFlag.swift
git commit -m "feat: add lazyMenuRebuild feature flag (enabled by default)"
```

---

## Task 2: Add `LazyBookmarkFolderMenuDelegate`

**Files:**
- Modify: `macOS/DuckDuckGo/Menus/MainMenu.swift`

This class handles lazy population of bookmark folder submenus. It will be added above the `MainMenu` class definition.

### Step 1: Write the failing test

In `macOS/UnitTests/Menus/MainMenuTests.swift`, add a new test class:

```swift
final class LazyBookmarkFolderMenuDelegateTests: XCTestCase {

    func testMenuIsEmptyBeforeFirstOpen() {
        let folder = BookmarkFolder(id: "1", title: "Folder")
        let bookmark = Bookmark(id: "2", url: "https://example.com", title: "Example", isFavorite: false)
        folder.children = [bookmark]
        let viewModels = [BookmarkViewModel(entity: bookmark)]

        let delegate = LazyBookmarkFolderMenuDelegate(children: viewModels)
        let menu = NSMenu()
        menu.addItem(NSMenuItem()) // placeholder
        menu.delegate = delegate

        // Before menuNeedsUpdate is called, menu still has the placeholder
        XCTAssertEqual(menu.items.count, 1)
    }

    func testMenuIsPopulatedAfterFirstOpen() {
        let bookmark = Bookmark(id: "2", url: "https://example.com", title: "Example", isFavorite: false)
        let viewModels = [BookmarkViewModel(entity: bookmark)]

        let delegate = LazyBookmarkFolderMenuDelegate(children: viewModels)
        let menu = NSMenu()
        menu.addItem(NSMenuItem()) // placeholder
        menu.delegate = delegate

        delegate.menuNeedsUpdate(menu)

        XCTAssertFalse(menu.items.isEmpty)
        XCTAssertEqual(menu.items.first?.title, "Example")
    }

    func testMenuIsNotRebuiltOnSecondOpen() {
        let bookmark = Bookmark(id: "2", url: "https://example.com", title: "Example", isFavorite: false)
        let viewModels = [BookmarkViewModel(entity: bookmark)]

        let delegate = LazyBookmarkFolderMenuDelegate(children: viewModels)
        let menu = NSMenu()
        menu.addItem(NSMenuItem()) // placeholder
        menu.delegate = delegate

        delegate.menuNeedsUpdate(menu)
        let countAfterFirst = menu.items.count

        // Mutate menu to detect if rebuild happens
        menu.addItem(NSMenuItem(title: "extra", action: nil, keyEquivalent: ""))
        delegate.menuNeedsUpdate(menu)

        // Should not have been rebuilt (extra item still present)
        XCTAssertEqual(menu.items.count, countAfterFirst + 1)
    }

    func testFolderChildrenGetLazySubmenus() {
        let folder = BookmarkFolder(id: "1", title: "Sub")
        let childBookmark = Bookmark(id: "3", url: "https://sub.com", title: "Sub", isFavorite: false)
        folder.children = [childBookmark]
        let folderViewModel = BookmarkViewModel(entity: folder)

        let delegate = LazyBookmarkFolderMenuDelegate(children: [folderViewModel])
        let menu = NSMenu()
        menu.addItem(NSMenuItem()) // placeholder
        menu.delegate = delegate

        delegate.menuNeedsUpdate(menu)

        let folderItem = menu.items.first { $0.submenu != nil }
        XCTAssertNotNil(folderItem, "Folder item should have a submenu")
        XCTAssertEqual(folderItem?.submenu?.items.count, 1, "Submenu should have the placeholder item")
        XCTAssertNotNil(folderItem?.submenu?.delegate, "Submenu should have a lazy delegate")
    }
}
```

### Step 2: Run to verify test fails

```bash
xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" -only-testing "UnitTests/LazyBookmarkFolderMenuDelegateTests" 2>&1 | grep -E "error:|FAILED|PASSED|Build succeeded"
```

Expected: compile error — `LazyBookmarkFolderMenuDelegate` does not exist yet.

### Step 3: Add `LazyBookmarkFolderMenuDelegate` to `MainMenu.swift`

Insert before the `final class MainMenu` declaration. Find a suitable place above `MainMenu` (e.g., after the import block, before `// MARK: - MainMenu`).

```swift
// MARK: - LazyBookmarkFolderMenuDelegate

final class LazyBookmarkFolderMenuDelegate: NSObject, NSMenuDelegate {
    private let children: [BookmarkViewModel]
    private var isPopulated = false

    init(children: [BookmarkViewModel]) {
        self.children = children
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isPopulated else { return }
        isPopulated = true
        menu.removeAllItems() // removes the placeholder
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
                subMenu.addItem(NSMenuItem()) // placeholder
                let childViewModels = folder.children.map(BookmarkViewModel.init)
                let delegate = LazyBookmarkFolderMenuDelegate(children: childViewModels)
                subMenu.delegate = delegate
                item.submenu = subMenu
            }
            menu.addItem(item)
        }
    }
}
```

### Step 4: Run tests to verify they pass

```bash
xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" -only-testing "UnitTests/LazyBookmarkFolderMenuDelegateTests" 2>&1 | grep -E "error:|FAILED|PASSED|Build succeeded"
```

Expected: All 4 tests PASSED.

### Step 5: Commit

```bash
git add macOS/DuckDuckGo/Menus/MainMenu.swift macOS/UnitTests/Menus/MainMenuTests.swift
git commit -m "feat: add LazyBookmarkFolderMenuDelegate for lazy folder submenu population"
```

---

## Task 3: Lazy MainMenu bookmarks and favicons

**Files:**
- Modify: `macOS/DuckDuckGo/Menus/MainMenu.swift`
- Test: `macOS/UnitTests/Menus/MainMenuTests.swift`

This task converts `subscribeToBookmarkList` and `subscribeToFavicons` to use dirty flags, and wires `NSMenuDelegate.menuNeedsUpdate(_:)` on `bookmarksMenu` and `favoritesMenu`. All of this is gated behind the `lazyMenuRebuild` feature flag.

### Step 1: Write failing tests

In `MainMenuTests.swift`, add a new `LazyMainMenuBookmarksTests` class. You will need a test `MainMenu` instance that exposes the relevant internals — use `@testable import DuckDuckGo`.

```swift
@testable import DuckDuckGo

final class LazyMainMenuBookmarksTests: XCTestCase {

    @MainActor
    func testBookmarksMenuNeedsRebuildFlagSetOnListChange() {
        // Given a MainMenu with lazyMenuRebuild flag enabled
        let menu = makeMainMenu(lazyMenuEnabled: true)
        XCTAssertFalse(menu.bookmarksMenuNeedsRebuild)

        // When the bookmark list publisher fires
        menu.simulateBookmarkListChange(favorites: [], topLevel: [])

        // Then the flag is set and no menu mutation has happened
        XCTAssertTrue(menu.bookmarksMenuNeedsRebuild)
    }

    @MainActor
    func testMenuNeedsUpdateRebuildsAndClearsFlag() {
        let menu = makeMainMenu(lazyMenuEnabled: true)
        menu.simulateBookmarkListChange(favorites: [], topLevel: [])

        // When menuNeedsUpdate fires (simulating AppKit about to display menu)
        menu.menuNeedsUpdate(menu.bookmarksMenu)

        XCTAssertFalse(menu.bookmarksMenuNeedsRebuild)
    }

    @MainActor
    func testFaviconUpdateFlagSetOnFaviconsLoaded() {
        let menu = makeMainMenu(lazyMenuEnabled: true)
        // Populate the menu first so favicon update is meaningful
        menu.simulateBookmarkListChange(favorites: [], topLevel: [])
        menu.menuNeedsUpdate(menu.bookmarksMenu)
        XCTAssertFalse(menu.bookmarkFaviconsNeedUpdate)

        menu.simulateFaviconsLoaded()

        XCTAssertTrue(menu.bookmarkFaviconsNeedUpdate)
    }

    @MainActor
    func testFlagNotSetWhenLazyDisabled() {
        let menu = makeMainMenu(lazyMenuEnabled: false)
        // With flag off, the old eager path runs — no dirty flag should be set
        menu.simulateBookmarkListChange(favorites: [], topLevel: [])
        XCTAssertFalse(menu.bookmarksMenuNeedsRebuild)
    }

    // MARK: Helpers

    @MainActor
    private func makeMainMenu(lazyMenuEnabled: Bool) -> MainMenu {
        let featureFlagger = MockFeatureFlagger()
        featureFlagger.enabledFlags = lazyMenuEnabled ? [.lazyMenuRebuild] : []
        // Construct with test doubles — use existing test helpers in MainMenuTests.swift
        return MainMenu(featureFlagger: featureFlagger, /* ... other test doubles ... */)
    }
}
```

> **Note:** Look at existing `MainMenuTests.swift` for how `MainMenu` is constructed in tests. Use the same factory/test doubles. The key things to expose for testing are `bookmarksMenuNeedsRebuild`, `bookmarkFaviconsNeedUpdate`, and `simulateBookmarkListChange` — add these as `internal` test hooks (or use `@testable` to access `internal` properties directly).

### Step 2: Run to verify tests fail

```bash
xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" -only-testing "UnitTests/LazyMainMenuBookmarksTests" 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: compile error — `bookmarksMenuNeedsRebuild` and other new properties don't exist yet.

### Step 3: Add dirty-flag properties to `MainMenu`

In `MainMenu.swift`, near the bookmark-related properties (around the `// MARK: - Bookmarks` comment, line 571), add:

```swift
// MARK: - Lazy rebuild state
private(set) var pendingFavoriteViewModels: [BookmarkViewModel] = []
private(set) var pendingTopLevelViewModels: [BookmarkViewModel] = []
private(set) var bookmarksMenuNeedsRebuild = false
private(set) var bookmarkFaviconsNeedUpdate = false
```

(`private(set)` makes them readable in tests via `@testable import`.)

### Step 4: Update `subscribeToBookmarkList`

Replace the body of `subscribeToBookmarkList` (lines 599-612) to branch on the flag:

```swift
private func subscribeToBookmarkList(bookmarkManager: BookmarkManager) {
    bookmarkListCancellable = bookmarkManager.listPublisher
        .compactMap {
            let favorites = $0?.favoriteBookmarks.compactMap(BookmarkViewModel.init(entity:)) ?? []
            let topLevelEntities = $0?.topLevelEntities.compactMap(BookmarkViewModel.init(entity:)) ?? []
            return (favorites, topLevelEntities)
        }
        .sink { [weak self] favorites, topLevel in
            guard let self else { return }
            if self.featureFlagger.isFeatureOn(.lazyMenuRebuild) {
                self.pendingFavoriteViewModels = favorites
                self.pendingTopLevelViewModels = topLevel
                self.bookmarksMenuNeedsRebuild = true
            } else {
                Task { @MainActor in
                    self.updateBookmarksMenu(favoriteViewModels: favorites,
                                             topLevelBookmarkViewModels: topLevel)
                }
            }
        }
}
```

### Step 5: Update `subscribeToFavicons`

Replace the body of `subscribeToFavicons` (lines 575-584) to branch on the flag:

```swift
@MainActor
private func subscribeToFavicons(faviconManager: FaviconManagement) {
    faviconsCancellable = faviconManager.faviconsLoadedPublisher
        .receive(on: DispatchQueue.main)
        .sink { [weak self] loaded in
            guard let self, loaded else { return }
            if self.featureFlagger.isFeatureOn(.lazyMenuRebuild) {
                self.bookmarkFaviconsNeedUpdate = true
            } else {
                self.updateFavicons(in: bookmarksMenu)
                self.updateFavicons(in: favoritesMenu)
            }
        }
}
```

### Step 6: Add `menuNeedsUpdate` for bookmark menus

`MainMenu` already conforms to `NSMenuDelegate`. Add this implementation to the existing `NSMenuDelegate` extension (search for `extension MainMenu: NSMenuDelegate` in the file):

```swift
func menuNeedsUpdate(_ menu: NSMenu) {
    // Handle other menus that already have delegate handling first
    // ... (existing menuNeedsUpdate body if any) ...

    guard menu === bookmarksMenu || menu === favoritesMenu else { return }

    if bookmarksMenuNeedsRebuild {
        updateBookmarksMenu(
            favoriteViewModels: pendingFavoriteViewModels,
            topLevelBookmarkViewModels: pendingTopLevelViewModels
        )
        bookmarksMenuNeedsRebuild = false
        bookmarkFaviconsNeedUpdate = false
    } else if bookmarkFaviconsNeedUpdate {
        updateFavicons(in: menu)
        bookmarkFaviconsNeedUpdate = false
    }
}
```

> **Note:** If `MainMenu` already has a `menuNeedsUpdate` method, add the bookmark handling inside it rather than creating a duplicate. Use `guard menu === bookmarksMenu || menu === favoritesMenu else { return }` at the top of the new block, or merge with the existing guard.

### Step 7: Wire delegates after menu creation

Find where `bookmarksMenu` and `favoritesMenu` are created/configured in `MainMenu` (search for `bookmarksMenu` in `init` or setup methods). Add:

```swift
if featureFlagger.isFeatureOn(.lazyMenuRebuild) {
    bookmarksMenu.delegate = self
    favoritesMenu.delegate = self
    bookmarksMenu.addItem(NSMenuItem()) // placeholder so AppKit shows ▶ arrow
    favoritesMenu.addItem(NSMenuItem()) // placeholder
}
```

Place this after the menus are created but before subscriptions are attached.

### Step 8: Update `updateBookmarksMenu` to use lazy folder delegates (when flag is on)

In `updateBookmarksMenu`, add a storage property at the top of `MainMenu`:

```swift
private var folderDelegates: [LazyBookmarkFolderMenuDelegate] = []
```

At the start of `updateBookmarksMenu`, add:

```swift
if featureFlagger.isFeatureOn(.lazyMenuRebuild) {
    folderDelegates.removeAll()
}
```

In the folder-building branch inside `bookmarkMenuItems(from:topLevel:)` (lines 641-650), add a conditional path when the flag is on:

```swift
if let folder = viewModel.entity as? BookmarkFolder {
    if featureFlagger.isFeatureOn(.lazyMenuRebuild) {
        let subMenu = NSMenu(title: folder.title)
        subMenu.addItem(NSMenuItem()) // placeholder
        let childViewModels = folder.children.map(BookmarkViewModel.init)
        if !childViewModels.isEmpty {
            let delegate = LazyBookmarkFolderMenuDelegate(children: childViewModels)
            subMenu.delegate = delegate
            folderDelegates.append(delegate)
            menuItem.submenu = subMenu
        }
    } else {
        // existing eager path
        let subMenu = NSMenu(title: folder.title)
        let childViewModels = folder.children.map(BookmarkViewModel.init)
        let childMenuItems = bookmarkMenuItems(from: childViewModels, topLevel: false)
        subMenu.items = childMenuItems
        if !subMenu.items.isEmpty {
            menuItem.submenu = subMenu
        }
    }
}
```

> **Note:** `bookmarkMenuItems` is a nested function inside `updateBookmarksMenu`. Because it's nested it can't directly access `self.featureFlagger` without capturing it. Refactor: extract `bookmarkMenuItems` to a method on `MainMenu` so it can access `self.featureFlagger` and `self.folderDelegates`.

### Step 9: Run tests to verify they pass

```bash
xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" -only-testing "UnitTests/LazyMainMenuBookmarksTests" 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: All tests PASSED.

### Step 10: Build full project

```bash
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" build 2>&1 | grep -E "error:|Build succeeded"
```

### Step 11: Commit

```bash
git add macOS/DuckDuckGo/Menus/MainMenu.swift macOS/UnitTests/Menus/MainMenuTests.swift
git commit -m "feat: lazy bookmark menu rebuild via NSMenuDelegate and dirty flags"
```

---

## Task 4: Lazy MoreOptionsMenu submenus

**Files:**
- Modify: `macOS/DuckDuckGo/NavigationBar/View/MoreOptionsMenu.swift`
- Test: `macOS/UnitTests/Menus/MainMenuTests.swift` (or a new `MoreOptionsMenuTests.swift`)

Each submenu class (`FeedbackSubMenu`, `ZoomSubMenu`, `LoginsSubMenu`, `HelpSubMenu`, `BookmarksSubMenu`) gets `NSMenuDelegate` conformance with an `isPopulated` guard. Construction becomes a lightweight shell; `updateMenuItems` runs in `menuNeedsUpdate`. All guarded by `featureFlagger.isFeatureOn(.lazyMenuRebuild)` passed through from `MoreOptionsMenu`.

### Step 1: Write failing tests

Create `macOS/UnitTests/Menus/MoreOptionsMenuTests.swift` (or append to existing test file):

```swift
@testable import DuckDuckGo

final class LazyMoreOptionsMenuTests: XCTestCase {

    @MainActor
    func testFeedbackSubMenuIsEmptyBeforeOpen() {
        let featureFlagger = MockFeatureFlagger(enabledFlags: [.lazyMenuRebuild])
        let menu = FeedbackSubMenu(targetting: NSObject(),
                                   authenticationStateProvider: MockSubscriptionAuthStateProvider(),
                                   internalUserDecider: MockInternalUserDecider(),
                                   moreOptionsMenuIconsProvider: MockMoreOptionsMenuIconsProvider(),
                                   featureFlagger: featureFlagger)

        XCTAssertEqual(menu.items.count, 1, "Should only contain placeholder before first open")
    }

    @MainActor
    func testFeedbackSubMenuIsPopulatedAfterOpen() {
        let featureFlagger = MockFeatureFlagger(enabledFlags: [.lazyMenuRebuild])
        let menu = FeedbackSubMenu(targetting: NSObject(),
                                   authenticationStateProvider: MockSubscriptionAuthStateProvider(),
                                   internalUserDecider: MockInternalUserDecider(),
                                   moreOptionsMenuIconsProvider: MockMoreOptionsMenuIconsProvider(),
                                   featureFlagger: featureFlagger)

        menu.menuNeedsUpdate(menu)

        XCTAssertGreaterThan(menu.items.count, 1)
    }

    @MainActor
    func testFeedbackSubMenuIsNotRebuiltOnSecondOpen() {
        let featureFlagger = MockFeatureFlagger(enabledFlags: [.lazyMenuRebuild])
        let menu = FeedbackSubMenu(targetting: NSObject(),
                                   authenticationStateProvider: MockSubscriptionAuthStateProvider(),
                                   internalUserDecider: MockInternalUserDecider(),
                                   moreOptionsMenuIconsProvider: MockMoreOptionsMenuIconsProvider(),
                                   featureFlagger: featureFlagger)

        menu.menuNeedsUpdate(menu)
        let countAfterFirst = menu.items.count

        menu.addItem(NSMenuItem(title: "sentinel", action: nil, keyEquivalent: ""))
        menu.menuNeedsUpdate(menu) // should be a no-op

        XCTAssertEqual(menu.items.count, countAfterFirst + 1, "Sentinel should still be present")
    }

    @MainActor
    func testFeedbackSubMenuEagerlyBuiltWhenFlagOff() {
        let featureFlagger = MockFeatureFlagger(enabledFlags: [])
        let menu = FeedbackSubMenu(targetting: NSObject(),
                                   authenticationStateProvider: MockSubscriptionAuthStateProvider(),
                                   internalUserDecider: MockInternalUserDecider(),
                                   moreOptionsMenuIconsProvider: MockMoreOptionsMenuIconsProvider(),
                                   featureFlagger: featureFlagger)

        // When flag is off, init builds eagerly — items present without calling menuNeedsUpdate
        XCTAssertGreaterThan(menu.items.count, 1)
    }
}
```

> Repeat for `ZoomSubMenu`, `LoginsSubMenu`, `HelpSubMenu` with their respective init signatures (see below).

### Step 2: Run to verify tests fail

```bash
xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" -only-testing "UnitTests/LazyMoreOptionsMenuTests" 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: compile error — `menuNeedsUpdate` not yet implemented.

### Step 3: Convert `FeedbackSubMenu`

Current init (line 878):
```swift
init(targetting target: AnyObject,
     authenticationStateProvider: ...,
     internalUserDecider: ...,
     moreOptionsMenuIconsProvider: ...,
     featureFlagger: FeatureFlagger) {
    // ...
    super.init(title: UserText.sendFeedback)
    updateMenuItems(targetting: target, featureFlagger: featureFlagger, ...)
}
```

New implementation (add `NSMenuDelegate` conformance and `isPopulated`):

```swift
final class FeedbackSubMenu: NSMenu, NSMenuDelegate {
    private let authenticationStateProvider: any SubscriptionAuthenticationStateProvider
    private let internalUserDecider: InternalUserDecider
    private let featureFlagger: FeatureFlagger
    private weak var target: AnyObject?
    private var moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding
    private var isPopulated = false

    init(targetting target: AnyObject,
         authenticationStateProvider: any SubscriptionAuthenticationStateProvider,
         internalUserDecider: InternalUserDecider,
         moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding,
         featureFlagger: FeatureFlagger) {
        self.authenticationStateProvider = authenticationStateProvider
        self.internalUserDecider = internalUserDecider
        self.featureFlagger = featureFlagger
        self.target = target
        self.moreOptionsMenuIconsProvider = moreOptionsMenuIconsProvider
        super.init(title: UserText.sendFeedback)

        if featureFlagger.isFeatureOn(.lazyMenuRebuild) {
            addItem(NSMenuItem()) // placeholder
            delegate = self
        } else {
            updateMenuItems(targetting: target,
                            featureFlagger: featureFlagger,
                            moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isPopulated else { return }
        isPopulated = true
        removeAllItems()
        guard let target else { return }
        updateMenuItems(targetting: target,
                        featureFlagger: featureFlagger,
                        moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider)
    }

    // ... existing updateMenuItems and other methods unchanged ...
}
```

### Step 4: Convert `ZoomSubMenu`

`ZoomSubMenu` (line 955) currently stores no dependencies. Add stored properties for everything `updateMenuItems` needs:

```swift
final class ZoomSubMenu: NSMenu, NSMenuDelegate {
    private weak var tabCollectionViewModel: TabCollectionViewModel?
    private weak var target: AnyObject?
    private let moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding
    private let featureFlagger: FeatureFlagger
    private var isPopulated = false
    private var zoomItems: [NSMenuItem] = []

    @MainActor
    init(targetting target: AnyObject,
         tabCollectionViewModel: TabCollectionViewModel,
         moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding,
         featureFlagger: FeatureFlagger) {
        self.target = target
        self.tabCollectionViewModel = tabCollectionViewModel
        self.moreOptionsMenuIconsProvider = moreOptionsMenuIconsProvider
        self.featureFlagger = featureFlagger
        super.init(title: UserText.zoom)

        if featureFlagger.isFeatureOn(.lazyMenuRebuild) {
            addItem(NSMenuItem()) // placeholder
            delegate = self
        } else {
            updateMenuItems(with: tabCollectionViewModel,
                            targetting: target,
                            moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isPopulated else { return }
        isPopulated = true
        removeAllItems()
        guard let tabCollectionViewModel, let target else { return }
        updateMenuItems(with: tabCollectionViewModel,
                        targetting: target,
                        moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider)
    }

    // ... existing updateMenuItems and performActionForItem unchanged ...
}
```

> **Note:** The `ZoomSubMenu` init call in `setupMenuItems` needs the new `featureFlagger:` parameter added. Find the call site in `MoreOptionsMenu.setupMenuItems` and add `featureFlagger: featureFlagger`.

### Step 5: Convert `LoginsSubMenu`

`LoginsSubMenu` (line 1141) — same pattern:

```swift
final class LoginsSubMenu: NSMenu, NSMenuDelegate {
    let passwordManagerCoordinator: PasswordManagerCoordinating
    private weak var target: AnyObject?
    private let moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding
    private let featureFlagger: FeatureFlagger
    private var isPopulated = false

    init(targetting target: AnyObject,
         passwordManagerCoordinator: PasswordManagerCoordinating,
         moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding,
         featureFlagger: FeatureFlagger) {
        self.passwordManagerCoordinator = passwordManagerCoordinator
        self.target = target
        self.moreOptionsMenuIconsProvider = moreOptionsMenuIconsProvider
        self.featureFlagger = featureFlagger
        super.init(title: UserText.passwordManagementTitle)

        if featureFlagger.isFeatureOn(.lazyMenuRebuild) {
            addItem(NSMenuItem()) // placeholder
            delegate = self
        } else {
            updateMenuItems(with: target, moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isPopulated else { return }
        isPopulated = true
        removeAllItems()
        guard let target else { return }
        updateMenuItems(with: target, moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider)
    }

    // ... existing updateMenuItems unchanged ...
}
```

### Step 6: Convert `HelpSubMenu`

`HelpSubMenu` (line 1193) — same pattern:

```swift
final class HelpSubMenu: NSMenu, NSMenuDelegate {
    private weak var target: AnyObject?
    private let featureFlagger: FeatureFlagger
    private var isPopulated = false

    @MainActor
    init(targetting target: AnyObject, featureFlagger: FeatureFlagger) {
        self.target = target
        self.featureFlagger = featureFlagger
        super.init(title: UserText.mainMenuHelp)

        if featureFlagger.isFeatureOn(.lazyMenuRebuild) {
            addItem(NSMenuItem()) // placeholder
            delegate = self
        } else {
            updateMenuItems(targetting: target)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isPopulated else { return }
        isPopulated = true
        removeAllItems()
        guard let target else { return }
        updateMenuItems(targetting: target)
    }

    // ... existing updateMenuItems and performActionForItem unchanged ...
}
```

> **Note:** `HelpSubMenu` init call site in `setupMenuItems` currently uses `HelpSubMenu(targetting: self)`. Add the `featureFlagger:` parameter.

### Step 7: Convert `BookmarksSubMenu`

`BookmarksSubMenu` (line 1016):

```swift
final class BookmarksSubMenu: NSMenu, NSMenuDelegate {
    private weak var tabCollectionViewModel: TabCollectionViewModel?
    private weak var target: AnyObject?
    private let bookmarkManager: BookmarkManager
    private let moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding
    private let featureFlagger: FeatureFlagger
    private var isPopulated = false

    @MainActor
    init(targetting target: AnyObject,
         tabCollectionViewModel: TabCollectionViewModel,
         bookmarkManager: BookmarkManager,
         moreOptionsMenuIconsProvider: MoreOptionsMenuIconsProviding,
         featureFlagger: FeatureFlagger) {
        self.target = target
        self.tabCollectionViewModel = tabCollectionViewModel
        self.bookmarkManager = bookmarkManager
        self.moreOptionsMenuIconsProvider = moreOptionsMenuIconsProvider
        self.featureFlagger = featureFlagger
        super.init(title: UserText.passwordManagementTitle)
        self.autoenablesItems = false

        if featureFlagger.isFeatureOn(.lazyMenuRebuild) {
            addItem(NSMenuItem()) // placeholder
            delegate = self
        } else {
            guard let tabCollectionViewModel = tabCollectionViewModel as TabCollectionViewModel? else { return }
            addMenuItems(with: tabCollectionViewModel,
                         target: target,
                         bookmarkManager: bookmarkManager,
                         moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider)
        }
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @MainActor
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard !isPopulated else { return }
        isPopulated = true
        removeAllItems()
        guard let tabCollectionViewModel, let target else { return }
        addMenuItems(with: tabCollectionViewModel,
                     target: target,
                     bookmarkManager: bookmarkManager,
                     moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider)
    }

    // ... existing addMenuItems, bookmarkMenuItems, performActionForItem unchanged ...
}
```

### Step 8: Update call sites in `setupMenuItems`

Each call site that creates the converted submenus needs the `featureFlagger:` parameter added. In `MoreOptionsMenu.setupMenuItems` (line 183+), update all submenu constructors:

```swift
feedbackMenuItem.submenu = FeedbackSubMenu(targetting: self,
                                           authenticationStateProvider: subscriptionManager,
                                           internalUserDecider: internalUserDecider,
                                           moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider,
                                           featureFlagger: featureFlagger)   // ← added

// ...

zoomMenuItem.submenu = ZoomSubMenu(targetting: self,
                                   tabCollectionViewModel: tabCollectionViewModel,
                                   moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider,
                                   featureFlagger: featureFlagger)            // ← added

// ...

loginsMenuItem.submenu = LoginsSubMenu(targetting: self,
                                       passwordManagerCoordinator: passwordManagerCoordinator,
                                       moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider,
                                       featureFlagger: featureFlagger)        // ← added

// ...

helpMenuItem.submenu = HelpSubMenu(targetting: self,
                                   featureFlagger: featureFlagger)            // ← added

// ...

bookmarksMenuItem.submenu = BookmarksSubMenu(targetting: self,
                                             tabCollectionViewModel: tabCollectionViewModel,
                                             bookmarkManager: bookmarkManager,
                                             moreOptionsMenuIconsProvider: moreOptionsMenuIconsProvider,
                                             featureFlagger: featureFlagger)  // ← added
```

### Step 9: Run tests

```bash
xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" -only-testing "UnitTests/LazyMoreOptionsMenuTests" 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: All tests PASSED.

### Step 10: Build full project

```bash
xcodebuild -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" build 2>&1 | grep -E "error:|Build succeeded"
```

### Step 11: Run all menu-related tests

```bash
xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" -only-testing "UnitTests/MainMenuTests" -only-testing "UnitTests/LazyMainMenuBookmarksTests" -only-testing "UnitTests/LazyMoreOptionsMenuTests" -only-testing "UnitTests/LazyBookmarkFolderMenuDelegateTests" 2>&1 | grep -E "error:|FAILED|PASSED|Test Suite"
```

Expected: All tests PASSED, 0 failures.

### Step 12: Commit

```bash
git add macOS/DuckDuckGo/NavigationBar/View/MoreOptionsMenu.swift macOS/UnitTests/Menus/
git commit -m "feat: lazy MoreOptionsMenu submenus via NSMenuDelegate"
```

---

## Final verification

Run the full unit test suite once to catch any regressions:

```bash
xcodebuild test -workspace DuckDuckGo.xcworkspace -scheme "DuckDuckGo macOS" -destination "platform=macOS" 2>&1 | grep -E "FAILED|Test Suite.*passed|Test Suite.*failed"
```

Expected: No failures.
