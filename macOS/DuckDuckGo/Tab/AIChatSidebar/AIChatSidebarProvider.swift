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
typealias AIChatSidebarsByTab = [TabIdentifier: AIChatSidebar]

/// A protocol that defines the interface for managing AI chat sidebars in tabs.
/// This provider handles the lifecycle and state of chat sidebars across multiple browser tabs.
protocol AIChatSidebarProviding: AnyObject {
    /// The width of the chat sidebar in points.
    var sidebarWidth: CGFloat { get }

    /// Returns the existing cached chat sidebar instance for the specified tab, if one exists.
    /// - Parameter tabID: The unique identifier of the tab
    /// - Returns: An `AIChatSidebar` instance associated with the tab, or `nil` if no sidebar exists
    func getSidebar(for tabID: TabIdentifier) -> AIChatSidebar?

    /// Creates and caches a new chat sidebar instance for the specified tab.
    /// - Parameters:
    ///   - tabID: The unique identifier of the tab
    ///   - burnerMode: The burner mode configuration for the sidebar
    /// - Returns: A newly created `AIChatSidebar` instance
    func makeSidebar(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSidebar

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

    /// The underlying model containing all active chat sidebars mapped by their tab identifiers.
    /// This dictionary maintains the state of all chat sidebars across different browser tabs.
    var sidebarsByTab: AIChatSidebarsByTab { get }

    /// Restores the sidebar provider's state from a previously saved model.
    /// This method cleans up all existing sidebars and replaces the current model with the provided one.
    /// - Parameter model: The sidebar model to restore, containing tab IDs mapped to their chat sidebars
    func restoreState(_ sidebarsByTab: AIChatSidebarsByTab)
}

final class AIChatSidebarProvider: AIChatSidebarProviding {

    enum Constants {
        static let sidebarWidth: CGFloat = 400
    }

    var sidebarWidth: CGFloat { Constants.sidebarWidth }

    private(set) var sidebarsByTab: AIChatSidebarsByTab

    init(sidebarsByTab: AIChatSidebarsByTab? = nil) {
        self.sidebarsByTab = sidebarsByTab ?? [:]
    }

    func getSidebar(for tabID: TabIdentifier) -> AIChatSidebar? {
        return sidebarsByTab[tabID]
    }

    func makeSidebar(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSidebar {
        let sidebar = AIChatSidebar(burnerMode: burnerMode)
        sidebarsByTab[tabID] = sidebar
        return sidebar
    }

    func isShowingSidebar(for tabID: TabIdentifier) -> Bool {
        return getSidebar(for: tabID) != nil
    }

    func handleSidebarDidClose(for tabID: TabIdentifier) {
        guard let tabSidebar = getSidebar(for: tabID) else {
            return
        }
        tabSidebar.sidebarViewController.stopLoading()
        tabSidebar.sidebarViewController.removeCompletely()
        sidebarsByTab.removeValue(forKey: tabID)
    }

    func cleanUp(for currentTabIDs: [TabIdentifier]) {
        let tabIDsForRemoval = Set(sidebarsByTab.keys).subtracting(currentTabIDs)

        for tabID in tabIDsForRemoval {
            handleSidebarDidClose(for: tabID)
        }
    }

    func restoreState(_ sidebarsByTab: AIChatSidebarsByTab) {
        cleanUp(for: [])
        self.sidebarsByTab = sidebarsByTab
    }
}
