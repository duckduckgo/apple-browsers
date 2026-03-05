//
//  ToolbarStateHandling.swift
//  DuckDuckGo
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

import UIKit
import BrowserServicesKit
import SwiftUI
import DesignResourcesKit
import DesignResourcesKitIcons

enum ToolbarContentState: Equatable {
    case newTab
    case pageLoaded(currentTab: Navigatable)

    static func == (lhs: ToolbarContentState, rhs: ToolbarContentState) -> Bool {
        switch (lhs, rhs) {
        case (.newTab, .newTab):
            return true
        case (.pageLoaded(let lhsTab), .pageLoaded(let rhsTab)):
            return lhsTab === rhsTab && lhsTab.canGoBack == rhsTab.canGoBack && lhsTab.canGoForward == rhsTab.canGoForward
        default:
            return false
        }
    }
}

protocol ToolbarStateHandling {

    var backButton: UIBarButtonItem { get }
    var fireBarButtonItem: UIBarButtonItem { get }
    var forwardButton: UIBarButtonItem { get }
    var tabSwitcherButton: UIBarButtonItem { get }
    var bookmarkButton: UIBarButtonItem { get }

    var passwordsButton: UIBarButtonItem { get }
    var browserMenuButton: UIBarButtonItem { get }

    func updateToolbarWithState(_ state: ToolbarContentState)

}

final class ToolbarHandler: ToolbarStateHandling {
    weak var toolbar: UIToolbar?

    private let themeManager: ThemeManaging

    lazy var backButton = {
        return BrowserChromeButton.createToolbarButtonItem(title: UserText.keyCommandBrowserBack, image: DesignSystemImages.Glyphs.Size24.arrowLeft)
    }()

    lazy var fireBarButtonItem = {
        let buttonItem = BrowserChromeButton.createToolbarButtonItem(title: UserText.actionForgetAll, image: DesignSystemImages.Glyphs.Size24.fireSolid)
        buttonItem.accessibilityIdentifier = "Browser.Toolbar.Button.Fire"
        return buttonItem
    }()

    lazy var forwardButton = {
        return BrowserChromeButton.createToolbarButtonItem(title: UserText.keyCommandBrowserForward, image: DesignSystemImages.Glyphs.Size24.arrowRight)
    }()

    lazy var tabSwitcherButton = {
        return BrowserChromeButton.createToolbarButtonItem(title: UserText.tabSwitcherAccessibilityLabel, image: DesignSystemImages.Glyphs.Size24.tabNew)
    }()

    lazy var bookmarkButton = {
        return BrowserChromeButton.createToolbarButtonItem(title: UserText.actionOpenBookmarks, image: DesignSystemImages.Glyphs.Size24.bookmarks)
    }()

    lazy var passwordsButton = {
        return BrowserChromeButton.createToolbarButtonItem(title: UserText.actionOpenPasswords, image: DesignSystemImages.Glyphs.Size24.key)
    }()

    lazy var browserMenuButton = {
        return BrowserChromeButton.createToolbarButtonItem(title: UserText.menuButtonHint, image: DesignSystemImages.Glyphs.Size24.menuHamburger)
    }()

    private var state: ToolbarContentState?

    init(toolbar: UIToolbar,
         themeManager: ThemeManaging = ThemeManager.shared) {
        self.toolbar = toolbar
        self.themeManager = themeManager
    }

    // MARK: - Public Methods

    func updateToolbarWithState(_ state: ToolbarContentState) {
        guard let toolbar = toolbar else { return }

        updateNavigationButtonsWithState(state)

        /// Avoid unnecessary updates if the state hasn't changed
        guard self.state != state else { return }
        self.state = state

        let buttons: [UIBarButtonItem] = {
            switch state {
            case .pageLoaded:
                return createPageLoadedButtons()
            case .newTab:
                return createNewTabButtons()
            }
        }()

        toolbar.setItems(buttons, animated: false)

    }

    // MARK: - Private Methods

    private func updateNavigationButtonsWithState(_ state: ToolbarContentState) {
        let currentTab: Navigatable? = {
            if case let .pageLoaded(tab) = state {
                return tab
            }
            return nil
        }()

        backButton.isEnabled = currentTab?.canGoBack ?? false
        forwardButton.isEnabled = currentTab?.canGoForward ?? false
    }

    private func createPageLoadedButtons() -> [UIBarButtonItem] {
        return [
            backButton,
            .flexibleSpace(),
            forwardButton,
            .flexibleSpace(),
            fireBarButtonItem,
            .flexibleSpace(),
            tabSwitcherButton,
            .flexibleSpace(),
            browserMenuButton,
        ].compactMap { $0 }
    }

    private func createNewTabButtons() -> [UIBarButtonItem] {
        return [
            bookmarkButton,
            .flexibleSpace(),
            passwordsButton,
            .flexibleSpace(),
            fireBarButtonItem,
            .flexibleSpace(),
            tabSwitcherButton,
            .flexibleSpace(),
            browserMenuButton,
        ].compactMap { $0 }
    }
}
