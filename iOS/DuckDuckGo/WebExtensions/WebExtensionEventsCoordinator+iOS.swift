//
//  WebExtensionEventsCoordinator+iOS.swift
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
import WebKit
import WebExtensions

@MainActor
final class WebExtensionEventsCoordinator {

    private weak var webExtensionManager: WebExtensionManaging?
    private weak var mainViewController: MainViewController?

    /// Tracks UIDs of tabs that have already been reported to the extension via didOpenTab,
    /// preventing duplicate notifications when a controller is lazily recreated.
    private var reportedTabUIDs = Set<String>()

    @available(iOS 18.4, *)
    init(webExtensionManager: WebExtensionManaging, mainViewController: MainViewController) {
        self.webExtensionManager = webExtensionManager
        self.mainViewController = mainViewController

        // Observe TabManager so that any time a TabViewController is first created —
        // whether eagerly (new tab) or lazily (existing tab activated for the first time) —
        // we fire didOpenTab if this tab hasn't been reported yet.
        mainViewController.tabManager.onTabControllerCreated = { [weak self] controller in
            guard let self, !self.reportedTabUIDs.contains(controller.tabModel.uid) else { return }
            self.didOpenTab(controller)
        }
    }

    // MARK: - Tab Events

    @available(iOS 18.4, *)
    func didOpenTab(_ tabViewController: TabViewController) {
        guard reportedTabUIDs.insert(tabViewController.tabModel.uid).inserted else { return }
        webExtensionManager?.eventsListener.didOpenTab(tabViewController)
    }

    @available(iOS 18.4, *)
    func didCloseTab(_ tabViewController: TabViewController, windowIsClosing: Bool = false) {
        reportedTabUIDs.remove(tabViewController.tabModel.uid)
        webExtensionManager?.eventsListener.didCloseTab(tabViewController, windowIsClosing: windowIsClosing)
    }

    @available(iOS 18.4, *)
    func didActivateTab(_ tabViewController: TabViewController, previousActiveTab: TabViewController?) {
        webExtensionManager?.eventsListener.didActivateTab(tabViewController, previousActiveTab: previousActiveTab)
    }

    @available(iOS 18.4, *)
    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tabViewController: TabViewController) {
        webExtensionManager?.eventsListener.didChangeTabProperties(properties, for: tabViewController)
    }

    @available(iOS 18.4, *)
    func didSelectTabs(_ tabViewControllers: [TabViewController]) {
        webExtensionManager?.eventsListener.didSelectTabs(tabViewControllers)
    }

    @available(iOS 18.4, *)
    func didDeselectTabs(_ tabViewControllers: [TabViewController]) {
        webExtensionManager?.eventsListener.didDeselectTabs(tabViewControllers)
    }

    // MARK: - Window Events

    @available(iOS 18.4, *)
    func didOpenWindow() {
        guard let mainViewController else { return }
        webExtensionManager?.eventsListener.didOpenWindow(mainViewController)
    }

    @available(iOS 18.4, *)
    func didCloseWindow() {
        guard let mainViewController else { return }
        webExtensionManager?.eventsListener.didCloseWindow(mainViewController)
    }

    @available(iOS 18.4, *)
    func didFocusWindow() {
        guard let mainViewController else { return }
        webExtensionManager?.eventsListener.didFocusWindow(mainViewController)
    }

    // MARK: - Initial Registration

    @available(iOS 18.4, *)
    func registerExistingTabsAndWindow() {
        guard let mainViewController else { return }

        // Tell the extension about the single iOS window.
        didOpenWindow()

        // Register all tabs that are already open at extension load time.
        // On iOS, TabViewControllers are created lazily — only the active tab is guaranteed
        // to have a controller in memory. For tabs that already have a controller, we notify
        // immediately. For tabs whose controller hasn't been created yet, the onTabControllerCreated
        // callback wired in init will fire didOpenTab the first time the user activates them.
        let tabManager = mainViewController.tabManager
        for tab in tabManager.model.tabs {
            if let tabController = tabManager.controller(for: tab) {
                didOpenTab(tabController)
            }
            // No else needed: unreported tabs will be caught by onTabControllerCreated.
        }

        // Report the current selection state so the extension has an accurate picture
        // of which tab is active right now.
        if let currentTab = tabManager.current() {
            didActivateTab(currentTab, previousActiveTab: nil)
            didSelectTabs([currentTab])
        }
    }
}
