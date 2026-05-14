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

    /// Call this when all extensions are unloaded (e.g. before clearing browser data).
    /// Clears the reported-tab tracking so that registerExistingTabsAndWindow() can
    /// re-register all tabs correctly after extensions are reloaded.
    @available(iOS 18.4, *)
    func extensionsWillUnload() {
        reportedTabUIDs.removeAll()
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

        didOpenWindow()

        // Register all tabs that are already open at extension load time.
        // On iOS, TabViewControllers are created lazily — only the active tab is guaranteed
        // to have a controller in memory. For tabs that already have a controller, we notify
        // immediately. For tabs whose controller hasn't been created yet, the cacheDelegate
        // will fire didOpenTab via didCreateController the first time the user activates them.
        //
        // The cacheDelegate is set here — after loadInstalledExtensions() has run — so that
        // controller creation events during app startup don't record UIDs into reportedTabUIDs
        // before the extension is ready to receive them.
        let tabManager = mainViewController.tabManager
        tabManager.cacheDelegate = self
        for tab in tabManager.allTabsModel.tabs {
            if let tabController = tabManager.controller(for: tab) {
                didOpenTab(tabController)
            }
        }

        // Report the current selection state so the extension has an accurate picture
        // of which tab is active right now.
        if let currentTab = tabManager.current() {
            didActivateTab(currentTab, previousActiveTab: nil)
            didSelectTabs([currentTab])
        }
    }
}

// MARK: - TabControllerCacheDelegate

extension WebExtensionEventsCoordinator: TabControllerCacheDelegate {

    func tabManager(_ tabManager: TabManager, didCreateController controller: TabViewController) {
        guard #available(iOS 18.4, *) else { return }
        guard !reportedTabUIDs.contains(controller.tabModel.uid) else { return }
        didOpenTab(controller)
    }

    // When a background tab's WebKit process terminates, its controller is evicted from
    // the cache. The tab still exists in the model, so we must not call didCloseTab —
    // extensions would drop the tab from their state entirely. Instead, just remove the UID
    // from reportedTabUIDs so that didOpenTab fires correctly for the replacement controller
    // when the user next activates the tab.
    func tabManager(_ tabManager: TabManager, didInvalidateController controller: TabViewController) {
        guard #available(iOS 18.4, *) else { return }
        reportedTabUIDs.remove(controller.tabModel.uid)
    }
}
