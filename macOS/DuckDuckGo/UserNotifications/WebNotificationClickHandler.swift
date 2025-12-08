//
//  WebNotificationClickHandler.swift
//
//  Copyright © 2024 DuckDuckGo. All rights reserved.
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

import Foundation

/// Protocol for finding and focusing tabs, enabling isolated testing.
@MainActor
protocol WebNotificationTabFinding: AnyObject {
    func findTab(byUUID uuid: String) -> Tab?
    func focusTab(_ tab: Tab)
    func focusBrowser()
}

/// Handles user interactions with web notifications.
///
/// When a user clicks a notification, this handler finds the originating tab,
/// focuses it, and dispatches the click event to JavaScript.
@MainActor
final class WebNotificationClickHandler {

    private let tabFinder: WebNotificationTabFinding

    nonisolated init(tabFinder: WebNotificationTabFinding) {
        self.tabFinder = tabFinder
    }

    /// Handles a notification click by focusing the tab and dispatching the JS event.
    /// - Parameters:
    ///   - tabUUID: The UUID of the tab that created the notification.
    ///   - notificationId: The notification's unique identifier.
    func handleClick(tabUUID: String, notificationId: String) {
        guard let tab = tabFinder.findTab(byUUID: tabUUID) else {
            // Tab was closed; just focus the browser window
            tabFinder.focusBrowser()
            return
        }

        tabFinder.focusTab(tab)
        tab.webNotifications?.sendClickEvent(notificationId: notificationId)
    }
}
