//
//  WebExtensionEventsCoordinator+iOS.swift
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

@available(iOS 18.4, *)
@MainActor
final class WebExtensionEventsCoordinator {

    private weak var webExtensionManager: WebExtensionManaging?
    private weak var mainViewController: MainViewController?

    init(webExtensionManager: WebExtensionManaging, mainViewController: MainViewController) {
        self.webExtensionManager = webExtensionManager
        self.mainViewController = mainViewController
    }

    // MARK: - Tab Events

    func didOpenTab(_ tabViewController: TabViewController) {
        webExtensionManager?.eventsListener.didOpenTab(tabViewController)
    }

    func didCloseTab(_ tabViewController: TabViewController, windowIsClosing: Bool = false) {
        webExtensionManager?.eventsListener.didCloseTab(tabViewController, windowIsClosing: windowIsClosing)
    }

    func didActivateTab(_ tabViewController: TabViewController, previousActiveTab: TabViewController?) {
        webExtensionManager?.eventsListener.didActivateTab(tabViewController, previousActiveTab: previousActiveTab)
    }

    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tabViewController: TabViewController) {
        webExtensionManager?.eventsListener.didChangeTabProperties(properties, for: tabViewController)
    }

    // MARK: - Window Events

    func didFocusWindow() {
        guard let mainViewController else { return }
        webExtensionManager?.eventsListener.didFocusWindow(mainViewController)
    }
}
