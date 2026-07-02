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

    var backButton: BrowserChromeButton { get }
    var fireButton: BrowserChromeButton { get }
    var forwardButton: BrowserChromeButton { get }
    var bookmarkButton: BrowserChromeButton { get }
    var passwordsButton: BrowserChromeButton { get }
    var browserMenuButton: BrowserChromeButton { get }

    /// Current tab-switcher control in the toolbar (default chrome button or a replaced view such as `TabSwitcherStaticButton`).
    var tabSwitcherView: UIView { get }

    func setTabSwitcherView(_ view: UIView)
    func updateToolbarWithState(_ state: ToolbarContentState)
}

final class ToolbarHandler: ToolbarStateHandling {
    weak var toolbar: BrowserToolbarView?

    lazy var backButton = {
        BrowserChromeButton.createToolbarButton(title: UserText.keyCommandBrowserBack, image: DesignSystemImages.Glyphs.Size24.arrowLeft)
    }()

    lazy var fireButton = {
        let button = BrowserChromeButton.createToolbarButton(title: UserText.actionForgetAll, image: DesignSystemImages.Glyphs.Size24.fireSolid)
        button.accessibilityIdentifier = "Browser.Toolbar.Button.Fire"
        return button
    }()

    lazy var forwardButton = {
        BrowserChromeButton.createToolbarButton(title: UserText.keyCommandBrowserForward, image: DesignSystemImages.Glyphs.Size24.arrowRight)
    }()

    private(set) var tabSwitcherView: UIView

    lazy var bookmarkButton = {
        BrowserChromeButton.createToolbarButton(title: UserText.actionOpenBookmarks, image: DesignSystemImages.Glyphs.Size24.bookmarks)
    }()

    lazy var passwordsButton = {
        BrowserChromeButton.createToolbarButton(title: UserText.actionOpenPasswords, image: DesignSystemImages.Glyphs.Size24.key)
    }()

    lazy var browserMenuButton = {
        BrowserChromeButton.createToolbarButton(title: UserText.menuButtonHint, image: DesignSystemImages.Glyphs.Size24.menuHamburger)
    }()

    private var state: ToolbarContentState?

    init(toolbar: BrowserToolbarView) {
        self.toolbar = toolbar
        let tabSwitcher = BrowserChromeButton.createToolbarButton(
            title: UserText.tabSwitcherAccessibilityLabel,
            image: DesignSystemImages.Glyphs.Size24.tabNew
        )
        self.tabSwitcherView = tabSwitcher
    }

    // MARK: - Public Methods

    func setTabSwitcherView(_ view: UIView) {
        tabSwitcherView = view
        if let state {
            applyToolbarLayout(for: state)
        } else {
            updateToolbarWithState(.newTab)
        }
    }

    func updateToolbarWithState(_ state: ToolbarContentState) {
        guard toolbar != nil else { return }

        updateNavigationButtonsWithState(state)

        /// Avoid unnecessary updates if the state hasn't changed
        guard self.state != state else { return }
        self.state = state

        applyToolbarLayout(for: state)
    }

    private func applyToolbarLayout(for state: ToolbarContentState) {
        guard let toolbar = toolbar else { return }

        let views: [UIView] = {
            switch state {
            case .pageLoaded:
                return createPageLoadedViews()
            case .newTab:
                return createNewTabViews()
            }
        }()

        toolbar.setToolbarButtons(views)
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

    private func createPageLoadedViews() -> [UIView] {
        [
            backButton,
            forwardButton,
            fireButton,
            tabSwitcherView,
            browserMenuButton,
        ]
    }

    private func createNewTabViews() -> [UIView] {
        [
            bookmarkButton,
            passwordsButton,
            fireButton,
            tabSwitcherView,
            browserMenuButton,
        ]
    }
}
