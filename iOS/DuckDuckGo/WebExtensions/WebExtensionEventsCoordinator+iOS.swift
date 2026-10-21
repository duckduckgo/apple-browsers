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

    /// Controllers of tabs whose WebKit process was terminated and whose controller was evicted,
    /// kept (keyed by `tabModel.uid`) until a replacement controller is created, so the swap can be
    /// reported as didReplaceTab and the tab keeps its extension identity rather than getting a new
    /// tab id. Closed instead if the tab is removed while still evicted.
    private var invalidatedControllersByTabUID = [String: TabViewController]()

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
        let uid = tabViewController.tabModel.uid
        reportedTabUIDs.remove(uid)
        invalidatedControllersByTabUID.removeValue(forKey: uid)
        webExtensionManager?.eventsListener.didCloseTab(tabViewController, windowIsClosing: windowIsClosing)
    }

    /// Closes a tab identified by its model, resolving the controller from the live cache or — when
    /// the tab's WebKit process was evicted — from the retained one, so it's reported right away.
    @available(iOS 18.4, *)
    func didCloseTab(_ tab: Tab, windowIsClosing: Bool = false) {
        guard let controller = mainViewController?.tabManager.controller(for: tab)
                ?? invalidatedControllersByTabUID[tab.uid] else { return }
        didCloseTab(controller, windowIsClosing: windowIsClosing)
    }

    /// Call this when all extensions are unloaded (e.g. before clearing browser data).
    /// Clears the reported-tab tracking so that registerExistingTabsAndWindow() can
    /// re-register all tabs correctly after extensions are reloaded.
    @available(iOS 18.4, *)
    func extensionsWillUnload() {
        reportedTabUIDs.removeAll()
        invalidatedControllersByTabUID.removeAll()
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
        pruneInvalidatedControllers()

        let uid = controller.tabModel.uid

        // Replacing an evicted controller: report a replacement, not a new open, so the tab keeps
        // its extension identity.
        if let oldController = invalidatedControllersByTabUID.removeValue(forKey: uid), oldController !== controller {
            reportedTabUIDs.insert(uid)
            webExtensionManager?.eventsListener.didReplaceTab(oldController, with: controller)
            return
        }

        guard !reportedTabUIDs.contains(uid) else { return }
        didOpenTab(controller)
    }

    func tabManager(_ tabManager: TabManager,
                    didEvictController controller: TabViewController,
                    reason: TabControllerCacheEvictionReason) {
        guard #available(iOS 18.4, *) else { return }
        pruneInvalidatedControllers()
        switch reason {
        case .webContentProcessTermination:
            invalidatedControllersByTabUID[controller.tabModel.uid] = controller
        case .memoryWarning, .lruCapacity:
            didCloseTab(controller)
        }
    }

    /// Reports retained controllers whose tab is gone from the model as closed, so the extension
    /// stops tracking tabs that were removed while evicted.
    @available(iOS 18.4, *)
    private func pruneInvalidatedControllers() {
        guard !invalidatedControllersByTabUID.isEmpty, let tabManager = mainViewController?.tabManager else { return }
        let liveTabUIDs = Set(tabManager.allTabsModel.tabs.map(\.uid))
        let staleTabUIDs = invalidatedControllersByTabUID.keys.filter { !liveTabUIDs.contains($0) }
        for uid in staleTabUIDs {
            guard let oldController = invalidatedControllersByTabUID.removeValue(forKey: uid) else { continue }
            reportedTabUIDs.remove(uid)
            webExtensionManager?.eventsListener.didCloseTab(oldController, windowIsClosing: false)
        }
    }
}
