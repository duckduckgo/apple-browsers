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

import Combine
import Foundation
import FeatureFlags
import BrowserServicesKit

typealias TabIdentifier = String
typealias AIChatSidebarsByTab = [TabIdentifier: AIChatSidebar]

/// A protocol that defines the interface for managing AI chat sidebars in tabs.
/// This provider handles the lifecycle and state of chat sidebars across multiple browser tabs.
protocol AIChatSidebarProviding: AnyObject {
    /// The width of the chat sidebar in points.
    var sidebarWidth: CGFloat { get }

    /// Returns the existing cached sidebar view controller for the specified tab, if one exists.
    /// - Parameter tabID: The unique identifier of the tab
    /// - Returns: An `AIChatSidebarViewController` instance associated with the tab, or `nil` if no view controller exists
    func getSidebarViewController(for tabID: TabIdentifier) -> AIChatSidebarViewController?

    /// Creates and caches a new sidebar view controller for the specified tab.
    /// - Parameters:
    ///   - tabID: The unique identifier of the tab
    ///   - burnerMode: The burner mode configuration for the sidebar
    /// - Returns: A newly created `AIChatSidebarViewController` instance
    func makeSidebarViewController(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSidebarViewController

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

    /// Publishes events whenever `sidebarsByTab` gets updated.
    var sidebarsByTabPublisher: AnyPublisher<AIChatSidebarsByTab, Never> { get }

    /// Restores the sidebar provider's state from a previously saved model.
    /// This method cleans up all existing sidebars and replaces the current model with the provided one.
    /// - Parameter model: The sidebar model to restore, containing tab IDs mapped to their chat sidebars
    func restoreState(_ sidebarsByTab: AIChatSidebarsByTab)
}

final class AIChatSidebarProvider: AIChatSidebarProviding {

    enum Constants {
        static let sidebarWidth: CGFloat = 400
    }

    private let featureFlagger: FeatureFlagger

    var sidebarWidth: CGFloat { Constants.sidebarWidth }

    @Published private(set) var sidebarsByTab: AIChatSidebarsByTab

    var sidebarsByTabPublisher: AnyPublisher<AIChatSidebarsByTab, Never> {
        $sidebarsByTab.dropFirst().eraseToAnyPublisher()
    }

    private var shouldKeepSession: Bool {
        featureFlagger.isFeatureOn(.aiChatKeepSession)
    }

    init(sidebarsByTab: AIChatSidebarsByTab? = nil,
         featureFlagger: FeatureFlagger) {
        self.sidebarsByTab = sidebarsByTab ?? [:]
        self.featureFlagger = featureFlagger
    }

    func getSidebarViewController(for tabID: TabIdentifier) -> AIChatSidebarViewController? {
        return sidebarsByTab[tabID]?.sidebarViewController
    }

    func makeSidebarViewController(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSidebarViewController {
        let sidebar = getCurrentSidebar(for: tabID, burnerMode: burnerMode)

        if let existingViewController = sidebar.sidebarViewController {
            return existingViewController
        }

        let sidebarViewController = AIChatSidebarViewController(currentAIChatURL: sidebar.currentAIChatURL, burnerMode: burnerMode)
        if let restorationData = sidebar.restorationData {
            sidebarViewController.setAIChatRestorationData(restorationData)
        }
        sidebar.sidebarViewController = sidebarViewController

        return sidebarViewController
    }

    private func getCurrentSidebar(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSidebar {
        let aiChatRemoteSettings = AIChatRemoteSettings()
        var currentSidebar = sidebarsByTab[tabID]

        if let existingSidebar = currentSidebar,
           let hiddenAt = existingSidebar.hiddenAt,
           hiddenAt.minutesSinceNow() > aiChatRemoteSettings.sessionTimeoutMinutes {
            // If the sidebar was hidden past the session timeout setting unload it and create a new one
            existingSidebar.unloadViewController(persistingState: shouldKeepSession)
            sidebarsByTab.removeValue(forKey: tabID)

            currentSidebar = nil
        }

        return currentSidebar ?? makeSidebar(for: tabID, burnerMode: burnerMode)
    }

    private func makeSidebar(for tabID: TabIdentifier, burnerMode: BurnerMode) -> AIChatSidebar {
        let sidebar = AIChatSidebar(burnerMode: burnerMode)
        sidebarsByTab[tabID] = sidebar
        return sidebar
    }

    func isShowingSidebar(for tabID: TabIdentifier) -> Bool {
        sidebarsByTab[tabID]?.isPresented ?? false
    }

    func handleSidebarDidClose(for tabID: TabIdentifier) {
        sidebarsByTab[tabID]?.unloadViewController(persistingState: shouldKeepSession) // This already calls setHidden() internally

        // If keep session is disables always remove sidebar data model
        if !shouldKeepSession {
            sidebarsByTab.removeValue(forKey: tabID)
        }
    }

    func cleanUp(for currentTabIDs: [TabIdentifier]) {
        let tabIDsForRemoval = Set(sidebarsByTab.keys).subtracting(currentTabIDs)

        for tabID in tabIDsForRemoval {
            handleSidebarDidClose(for: tabID)
            sidebarsByTab.removeValue(forKey: tabID)
        }
    }

    func restoreState(_ sidebarsByTab: AIChatSidebarsByTab) {
        cleanUp(for: [])
        self.sidebarsByTab = sidebarsByTab
    }
}
