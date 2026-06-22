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
import os.log

@available(macOS 15.4, iOS 18.4, *)
public protocol WebExtensionEventsListening {

    var controller: WKWebExtensionController? { get set }
    var droppedCallbacksCount: Int { get }

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

@available(macOS 15.4, iOS 18.4, *)
public final class WebExtensionEventsListener: WebExtensionEventsListening {

    public weak var controller: WKWebExtensionController?
    public private(set) var droppedCallbacksCount = 0

    public init() {}

    public func didOpenWindow(_ window: WKWebExtensionWindow) {
        notifyController { $0.didOpenWindow(window) }
    }

    public func didCloseWindow(_ window: WKWebExtensionWindow) {
        notifyController { $0.didCloseWindow(window) }
    }

    public func didFocusWindow(_ window: WKWebExtensionWindow) {
        notifyController { $0.didFocusWindow(window) }
    }

    public func didOpenTab(_ tab: WKWebExtensionTab) {
        notifyController { $0.didOpenTab(tab) }
    }

    public func didCloseTab(_ tab: WKWebExtensionTab, windowIsClosing: Bool) {
        notifyController { $0.didCloseTab(tab, windowIsClosing: windowIsClosing) }
    }

    public func didActivateTab(_ tab: WKWebExtensionTab, previousActiveTab: WKWebExtensionTab?) {
        notifyController { $0.didActivateTab(tab, previousActiveTab: previousActiveTab) }
    }

    public func didSelectTabs(_ tabs: [WKWebExtensionTab]) {
        notifyController { $0.didSelectTabs(tabs) }
    }

    public func didDeselectTabs(_ tabs: [WKWebExtensionTab]) {
        notifyController { $0.didDeselectTabs(tabs) }
    }

    public func didMoveTab(_ tab: WKWebExtensionTab, from oldIndex: Int, in oldWindow: WKWebExtensionWindow) {
        notifyController { $0.didMoveTab(tab, from: oldIndex, in: oldWindow) }
    }

    public func didReplaceTab(_ oldTab: WKWebExtensionTab, with tab: WKWebExtensionTab) {
        notifyController { $0.didReplaceTab(oldTab, with: tab) }
    }

    public func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tab: WKWebExtensionTab) {
        notifyController { $0.didChangeTabProperties(properties, for: tab) }
    }

    private func notifyController(_ callback: (WKWebExtensionController) -> Void, caller: String = #function) {
        guard let controller else {
            droppedCallbacksCount += 1
            Logger.webExtensions.warning("⚠️ Dropped web extension callback '\(caller, privacy: .public)' — controller is nil (total dropped: \(self.droppedCallbacksCount, privacy: .public))")
            return
        }

        callback(controller)
    }
}
