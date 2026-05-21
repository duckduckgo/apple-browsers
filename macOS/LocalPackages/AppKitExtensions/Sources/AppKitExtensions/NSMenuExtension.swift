//
//  NSMenuExtension.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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
import Utilities

typealias MenuBuilder = ArrayBuilder<NSMenuItem>

public extension NSMenu {

    convenience init(title: String = "", items: [NSMenuItem]) {
        self.init(title: title)
        self.items = items
    }

    convenience init(title string: String = "", @MenuBuilder items: () -> [NSMenuItem]) {
        self.init(title: string, items: items())
    }

    @discardableResult
    func buildItems(@MenuBuilder items: () -> [NSMenuItem]) -> NSMenu {
        self.items = items()
        return self
    }

    func indexOfItem(withIdentifier id: String) -> Int? {
        return items.enumerated().first(where: { $0.element.identifier?.rawValue == id })?.offset
    }

    func indexOfItem(with action: Selector) -> Int? {
        return items.enumerated().first(where: { $0.element.action == action })?.offset
    }

    func item(with action: Selector) -> NSMenuItem? {
        return indexOfItem(with: action).map { self.items[$0] }
    }

    func item(with identifier: NSUserInterfaceItemIdentifier) -> NSMenuItem? {
        return indexOfItem(withIdentifier: identifier.rawValue).map { self.items[$0] }
    }

    func replaceItem(at index: Int, with newItem: NSMenuItem) {
        removeItem(at: index)
        insertItem(newItem, at: index)
    }

    /// Pops up the menu at the current mouse location.
    ///
    /// - Parameter view: The view to display the menu item over.
    /// - Attention: If the view is not currently installed in a window, this function does not show any pop up menu.
    func popUpAtMouseLocation(in view: NSView) {
        guard let cursorLocation = view.window?.mouseLocationOutsideOfEventStream else { return }
        let convertedLocation = view.convert(cursorLocation, from: nil)
        popUp(positioning: nil, at: convertedLocation, in: view)
    }

    /// This API removes / re-adds all items, effectively forcing a relayout cycle
    ///
    func forceRelayout() {
        let currentItems = items
        removeAllItems()

        for item in currentItems {
            addItem(item)
        }
    }

    /// Aligns the title text of items without an `image` with the title text of items that have one,
    /// section by section (sections are delimited by separator items).
    ///
    /// macOS 26's NSMenu auto-indent for image-less items is inconsistent — works in some menus,
    /// not in others, even when item images are uniformly sized. For each section that contains at
    /// least one item with an image, this sets a transparent placeholder image (sized to the largest
    /// image in that section) on the section's image-less items, which forces AppKit to reserve the
    /// icon column for them and aligns text. Sections with no icons are left untouched. Idempotent.
    @MainActor
    func alignItemTextWithIcons() {
        var section: [NSMenuItem] = []
        for item in items {
            if item.isSeparatorItem {
                alignTextInSection(section)
                section.removeAll(keepingCapacity: true)
            } else {
                section.append(item)
            }
        }
        alignTextInSection(section)
    }

    @MainActor
    private func alignTextInSection(_ section: [NSMenuItem]) {
        guard let maxSize = section.compactMap({ $0.image?.size }).max(by: { $0.width < $1.width }) else {
            return
        }
        let placeholder = NSImage(size: maxSize)
        for item in section where item.image == nil && item.view == nil && !item.isHeaderLike {
            item.image = placeholder
        }
    }

    /// Recursively calls ``alignItemTextWithIcons()`` on this menu and every submenu.
    /// Skips submenus that haven't been populated yet (those should call
    /// ``alignItemTextWithIcons()`` themselves after building their items).
    @MainActor
    func alignItemTextWithIconsRecursively() {
        alignItemTextWithIcons()
        for item in items where !item.isSeparatorItem {
            item.submenu?.alignItemTextWithIconsRecursively()
        }
    }
}

private extension NSMenuItem {
    /// Disabled items with no action render as section headers (small grey caption above a group).
    /// They sit flush-left, not in the icon column, so they should be excluded from icon alignment.
    var isHeaderLike: Bool {
        !isEnabled && action == nil
    }
}
