//
//  AIChatSidebarProvider.swift
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

import Foundation

typealias TabIdentifier = String

/// A protocol that defines the interface for managing AI chat sidebars in tabs.
/// This provider handles the lifecycle and state of chat sidebars across multiple browser tabs.
protocol AIChatSidebarProviding: AnyObject {
    /// The width of the chat sidebar in points.
    var sidebarWidth: CGFloat { get }

    /// Returns the chat sidebar instance for the specified tab.
    /// - Parameter tabID: The unique identifier of the tab
    /// - Returns: An `AIChatSidebar` instance associated with the tab
    func sidebar(for tabID: TabIdentifier) -> AIChatSidebar

    /// Checks if a sidebar is currently being displayed for the specified tab.
    /// - Parameter tabID: The unique identifier of the tab
    /// - Returns: `true` if the sidebar is showing, `false` otherwise
    func isShowingSidebar(for tabID: TabIdentifier) -> Bool

    /// Handles cleanup when a sidebar is closed by the user.
    /// - Parameter tabID: The unique identifier of the tab whose sidebar was closed
    func handleSidebarDidClose(for tabID: TabIdentifier)

    /// Removes sidebars for tabs that are no longer active.
    /// - Parameter currentTabIDs: Array of tab IDs that are currently open
    func cleanUp(for currentTabIDs: [TabIdentifier])
}

final class AIChatSidebarProvider: AIChatSidebarProviding {

    enum Constants {
        static let sidebarWidth: CGFloat = 450
    }

    private var sidebarsByTabIDs: [TabIdentifier: AIChatSidebar] = [:]

    var sidebarWidth: CGFloat { Constants.sidebarWidth }

    func sidebar(for tabID: TabIdentifier) -> AIChatSidebar {
        guard let sidebar = sidebarsByTabIDs[tabID] else {
            let sidebar = AIChatSidebar()
            sidebarsByTabIDs[tabID] = sidebar
            return sidebar
        }
        return sidebar
    }

    func isShowingSidebar(for tabID: TabIdentifier) -> Bool {
        return sidebarsByTabIDs[tabID] != nil
    }

    func handleSidebarDidClose(for tabID: TabIdentifier) {
        guard let tabSidebar = sidebarsByTabIDs[tabID] else {
            return
        }
        tabSidebar.sidebarViewController.removeCompletely()
        sidebarsByTabIDs.removeValue(forKey: tabID)
    }

    func cleanUp(for currentTabIDs: [TabIdentifier]) {
        let tabIDsForRemoval = Set(sidebarsByTabIDs.keys).subtracting(currentTabIDs)

        for tabID in tabIDsForRemoval {
            handleSidebarDidClose(for: tabID)
        }
    }
}
