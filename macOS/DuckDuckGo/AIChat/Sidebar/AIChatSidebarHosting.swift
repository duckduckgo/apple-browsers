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

/// Receives live resize events from the sidebar resize handle and layout changes.
@MainActor
protocol AIChatSidebarResizeDelegate: AnyObject {
    /// Called continuously during a drag with the proposed width.
    /// Returns the actual (clamped) width that was applied.
    @discardableResult
    func sidebarHostDidResize(to width: CGFloat) -> CGFloat

    /// Called once when the drag ends with the final width.
    func sidebarHostDidFinishResize(to width: CGFloat)

    /// Called when the host's available width changes (e.g. window resize).
    /// The presenter uses this to shrink the sidebar proportionally when space is tight.
    func sidebarHostDidChangeAvailableWidth(_ availableWidth: CGFloat)
}

/// A protocol that defines the requirements for hosting the AI Chat sidebar in a view controller.
///
/// This protocol provides the necessary properties and methods to manage the AI Chat sidebar's
/// layout, embedding, and tab-related functionality within a host view controller.
@MainActor
protocol AIChatSidebarHosting: AnyObject  {
    /// The delegate that receives tab-related events from the sidebar.
    var aiChatSidebarHostingDelegate: AIChatSidebarHostingDelegate? { get set }

    /// The delegate that receives resize events from the sidebar drag handle.
    var aiChatSidebarResizeDelegate: AIChatSidebarResizeDelegate? { get set }

    /// Tells if the sidebar host is in the key application window.
    var isInKeyWindow: Bool { get }

    /// The identifier of the currently active tab, if any.
    var currentTabID: TabIdentifier? { get }

    /// The layout constraint controlling the leading edge position of the sidebar container.
    var sidebarContainerLeadingConstraint: NSLayoutConstraint? { get }

    /// The layout constraint controlling the width of the sidebar container.
    var sidebarContainerWidthConstraint: NSLayoutConstraint? { get }

    /// Switches to the given tab and embeds the provided view controller as the sidebar content.
    /// - Parameters:
    ///   - vc: The view controller to embed as the sidebar content.
    ///   - tabID: If provided, the host switches to this tab before embedding.
    func embedChatViewController(_ vc: NSViewController, for tabID: TabIdentifier?)

    /// The burner mode status of the current tab (private browsing mode).
    var burnerMode: BurnerMode { get }

    /// Updates the sidebar width and leading constraint to the given value without animation.
    /// Used during live resize drags.
    func applySidebarWidth(_ width: CGFloat)

    /// Shows or hides the resize handle on the sidebar's leading edge.
    func setResizeHandleVisible(_ visible: Bool)

    /// The total width available for both the webview and sidebar.
    var availableWidth: CGFloat { get }
    /// The sidebar container's frame in screen coordinates, used for "pop off in place" positioning.
    var sidebarContainerScreenFrame: NSRect? { get }

    /// Switches the active tab to the one identified by `tabID`.
    func selectTab(with tabID: TabIdentifier)
}

extension BrowserTabViewController: AIChatSidebarHosting {

    var isInKeyWindow: Bool {
        view.window?.isKeyWindow ?? false
    }

    var currentTabID: TabIdentifier? {
        tabViewModel?.tab.uuid
    }

    func embedChatViewController(_ chatViewController: NSViewController, for tabID: TabIdentifier?) {
        if let tabID {
            selectTab(with: tabID)
        }

        // Keep exactly one AI Chat VC attached to the sidebar container.
        // Without this, tab switches can leave multiple chat VCs stacked,
        // and the "already embedded" fast-path can show stale content.
        children
            .filter { $0 !== chatViewController && $0.view.superview === sidebarContainer }
            .forEach { $0.removeCompletely() }

        if chatViewController.parent === self,
           chatViewController.view.superview === sidebarContainer {
            return
        }

        chatViewController.removeFromParent()
        chatViewController.view.removeFromSuperview()
        addAndLayoutChild(chatViewController, into: sidebarContainer)
    }

    var burnerMode: BurnerMode {
        tabViewModel?.tab.burnerMode ?? .regular
    }

    func applySidebarWidth(_ width: CGFloat) {
        sidebarContainerWidthConstraint?.constant = width
        sidebarContainerLeadingConstraint?.constant = -width
    }

    func setResizeHandleVisible(_ visible: Bool) {
        sidebarResizeHandle.isHidden = !visible
    }

    var availableWidth: CGFloat {
        view.bounds.width
    }
    var sidebarContainerScreenFrame: NSRect? {
        guard let window = view.window else { return nil }
        let frameInWindow = sidebarContainer.convert(sidebarContainer.bounds, to: nil)
        return window.convertToScreen(frameInWindow)
    }
}
