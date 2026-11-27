//
//  DebugMenuFavorites.swift
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

/// Owns favorite selection and the Favorites section, leaving the original menus and actions in place.
@MainActor
final class DebugMenuFavorites: NSObject, NSMenuDelegate {
    static let defaultsKey = "debugMenuFavorites"

    private weak var menu: NSMenu?
    private let defaults: UserDefaults
    private let onChange: () -> Void
    private let header = NSMenuItem(title: "Favorites — right-click to pin / unpin", action: nil, keyEquivalent: "")
    private let separator = NSMenuItem.separator()
    private var favoriteKeys: [String]
    private var originals: [String: NSMenuItem] = [:]
    private var favorites: [String: DebugMenuFavoriteItem] = [:]
    private var observers: [NSObjectProtocol] = []
    private var displayTimer: Timer?
    private var isRefreshing = false
    private var refreshScheduled = false

    init(menu: NSMenu, defaults: UserDefaults = .standard, onChange: @escaping () -> Void = {}) {
        self.menu = menu
        self.defaults = defaults
        self.onChange = onChange
        favoriteKeys = defaults.stringArray(forKey: Self.defaultsKey) ?? []
        super.init()

        for item in [header, separator] {
            item.tag = -1 // Like the search field, these are not searchable actions.
            item.isEnabled = false
        }
        let insertionIndex = menu.items.prefix(while: { $0.tag == -1 }).count
        menu.insertItem(header, at: insertionIndex)
        menu.insertItem(separator, at: insertionIndex + 1)
        menu.delegate = self
        refresh()

        for name in [NSMenu.didAddItemNotification, NSMenu.didRemoveItemNotification, NSMenu.didChangeItemNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] notification in
                MainActor.assumeMainThread {
                    guard let self, let changedMenu = notification.object as? NSMenu,
                          !self.isRefreshing, self.contains(changedMenu) else { return }
                    self.scheduleRefresh()
                }
            })
        }
    }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
        displayTimer?.invalidate()
    }

    func source(for key: String) -> NSMenuItem? {
        originals[key]
    }

    func key(for item: NSMenuItem) -> String? {
        originals.first(where: { $0.value === item })?.key
    }

    func toggle(_ key: String) {
        guard let item = originals[key], !isResetOverride(item) else { return }
        if let index = favoriteKeys.firstIndex(of: key) {
            favoriteKeys.remove(at: index)
        } else {
            favoriteKeys.append(key)
        }
        defaults.set(favoriteKeys, forKey: Self.defaultsKey)
        if displayTimer != nil {
            // Finish dispatching the click before changing the menu's rows. AppKit is
            // still tracking the clicked row until its input handler returns.
            scheduleRefresh()
        } else {
            refresh()
        }
    }

    func refresh() {
        guard let menu, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        originals.removeAll(keepingCapacity: true)
        prepare(menu, path: [])

        // A favorited flag can be used without opening its original menu. Run that
        // menu's existing updater so override icons and reset submenus stay current.
        let flagMenus = Set(favoriteKeys.compactMap { key in
            originals[key].flatMap(featureFlagMenu(for:))
        })
        if !flagMenus.isEmpty {
            flagMenus.forEach { $0.update() }
            originals.removeAll(keepingCapacity: true)
            prepare(menu, path: [])
        }
        let previousCount = favoriteKeys.count
        favoriteKeys.removeAll { key in originals[key].map(isResetOverride) ?? false }
        if favoriteKeys.count != previousCount {
            defaults.set(favoriteKeys, forKey: Self.defaultsKey)
        }

        for (key, item) in favorites where !favoriteKeys.contains(key) || originals[key] == nil {
            menu.removeItem(item)
            favorites.removeValue(forKey: key)
        }
        var insertionIndex = menu.index(of: header) + 1
        for key in favoriteKeys where originals[key] != nil {
            if let item = favorites[key] {
                item.synchronize()
            } else {
                let item = DebugMenuFavoriteItem(key: key, favorites: self)
                favorites[key] = item
                menu.insertItem(item, at: insertionIndex)
            }
            insertionIndex += 1
        }
        onChange()
    }

    private func isResetOverride(_ item: NSMenuItem) -> Bool {
        item.target is FeatureFlagOverridesMenu
            && item.action.map(NSStringFromSelector) == NSStringFromSelector(#selector(FeatureFlagOverridesMenu.resetOverride(_:)))
    }

    private func featureFlagMenu(for item: NSMenuItem) -> FeatureFlagOverridesMenu? {
        if let owner = item.target as? FeatureFlagOverridesMenu { return owner }
        if let owner = item.submenu as? FeatureFlagOverridesMenu { return owner }
        var ancestor = item.menu
        while let current = ancestor, current !== menu {
            if let owner = current as? FeatureFlagOverridesMenu { return owner }
            ancestor = current.supermenu
        }
        return nil
    }

    private func prepare(_ menu: NSMenu, path: [String]) {
        let identifierCounts = Dictionary(grouping: menu.items.compactMap { $0.identifier?.rawValue }, by: { $0 }).mapValues(\.count)
        let actionCounts = menu.items.reduce(into: [String: Int]()) { counts, item in
            if let action = item.action {
                counts[NSStringFromSelector(action), default: 0] += 1
            }
        }
        for item in menu.items where !(item is DebugMenuFavoriteItem) && item.tag != -1 && !item.isSeparatorItem {
            guard item.view == nil || item.view is DebugMenuItemView else { continue }
            guard item.action != nil || item.submenu != nil else { continue }
            let component: String
            if let identifier = item.identifier, identifierCounts[identifier.rawValue] == 1 {
                component = identifier.rawValue
            } else if let action = item.action, actionCounts[NSStringFromSelector(action)] == 1 {
                component = NSStringFromSelector(action)
            } else {
                component = item.title
            }
            let itemPath = path + [component]
            let key = itemPath.joined(separator: "\u{1F}")
            originals[key] = item
            if let view = item.view as? DebugMenuItemView {
                view.key = key
            } else {
                item.view = DebugMenuItemView(key: key, favorites: self)
            }
            if let submenu = item.submenu {
                prepare(submenu, path: itemPath)
            }
        }
    }

    private func contains(_ candidate: NSMenu) -> Bool {
        var current: NSMenu? = candidate
        while let ancestor = current {
            if ancestor === menu { return true }
            current = ancestor.supermenu
        }
        return false
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        RunLoop.main.perform(inModes: [.default, .eventTracking]) { [weak self] in
            MainActor.assumeMainThread {
                self?.refreshScheduled = false
                self?.refresh()
            }
        }
    }

    private func updateVisibleRows(in menu: NSMenu) {
        for item in menu.items {
            if let view = item.view as? DebugMenuItemView, view.window != nil {
                view.needsDisplay = true
            }
            if let submenu = item.submenu {
                updateVisibleRows(in: submenu)
            }
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        refresh()
    }

    func menuWillOpen(_ menu: NSMenu) {
        displayTimer?.invalidate()
        let timer = Timer(timeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeMainThread {
                guard let self, let menu = self.menu else { return }
                self.updateVisibleRows(in: menu)
            }
        }
        displayTimer = timer
        RunLoop.main.add(timer, forMode: .eventTracking)
    }

    func menuDidClose(_ menu: NSMenu) {
        displayTimer?.invalidate()
        displayTimer = nil
    }
}
