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

    @available(iOS 18.4, *)
    init(webExtensionManager: WebExtensionManaging, mainViewController: MainViewController) {
        self.webExtensionManager = webExtensionManager
        self.mainViewController = mainViewController
    }

    // MARK: - Tab Events

    @available(iOS 18.4, *)
    func didOpenTab(_ tabViewController: TabViewController) {
        print("--- didOpenTab")
        webExtensionManager?.eventsListener.didOpenTab(tabViewController)
    }

    @available(iOS 18.4, *)
    func didCloseTab(_ tabViewController: TabViewController, windowIsClosing: Bool = false) {
        print("--- didCloseTab")
        webExtensionManager?.eventsListener.didCloseTab(tabViewController, windowIsClosing: windowIsClosing)
    }

    @available(iOS 18.4, *)
    func didActivateTab(_ tabViewController: TabViewController, previousActiveTab: TabViewController?) {
        print("--- didActivateTab")
        webExtensionManager?.eventsListener.didActivateTab(tabViewController, previousActiveTab: previousActiveTab)
    }

    @available(iOS 18.4, *)
    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tabViewController: TabViewController) {
        print("--- didChangeTabProperties")
        webExtensionManager?.eventsListener.didChangeTabProperties(properties, for: tabViewController)
    }

    @available(iOS 18.4, *)
    func didSelectTabs(_ tabViewControllers: [TabViewController]) {
        print("--- didSelectTabs")
        webExtensionManager?.eventsListener.didSelectTabs(tabViewControllers)
    }

    @available(iOS 18.4, *)
    func didDeselectTabs(_ tabViewControllers: [TabViewController]) {
        print("--- didDeselectTabs")
        webExtensionManager?.eventsListener.didDeselectTabs(tabViewControllers)
    }

    // MARK: - Window Events

    @available(iOS 18.4, *)
    func didOpenWindow() {
        print("--- didOpenWindow")
        guard let mainViewController else { return }
        webExtensionManager?.eventsListener.didOpenWindow(mainViewController)
    }

    @available(iOS 18.4, *)
    func didCloseWindow() {
        print("--- didCloseWindow")
        guard let mainViewController else { return }
        webExtensionManager?.eventsListener.didCloseWindow(mainViewController)
    }

    @available(iOS 18.4, *)
    func didFocusWindow() {
        print("--- didFocusWindow")
        guard let mainViewController else { return }
        webExtensionManager?.eventsListener.didFocusWindow(mainViewController)
    }

    // MARK: - Initial Registration

    @available(iOS 18.4, *)
    func registerExistingTabsAndWindow() {
        print("--- registerExistingTabsAndWindow")
        guard let mainViewController else { return }

        didOpenWindow()

        let tabManager = mainViewController.tabManager
        for tab in tabManager.model.tabs {
            if let tabController = tabManager.controller(for: tab) {
                didOpenTab(tabController)
            }
        }

        if let currentTab = tabManager.current() {
            didActivateTab(currentTab, previousActiveTab: nil)
            didSelectTabs([currentTab])
        }
    }
}
