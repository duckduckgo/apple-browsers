//
//  DebugMenuFavoriteItem.swift
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

/// Forwards to the original item so targets, represented objects and dynamic submenu updates keep working.
@MainActor
final class DebugMenuFavoriteItem: NSMenuItem {
    let key: String
    private weak var favorites: DebugMenuFavorites?

    init(key: String, favorites: DebugMenuFavorites) {
        self.key = key
        self.favorites = favorites
        super.init(title: "", action: #selector(performOriginalAction), keyEquivalent: "")
        target = self
        view = DebugMenuItemView(key: key, favorites: favorites)
        synchronize()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func synchronize() {
        guard let source = favorites?.source(for: key) else {
            isEnabled = false
            return
        }
        title = source.title
        image = source.image
        state = source.state
        isEnabled = source.isEnabled
        isHidden = source.isHidden
        toolTip = source.toolTip
        indentationLevel = source.indentationLevel
        keyEquivalent = source.keyEquivalent
        keyEquivalentModifierMask = source.keyEquivalentModifierMask
        if source.submenu != nil {
            if submenu == nil, let favorites {
                submenu = DebugMenuFavoriteSubmenu(key: key, favorites: favorites)
            }
        } else {
            submenu = nil
        }
        view?.needsDisplay = true
    }

    @objc private func performOriginalAction() {
        guard let source = favorites?.source(for: key), source.isEnabled, let action = source.action else { return }
        NSApp.sendAction(action, to: source.target, from: source)
        favorites?.refresh()
    }
}

@MainActor
private final class DebugMenuFavoriteSubmenu: NSMenu {
    private let key: String
    private weak var favorites: DebugMenuFavorites?

    init(key: String, favorites: DebugMenuFavorites) {
        self.key = key
        self.favorites = favorites
        super.init(title: "")
        autoenablesItems = false
        synchronizeItems()
    }

    required init(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func update() {
        guard let favorites, let source = favorites.source(for: key)?.submenu else { return }
        source.update()
        favorites.refresh()
        synchronizeItems()
        super.update()
    }

    private func synchronizeItems() {
        guard let favorites, let source = favorites.source(for: key)?.submenu else { return }
        removeAllItems()
        for item in source.items {
            if item.isSeparatorItem {
                addItem(.separator())
            } else if let key = favorites.key(for: item) {
                addItem(DebugMenuFavoriteItem(key: key, favorites: favorites))
            } else if item.view == nil {
                let label = NSMenuItem(title: item.title, action: nil, keyEquivalent: "")
                label.attributedTitle = item.attributedTitle
                label.isEnabled = false
                addItem(label)
            }
        }
    }
}
