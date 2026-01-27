//
//  WebExtensionEventsListenerMock.swift
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
@testable import WebExtensions

@available(macOS 15.4, *)
final class WebExtensionEventsListenerMock: WebExtensionEventsListening {

    var controller: WKWebExtensionController?

    var didOpenWindowCalled = false
    func didOpenWindow(_ window: WKWebExtensionWindow) {
        didOpenWindowCalled = true
    }

    var didCloseWindowCalled = false
    func didCloseWindow(_ window: WKWebExtensionWindow) {
        didCloseWindowCalled = true
    }

    var didFocusWindowCalled = false
    func didFocusWindow(_ window: WKWebExtensionWindow) {
        didFocusWindowCalled = true
    }

    var didOpenTabCalled = false
    func didOpenTab(_ tab: WKWebExtensionTab) {
        didOpenTabCalled = true
    }

    var didCloseTabCalled = false
    func didCloseTab(_ tab: WKWebExtensionTab, windowIsClosing: Bool) {
        didCloseTabCalled = true
    }

    var didActivateTabCalled = false
    func didActivateTab(_ tab: WKWebExtensionTab, previousActiveTab: WKWebExtensionTab?) {
        didActivateTabCalled = true
    }

    var didSelectTabsCalled = false
    func didSelectTabs(_ tabs: [WKWebExtensionTab]) {
        didSelectTabsCalled = true
    }

    var didDeselectTabsCalled = false
    func didDeselectTabs(_ tabs: [WKWebExtensionTab]) {
        didDeselectTabsCalled = true
    }

    var didMoveTabCalled = false
    func didMoveTab(_ tab: WKWebExtensionTab, from oldIndex: Int, in oldWindow: WKWebExtensionWindow) {
        didMoveTabCalled = true
    }

    var didReplaceTabCalled = false
    func didReplaceTab(_ oldTab: WKWebExtensionTab, with tab: WKWebExtensionTab) {
        didReplaceTabCalled = true
    }

    var didChangeTabPropertiesCalled = false
    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tab: WKWebExtensionTab) {
        didChangeTabPropertiesCalled = true
    }
}
