//
//  LinkOpenBehavior.swift
//
//  Copyright © 2025 DuckDuckGo. All rights reserved.
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

/// Defines how links, bookmarks, or menu items should be opened depending on key modifiers (⌘, ⇧, ⌥) or middle button clicks.
/// - `currentTab`: The link should be opened in the current tab.
/// - `newTab(selected: Bool)`: The link should be opened in a new tab, selecting it if needed.
/// - `newWindow(selected: Bool)`: The link should be opened in a new window, making it the key window if needed or opening it in the background.
enum LinkOpenBehavior: Equatable {

    case currentTab
    case newTab(selected: Bool)
    case newWindow(selected: Bool)

    var shouldSelectNewTab: Bool {
        switch self {
        case .currentTab: false
        case .newTab(selected: let selected), .newWindow(selected: let selected): selected
        }
    }

    /// Initializes a new instance based on the currently handled NSEvent and preferences.
    /// - Parameters:
    ///   - event: The NSEvent that caused the link opening (e.g., ⌘-click or middle mouse button press).
    ///   - switchToNewTabWhenOpenedPreference: Whether the preference to switch to a new tab is set.
    ///   - canOpenLinkInCurrentTab: If `true`, allows opening in the current tab; `false` is used for pinned tabs or popup windows (default: `true`).
    ///   - shouldSelectNewTab: Indicates if the new tab should be selected by default (e.g., when opening a new web page or Duck Player).
    ///       If `true`, key modifiers can modify behavior based on `switchToNewTabWhenOpenedPreference`,
    ///       e.g., ⌘⇧-click will make the tab non-selected if `switchToNewTabWhenOpenedPreference` is `true`.
    init(event: NSEvent?, switchToNewTabWhenOpenedPreference: Bool, canOpenLinkInCurrentTab: Bool = true, shouldSelectNewTab: Bool = false) {
        self.init(button: event?.button,
                  modifierFlags: event?.modifierFlags,
                  switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpenedPreference,
                  canOpenLinkInCurrentTab: canOpenLinkInCurrentTab,
                  shouldSelectNewTab: shouldSelectNewTab)
    }

    /// Initializes a new instance with specified button and modifier flags, determining link opening behavior.
    /// - Parameters:
    ///   - button: The mouse button pressed (default: left).
    ///   - modifierFlags: The active modifier flags (default: none).
    ///   - switchToNewTabWhenOpenedPreference: Whether the preference to switch to a new tab is set.
    ///   - canOpenLinkInCurrentTab: If `true`, allows opening in the current tab; `false` is used for pinned tabs or popup windows (default: `true`).
    ///   - shouldSelectNewTab: Indicates if the new tab should be selected by default (e.g., when opening a new web page or Duck Player).
    ///       If `true`, key modifiers can modify behavior based on `switchToNewTabWhenOpenedPreference`,
    ///       e.g., ⌘⇧-click will make the tab non-selected if `switchToNewTabWhenOpenedPreference` is `true`.
    init(button: NSEvent.Button? = nil, modifierFlags: NSEvent.ModifierFlags? = nil, switchToNewTabWhenOpenedPreference: Bool, canOpenLinkInCurrentTab: Bool = true, shouldSelectNewTab: Bool = false) {
        let modifierFlags = modifierFlags ?? []
        // ⌘+click or middle click: New Tab/Window modifier
        let shouldOpenNewTab = button == .middle || modifierFlags.contains(.command)
        let isShiftPressed = modifierFlags.contains(.shift)

        guard shouldOpenNewTab || !canOpenLinkInCurrentTab else {
            self = .currentTab
            return
        }

        // Determine if the new tab should be selected
        // If `shouldSelectNewTab` is true (e.g., web page requested a new tab),
        // ⌘-click modifies the standard selection behavior
        let isSelected = if shouldSelectNewTab && !shouldOpenNewTab {
            true
        } else {
            // ⇧+click: activate new tab/window when `switchToNewTabWhenOpenedPreference` is false
            // ⇧+click: open new tab/window in background when `switchToNewTabWhenOpenedPreference` is true
            (switchToNewTabWhenOpenedPreference && !isShiftPressed) || (!switchToNewTabWhenOpenedPreference && isShiftPressed)
        }

        // ⌘+⌥+click: New Window
        if modifierFlags.contains(.option) {
            self = .newWindow(selected: isSelected)
        } else {
            // ⌘+click: New Tab
            self = .newTab(selected: isSelected)
        }
    }

}
