//
//  AIChatSidebarHosting.swift
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
import AppKit

/// A delegate protocol that handles tab-related events from the AI Chat sidebar.
///
/// This delegate is responsible for handling tab selection and tab list updates
/// that occur within the AI Chat sidebar interface.
@MainActor
protocol AIChatSidebarHostingDelegate: AnyObject {
    /// Called when a tab is selected in the AI Chat sidebar.
    /// - Parameter tabID: The unique identifier of the selected tab.
    func sidebarHostDidSelectTab(with tabID: TabIdentifier)

    /// Called when the list of tabs in the AI Chat sidebar is updated.
    /// - Parameter currentTabIDs: An array of tab identifiers representing the current state of tabs.
    func sidebarHostDidUpdateTabs()
}

/// A protocol that defines the requirements for hosting the AI Chat sidebar in a view controller.
///
/// This protocol provides the necessary properties and methods to manage the AI Chat sidebar's
/// layout, embedding, and tab-related functionality within a host view controller.
@MainActor
protocol AIChatSidebarHosting: AnyObject  {
    /// The delegate that receives tab-related events from the sidebar.
    var aiChatSidebarHostingDelegate: AIChatSidebarHostingDelegate? { get set }

    /// Tells if the sidebar host is in the key application window.
    var isInKeyWindow: Bool { get }

    /// The identifier of the currently active tab, if any.
    var currentTabID: TabIdentifier? { get }

    /// The layout constraint controlling the leading edge position of the sidebar container.
    var sidebarContainerLeadingConstraint: NSLayoutConstraint? { get }

    /// The layout constraint controlling the width of the sidebar container.
    var sidebarContainerWidthConstraint: NSLayoutConstraint? { get }

    /// Embeds the provided view controller as the sidebar content.
    /// - Parameter vc: The view controller to embed as the sidebar content.
    func embedSidebarViewController(_ vc: NSViewController)
}

extension BrowserTabViewController: AIChatSidebarHosting {

    var isInKeyWindow: Bool {
        view.window?.isKeyWindow ?? false
    }

    var currentTabID: TabIdentifier? {
        tabViewModel?.tab.uuid
    }

    func embedSidebarViewController(_ sidebarViewController: NSViewController) {
        addAndLayoutChild(sidebarViewController, into: sidebarContainer)
    }

}
