//
//  NavigationHotkeyHandler.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
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
import Foundation
import Navigation
final class NavigationHotkeyHandler {

    private var onNewWindow: ((WKNavigationAction?) -> NavigationDecision)?
    private let isTabPinned: () -> Bool
    private let isBurner: Bool

    init(isTabPinned: @escaping () -> Bool, isBurner: Bool) {
        self.isTabPinned = isTabPinned
        self.isBurner = isBurner
    }

}

extension NavigationHotkeyHandler: NewWindowPolicyDecisionMaker {

    func decideNewWindowPolicy(for navigationAction: WKNavigationAction) -> NavigationDecision? {
        defer {
            onNewWindow = nil
        }
        return onNewWindow?(navigationAction)
    }

}

extension NavigationHotkeyHandler: NavigationResponder {

    func decidePolicy(for navigationAction: NavigationAction, preferences: inout NavigationPreferences) async -> NavigationActionPolicy? {
        guard let targetFrame = navigationAction.targetFrame else { return .next }

        let isLinkActivated = !navigationAction.isTargetingNewWindow
            && (navigationAction.navigationType.isLinkActivated || (navigationAction.navigationType == .other && navigationAction.isUserInitiated))

        let isNavigatingAwayFromPinnedTab: Bool = {
            let isNavigatingToAnotherDomain = navigationAction.url.host != targetFrame.url.host && !targetFrame.url.isEmpty
            return isLinkActivated && self.isTabPinned() && isNavigatingToAnotherDomain && navigationAction.isForMainFrame
        }()

        // Don‘t interrupt Navigation Actions already targeting a new window as it will cause extra empty tabs opening
        guard isLinkActivated || isNavigatingAwayFromPinnedTab else { return .next }

        // Get the open behavior with canOpenLinkInCurrentTab=false for pinned tabs
        let canOpenLinkInCurrentTab = !isNavigatingAwayFromPinnedTab
        let button: NSEvent.Button = navigationAction.navigationType.isMiddleButtonClick ? .middle : .left
        let switchToNewTabWhenOpened = TabsPreferences.shared.switchToNewTabWhenOpened

        let linkOpenBehavior = LinkOpenBehavior(button: button, modifierFlags: NSApp.currentEvent?.modifierFlags ?? [], switchToNewTabWhenOpenedPreference: switchToNewTabWhenOpened, canOpenLinkInCurrentTab: canOpenLinkInCurrentTab)

        // Handle behavior for navigation
        switch linkOpenBehavior {
        case .currentTab:
            return .next

        case .newTab(let selected), .newWindow(let selected):
            self.onNewWindow = { [isBurner] _ in
                if case .newWindow = linkOpenBehavior {
                    return .allow(.window(active: selected, burner: isBurner))
                } else {
                    return .allow(.tab(selected: selected, burner: isBurner))
                }
            }
            targetFrame.webView?.loadInNewWindow(navigationAction.url)
            return .cancel
        }
    }

}

protocol NavigationHotkeyHandlerProtocol: AnyObject, NewWindowPolicyDecisionMaker, NavigationResponder {
}

extension NavigationHotkeyHandler: TabExtension, NavigationHotkeyHandlerProtocol {
    func getPublicProtocol() -> NavigationHotkeyHandlerProtocol { self }
}

extension TabExtensions {
    var navigationHotkeyHandler: NavigationHotkeyHandlerProtocol? {
        resolve(NavigationHotkeyHandler.self)
    }
}
