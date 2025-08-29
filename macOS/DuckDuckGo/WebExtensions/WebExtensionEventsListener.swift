//
//  WebExtensionEventsListener.swift
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

import WebKit

@available(macOS 15.4, *)
protocol WebExtensionEventsListening {

    var controller: WKWebExtensionController? { get set }

    func didOpenWindow(_ window: WKWebExtensionWindow)
    func didCloseWindow(_ window: WKWebExtensionWindow)
    func didFocusWindow(_ window: WKWebExtensionWindow)
    func didOpenTab(_ tab: WKWebExtensionTab)
    func didCloseTab(_ tab: WKWebExtensionTab, windowIsClosing: Bool)
    func didActivateTab(_ tab: WKWebExtensionTab, previousActiveTab: WKWebExtensionTab?)
    func didSelectTabs(_ tabs: [WKWebExtensionTab])
    func didDeselectTabs(_ tabs: [WKWebExtensionTab])
    func didMoveTab(_ tab: WKWebExtensionTab, from oldIndex: Int, in oldWindow: WKWebExtensionWindow)
    func didReplaceTab(_ oldTab: WKWebExtensionTab, with tab: WKWebExtensionTab)
    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tab: WKWebExtensionTab)
}

@available(macOS 15.4, *)
final class WebExtensionEventsListener: WebExtensionEventsListening {

    weak var controller: WKWebExtensionController?

    func didOpenWindow(_ window: WKWebExtensionWindow) {
        controller?.didOpenWindow(window)
    }

    func didCloseWindow(_ window: WKWebExtensionWindow) {
        controller?.didCloseWindow(window)
    }

    func didFocusWindow(_ window: WKWebExtensionWindow) {
        controller?.didFocusWindow(window)
    }

    func didOpenTab(_ tab: WKWebExtensionTab) {
        controller?.didOpenTab(tab)
    }

    func didCloseTab(_ tab: WKWebExtensionTab, windowIsClosing: Bool) {
        controller?.didCloseTab(tab, windowIsClosing: windowIsClosing)
    }

    func didActivateTab(_ tab: WKWebExtensionTab, previousActiveTab: WKWebExtensionTab?) {
        controller?.didActivateTab(tab, previousActiveTab: previousActiveTab)
    }

    func didSelectTabs(_ tabs: [WKWebExtensionTab]) {
        controller?.didSelectTabs(tabs)
    }

    func didDeselectTabs(_ tabs: [WKWebExtensionTab]) {
        controller?.didDeselectTabs(tabs)
    }

    func didMoveTab(_ tab: WKWebExtensionTab, from oldIndex: Int, in oldWindow: WKWebExtensionWindow) {
        controller?.didMoveTab(tab, from: oldIndex, in: oldWindow)
    }

    func didReplaceTab(_ oldTab: WKWebExtensionTab, with tab: WKWebExtensionTab) {
        controller?.didReplaceTab(oldTab, with: tab)
    }

    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tab: WKWebExtensionTab) {
        controller?.didChangeTabProperties(properties, for: tab)
    }

}
