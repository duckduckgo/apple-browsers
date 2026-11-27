//
//  DebugMenuFavoritesTests.swift
//
//  Copyright © 2026 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import AppKit
import Common
import FeatureFlags_macOS
import PrivacyConfig
import XCTest

@testable import DuckDuckGo_Privacy_Browser

@MainActor
final class DebugMenuFavoritesTests: XCTestCase {

    func testItemsWithSharedIdentifiersAndActionsKeepDistinctKeys() throws {
        let menu = NSMenu()
        let target = ActionTarget()
        let first = makeAction("Append 10 Tabs", target: target)
        let second = makeAction("Append 50 Tabs", target: target)
        first.identifier = NSUserInterfaceItemIdentifier("appendTabs")
        second.identifier = first.identifier
        first.representedObject = 10
        second.representedObject = 50
        menu.addItem(first)
        menu.addItem(second)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        let firstKey = try XCTUnwrap(favorites.key(for: first))
        let secondKey = try XCTUnwrap(favorites.key(for: second))

        XCTAssertNotEqual(firstKey, secondKey)
        favorites.toggle(firstKey)
        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)
        menu.performActionForItem(at: menu.index(of: favorite))

        XCTAssertTrue(target.senders.first === first)
        XCTAssertEqual(target.senders.first?.representedObject as? Int, 10)
    }

    func testFavoritedFlagRefreshesResetSubmenuAndResetCannotBeFavorited() throws {
        for defaultValue in [false, true] {
            let (flagMenu, overrides) = makeFeatureFlagMenu(defaultValue: defaultValue)
            let menu = NSMenu()
            let flags = makeGroup("Feature Flags", children: [])
            flags.submenu = flagMenu
            menu.addItem(flags)
            let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
            let flagItem = try XCTUnwrap(flagMenu.items.flatMap { $0.submenu?.items ?? [] }.first {
                ($0.representedObject as? FeatureFlag) == .debugURLScheme
            })
            let flagKey = try XCTUnwrap(favorites.key(for: flagItem))
            favorites.toggle(flagKey)
            let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)
            XCTAssertNil(favorite.submenu)

            overrides.toggleOverride(for: FeatureFlag.debugURLScheme)
            favorites.refresh()

            let resetMenu = try XCTUnwrap(favorite.submenu)
            let reset = try XCTUnwrap(resetMenu.items.first)
            XCTAssertEqual(reset.title, "Reset to default: \(defaultValue ? "ON" : "OFF")")
            XCTAssertFalse(reset.isHidden)
            let sourceReset = try XCTUnwrap(flagItem.submenu?.items.first)
            let resetKey = try XCTUnwrap(favorites.key(for: sourceReset))

            favorites.toggle(resetKey)

            XCTAssertEqual(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.count, 1)

            XCTAssertTrue(try XCTUnwrap(favorite.view as? DebugMenuItemView).accessibilityPerformPress())
            XCTAssertEqual(overrides.override(for: FeatureFlag.debugURLScheme), defaultValue)

            resetMenu.performActionForItem(at: 0)

            XCTAssertNil(overrides.override(for: FeatureFlag.debugURLScheme))
            XCTAssertNil(favorite.submenu)
        }
    }

    private func makeFeatureFlagMenu(defaultValue: Bool) -> (FeatureFlagOverridesMenu, FeatureFlagLocalOverrides) {
        let flagger = MockFeatureFlagger(
            internalUserDecider: PrivacyConfig.MockInternalUserDecider(isInternalUser: true),
            featuresStub: [FeatureFlag.debugURLScheme.rawValue: defaultValue]
        )
        let overrides = FeatureFlagLocalOverrides(
            keyValueStore: makeDefaults(),
            actionHandler: FeatureFlagOverridesPublishingHandler<FeatureFlag>()
        )
        overrides.featureFlagger = flagger
        flagger.localOverrides = overrides
        let menu = FeatureFlagOverridesMenu(featureFlagOverrides: flagger)
        return (menu, overrides)
    }

    func testUnpinningWhileTrackingRemovesFavoriteAfterMouseHandlerWithoutAddingDuplicate() throws {
        let menu = NSMenu()
        let original = makeAction("Reset")
        menu.addItem(original)
        let defaults = makeDefaults()
        let favorites = DebugMenuFavorites(menu: menu, defaults: defaults)
        let key = try XCTUnwrap(favorites.key(for: original))
        favorites.toggle(key)
        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)
        let row = try XCTUnwrap(favorite.view as? DebugMenuItemView)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseUp, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        favorites.menuWillOpen(menu)
        defer { favorites.menuDidClose(menu) }

        row.rightMouseUp(with: event)

        XCTAssertEqual(defaults.stringArray(forKey: DebugMenuFavorites.defaultsKey), [])
        XCTAssertTrue(favorite.menu === menu, "Finish dispatching input before changing the tracked rows")
        let removed = expectation(description: "Favorite is removed on the next run-loop turn")
        let check: @MainActor @Sendable () -> Void = {
            XCTAssertNil(favorite.menu)
            XCTAssertTrue(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.isEmpty)
            XCTAssertTrue(original.menu === menu)
            removed.fulfill()
        }
        RunLoop.main.perform(inModes: [.default]) {
            MainActor.assumeMainThread { check() }
        }
        wait(for: [removed], timeout: 1)
    }

    func testEmptyFavoritesSectionContainsOnlyInstructionHeader() throws {
        let menu = NSMenu()
        let original = makeAction("Reset")
        menu.addItem(original)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        let key = try XCTUnwrap(favorites.key(for: original))

        favorites.toggle(key)
        favorites.toggle(key)

        XCTAssertEqual(menu.items.first?.title, "Favorites — right-click to pin / unpin")
        XCTAssertEqual(menu.items.dropFirst().first?.isSeparatorItem, true)
        XCTAssertFalse(menu.items.contains { $0.title == "No Favorites" })
        XCTAssertTrue(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.isEmpty)
    }

    func testLongRowsAreMeasuredBeforeMenuTrackingBegins() throws {
        let menu = NSMenu()
        let title = String(repeating: "Long debug action title ", count: 8)
        let original = makeAction(title)
        menu.addItem(original)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        let titleWidth = (title as NSString).size(withAttributes: [.font: NSFont.menuFont(ofSize: 0)]).width
        let originalView = try XCTUnwrap(original.view as? DebugMenuItemView)

        XCTAssertGreaterThan(originalView.frame.width, titleWidth)

        favorites.toggle(try XCTUnwrap(favorites.key(for: original)))
        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)
        let favoriteView = try XCTUnwrap(favorite.view as? DebugMenuItemView)
        XCTAssertGreaterThan(favoriteView.frame.width, titleWidth)
    }

    func testRowKeepsMenuAssignedWidthWhenItsWindowChanges() throws {
        let menu = NSMenu()
        let original = makeAction("Reset")
        menu.addItem(original)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        let view = try XCTUnwrap(original.view as? DebugMenuItemView)
        let assignedSize = NSSize(width: 900, height: 24)
        view.setFrameSize(assignedSize)

        view.viewDidMoveToWindow()

        XCTAssertEqual(view.frame.size, assignedSize)
        XCTAssertNotNil(favorites.key(for: original))
    }

    func testPinningLeavesOriginalAndFavoriteTitlesUnchanged() throws {
        let menu = NSMenu()
        let original = makeAction("Reset Onboarding")
        menu.addItem(original)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())

        favorites.toggle(try XCTUnwrap(favorites.key(for: original)))

        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)
        XCTAssertEqual(original.title, "Reset Onboarding")
        XCTAssertEqual(favorite.title, "Reset Onboarding")
        XCTAssertTrue(original.menu === menu)
    }

    func testRightClickTogglesWithoutExecutingActionOrRemovingOriginalItem() throws {
        let target = ActionTarget()
        let menu = NSMenu()
        let original = makeAction("Reset", target: target)
        menu.addItem(original)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        let view = try XCTUnwrap(original.view as? DebugMenuItemView)
        let event = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseUp, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
        let mouseDown = try XCTUnwrap(NSEvent.mouseEvent(with: .rightMouseDown, location: .zero,
            modifierFlags: [], timestamp: 0, windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1))

        view.rightMouseDown(with: mouseDown)
        XCTAssertTrue(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.isEmpty)

        view.rightMouseUp(with: event)
        XCTAssertEqual(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.count, 1)
        XCTAssertEqual(target.senders.count, 0)
        XCTAssertTrue(original.menu === menu)

        view.rightMouseDown(with: mouseDown)
        XCTAssertEqual(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.count, 1)

        view.rightMouseUp(with: event)
        XCTAssertTrue(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.isEmpty)
        XCTAssertEqual(target.senders.count, 0)
        XCTAssertNotNil(favorites.key(for: original))
    }

    func testFavoritesPersistWhenMenuIsRecreated() throws {
        let defaults = makeDefaults()
        let firstMenu = NSMenu()
        let firstAction = makeAction("Reset")
        firstMenu.addItem(firstAction)
        let firstFavorites = DebugMenuFavorites(menu: firstMenu, defaults: defaults)
        firstFavorites.toggle(try XCTUnwrap(firstFavorites.key(for: firstAction)))

        let secondMenu = NSMenu()
        let secondAction = makeAction("Reset")
        secondMenu.addItem(secondAction)
        let secondFavorites = DebugMenuFavorites(menu: secondMenu, defaults: defaults)

        let favorite = try XCTUnwrap(secondMenu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)
        XCTAssertEqual(favorite.key, secondFavorites.key(for: secondAction))
        XCTAssertEqual(favorite.title, "Reset")
    }

    func testFavoriteActionReceivesOriginalSenderAndRepresentedObject() throws {
        let target = ActionTarget()
        let menu = NSMenu()
        let original = makeAction("Append Tabs", target: target)
        original.representedObject = 50
        menu.addItem(original)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        favorites.toggle(try XCTUnwrap(favorites.key(for: original)))
        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)

        menu.performActionForItem(at: menu.index(of: favorite))

        XCTAssertEqual(target.senders.count, 1)
        XCTAssertTrue(target.senders.first === original)
        XCTAssertEqual(target.senders.first?.representedObject as? Int, 50)
    }

    func testFavoriteSubmenuUsesOriginalUpdateAndForwardsChildActions() throws {
        let target = ActionTarget()
        let menu = NSMenu()
        let original = NSMenuItem(title: "VPN", action: nil, keyEquivalent: "")
        let submenu = UpdatingMenu()
        submenu.actionTarget = target
        original.submenu = submenu
        menu.addItem(original)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        favorites.toggle(try XCTUnwrap(favorites.key(for: original)))
        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)
        let favoriteSubmenu = try XCTUnwrap(favorite.submenu)

        favoriteSubmenu.update()
        let child = try XCTUnwrap(favoriteSubmenu.items.first)
        favoriteSubmenu.performActionForItem(at: 0)

        XCTAssertEqual(submenu.updateCount, 1)
        XCTAssertEqual(child.title, "Updated Connection")
        XCTAssertEqual(child.state, .on)
        XCTAssertTrue(target.senders.first === submenu.items.first)
        XCTAssertTrue(original.submenu === submenu)
    }

    func testDisabledFavoriteDoesNotExecuteItsAction() throws {
        let target = ActionTarget()
        let menu = NSMenu()
        let original = makeAction("Connect", target: target)
        original.isEnabled = false
        menu.addItem(original)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        favorites.toggle(try XCTUnwrap(favorites.key(for: original)))
        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)

        menu.performActionForItem(at: menu.index(of: favorite))

        XCTAssertFalse(favorite.isEnabled)
        XCTAssertTrue(target.senders.isEmpty)
    }

    func testChangingActionTitleKeepsItsFavoriteAndUpdatesTheDisplayedTitle() throws {
        let menu = NSMenu()
        let original = makeAction("Enable Logging")
        menu.addItem(original)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        let key = try XCTUnwrap(favorites.key(for: original))
        favorites.toggle(key)

        original.title = "Disable Logging"
        favorites.refresh()

        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)
        XCTAssertEqual(favorite.key, key)
        XCTAssertEqual(favorite.title, "Disable Logging")
    }

    func testSameNamedActionsInDifferentSubmenusCanBePinnedIndependently() throws {
        let menu = NSMenu()
        let first = makeGroup("Onboarding", children: [makeAction("Reset")])
        let second = makeGroup("VPN", children: [makeAction("Reset")])
        menu.addItem(first)
        menu.addItem(second)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        let firstChild = try XCTUnwrap(first.submenu?.items.first)
        let secondChild = try XCTUnwrap(second.submenu?.items.first)
        let firstKey = try XCTUnwrap(favorites.key(for: firstChild))
        let secondKey = try XCTUnwrap(favorites.key(for: secondChild))

        favorites.toggle(firstKey)

        XCTAssertNotEqual(firstKey, secondKey)
        XCTAssertEqual(menu.items.compactMap { ($0 as? DebugMenuFavoriteItem)?.key }, [firstKey])
    }

    func testSearchFiltersBothOriginalAndFavoriteCustomRows() throws {
        let menu = NSMenu()
        let reset = makeAction("Reset Onboarding")
        let logs = makeAction("Export Logs")
        menu.addItem(reset)
        menu.addItem(logs)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        favorites.toggle(try XCTUnwrap(favorites.key(for: logs)))
        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)

        menu.filterMenuItems(searchText: "reset")

        XCTAssertFalse(reset.isHidden)
        XCTAssertTrue(logs.isHidden)
        XCTAssertTrue(favorite.isHidden)

        menu.showAllMenuItems()

        XCTAssertFalse(logs.isHidden)
        XCTAssertFalse(favorite.isHidden)
    }

    func testExistingCustomViewsArePreserved() {
        let menu = NSMenu()
        let search = NSMenuItem()
        let searchView = NSSearchField()
        search.view = searchView
        menu.addItem(search)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())

        favorites.refresh()

        XCTAssertTrue(search.view === searchView)
        XCTAssertNil(favorites.key(for: search))
    }

    func testRefreshKeepsExistingFavoritesAndTheirSubmenusAttached() throws {
        let menu = NSMenu()
        let vpn = makeGroup("VPN", children: [makeAction("Connect")])
        let reset = makeAction("Reset")
        menu.addItem(vpn)
        menu.addItem(reset)
        let favorites = DebugMenuFavorites(menu: menu, defaults: makeDefaults())
        favorites.toggle(try XCTUnwrap(favorites.key(for: vpn)))
        let favorite = try XCTUnwrap(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.first)
        let favoriteSubmenu = favorite.submenu

        favorites.toggle(try XCTUnwrap(favorites.key(for: reset)))

        XCTAssertTrue(favorite.menu === menu)
        XCTAssertTrue(favorite.submenu === favoriteSubmenu)
        XCTAssertEqual(menu.items.compactMap { $0 as? DebugMenuFavoriteItem }.count, 2)
    }

    private func makeDefaults() -> UserDefaults {
        let name = "DebugMenuFavoritesTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        addTeardownBlock { defaults.removePersistentDomain(forName: name) }
        return defaults
    }

    private func makeAction(_ title: String, target: ActionTarget? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(ActionTarget.run(_:)), keyEquivalent: "")
        item.target = target
        return item
    }

    private func makeGroup(_ title: String, children: [NSMenuItem]) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.submenu = NSMenu()
        children.forEach { item.submenu?.addItem($0) }
        return item
    }

    private final class ActionTarget: NSObject {
        var senders: [NSMenuItem] = []

        @objc func run(_ sender: NSMenuItem) {
            senders.append(sender)
        }
    }

    private final class UpdatingMenu: NSMenu {
        var updateCount = 0
        weak var actionTarget: ActionTarget?

        override func update() {
            updateCount += 1
            removeAllItems()
            let item = NSMenuItem(title: "Updated Connection", action: #selector(ActionTarget.run(_:)), keyEquivalent: "")
            item.target = actionTarget
            item.state = .on
            addItem(item)
        }
    }
}
