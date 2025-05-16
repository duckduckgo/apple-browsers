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
import SwiftUICore

enum ToolbarContentState: Equatable {
    case newTab
    case pageLoaded(currentTab: Navigatable)

    static func == (lhs: ToolbarContentState, rhs: ToolbarContentState) -> Bool {
        switch (lhs, rhs) {
        case (.newTab, .newTab):
            return true
        case (.pageLoaded(let lhsTab), .pageLoaded(let rhsTab)):
            return lhsTab.canGoBack == rhsTab.canGoBack && lhsTab.canGoForward == rhsTab.canGoForward
        default:
            return false
        }
    }
}

protocol ToolbarStateHandling {
    func updateToolbarWithState(_ state: ToolbarContentState)
}

final class ToolbarHandler: ToolbarStateHandling {
    weak var toolbar: UIToolbar?
    private let featureFlagger: FeatureFlagger
    lazy var isExperimentalThemingEnabled = {
        ExperimentalThemingManager(featureFlagger: featureFlagger).isExperimentalThemingEnabled
    }()

    lazy var backButton = {
        let resource = isExperimentalThemingEnabled ? ImageResource.arrowLeftNew24 : .browsePrevious
        return createBarButtonItem(title: UserText.keyCommandBrowserBack, imageResource: resource)
    }()

    lazy var fireBarButtonItem = {
        let resource = isExperimentalThemingEnabled ? ImageResource.fireNew24 : .fire
        return createBarButtonItem(title: UserText.actionForgetAll, imageResource: resource)
    }()

    lazy var forwardButton = {
        let resource = isExperimentalThemingEnabled ? ImageResource.arrowRightNew24 : .browseNext
        return createBarButtonItem(title: UserText.keyCommandBrowserForward, imageResource: resource)
    }()

    lazy var tabSwitcherButton = {
        let resource = isExperimentalThemingEnabled ? ImageResource.tabNew24 : .add24
        return createBarButtonItem(title: UserText.tabSwitcherAccessibilityLabel, imageResource: resource)
    }()

    lazy var bookmarkButton = {
        let resource = isExperimentalThemingEnabled ? ImageResource.bookmarksStacked24 : .book24
        return createBarButtonItem(title: UserText.actionOpenBookmarks, imageResource: resource)
    }()

    lazy var passwordsButton = {
        let resource = isExperimentalThemingEnabled ? ImageResource.keyNew24 : .key24
        return createBarButtonItem(title: UserText.actionOpenPasswords, imageResource: resource)
    }()

    lazy var browserMenuButton = {
        let resource = isExperimentalThemingEnabled ? ImageResource.menuHamburgerNew24 : .menuHorizontal24
        return createBarButtonItem(title: UserText.menuButtonHint, imageResource: resource)
    }()

    private var state: ToolbarContentState?

    init(toolbar: UIToolbar, featureFlagger: FeatureFlagger) {
        self.toolbar = toolbar
        self.featureFlagger = featureFlagger
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

    private func createBarButtonItem(title: String, imageResource: ImageResource) -> UIBarButtonItem {
        if self.isExperimentalThemingEnabled {
            let button = ToolbarButton(.primary)
            button.setImage(UIImage(resource: imageResource))
            button.frame = CGRect(x: 0, y: 0, width: 34, height: 44)

            let barItem = UIBarButtonItem(customView: button)
            barItem.title = title

            return barItem
        } else {
            return UIBarButtonItem(title: title, image: UIImage(resource: imageResource), primaryAction: nil)
        }
    }

    private func createPageLoadedButtons() -> [UIBarButtonItem] {
        return [
            isExperimentalThemingEnabled ? .additionalFixedSpaceItem() : nil,
            backButton,
            .flexibleSpace(),
            forwardButton,
            .flexibleSpace(),
            fireBarButtonItem,
            .flexibleSpace(),
            tabSwitcherButton,
            .flexibleSpace(),
            browserMenuButton,
            isExperimentalThemingEnabled ? .additionalFixedSpaceItem() : nil
        ].compactMap { $0 }
    }

    private func createNewTabButtons() -> [UIBarButtonItem] {
        if isExperimentalThemingEnabled {
            return [
                .additionalFixedSpaceItem(),
                passwordsButton,
                .flexibleSpace(),
                bookmarkButton,
                .flexibleSpace(),
                fireBarButtonItem,
                .flexibleSpace(),
                tabSwitcherButton,
                .flexibleSpace(),
                browserMenuButton,
                .additionalFixedSpaceItem()
            ]
        } else {
            return [
                bookmarkButton,
                .flexibleSpace(),
                passwordsButton,
                .flexibleSpace(),
                fireBarButtonItem,
                .flexibleSpace(),
                tabSwitcherButton,
                .flexibleSpace(),
                browserMenuButton
            ]
        }
    }
}

private extension UIBarButtonItem {
    private static let additionalHorizontalSpace = 14.0

    static func additionalFixedSpaceItem() -> UIBarButtonItem {
        .fixedSpace(additionalHorizontalSpace)
    }
}
