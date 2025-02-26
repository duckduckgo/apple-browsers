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

/*

 - (void)didOpenWindow:(id <WKWebExtensionWindow>)newWindow NS_SWIFT_NAME(didOpenWindow(_:));
 - (void)didCloseWindow:(id <WKWebExtensionWindow>)closedWindow NS_SWIFT_NAME(didCloseWindow(_:));
 - (void)didFocusWindow:(nullable id <WKWebExtensionWindow>)focusedWindow NS_SWIFT_NAME(didFocusWindow(_:));

 - (void)didOpenTab:(id <WKWebExtensionTab>)newTab NS_SWIFT_NAME(didOpenTab(_:));
 - (void)didCloseTab:(id <WKWebExtensionTab>)closedTab windowIsClosing:(BOOL)windowIsClosing NS_SWIFT_NAME(didCloseTab(_:windowIsClosing:));
 - (void)didActivateTab:(id<WKWebExtensionTab>)activatedTab previousActiveTab:(nullable id<WKWebExtensionTab>)previousTab NS_SWIFT_NAME(didActivateTab(_:previousActiveTab:));
 - (void)didSelectTabs:(NSSet<id <WKWebExtensionTab>> *)selectedTabs NS_SWIFT_NAME(didSelectTabs(_:));
 - (void)didDeselectTabs:(NSSet<id <WKWebExtensionTab>> *)deselectedTabs NS_SWIFT_NAME(didDeselectTabs(_:));
 - (void)didMoveTab:(id <WKWebExtensionTab>)movedTab fromIndex:(NSUInteger)index inWindow:(nullable id <WKWebExtensionWindow>)oldWindow NS_SWIFT_NAME(didMoveTab(_:from:in:));
 - (void)didReplaceTab:(id <WKWebExtensionTab>)oldTab withTab:(id <WKWebExtensionTab>)newTab NS_SWIFT_NAME(didReplaceTab(_:with:));
 - (void)didChangeTabProperties:(WKWebExtensionTabChangedProperties)properties forTab:(id <WKWebExtensionTab>)changedTab NS_SWIFT_NAME(didChangeTabProperties(_:for:));

 @end

 */
@available(macOS 15.3, *)
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

@available(macOS 15.3, *)
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
        let set = NSSet(array: tabs) as Set
        controller?.didSelectTabs(set)
    }

    func didDeselectTabs(_ tabs: [WKWebExtensionTab]) {
        let set = NSSet(array: tabs) as Set
        controller?.didDeselectTabs(set)
    }

    func didMoveTab(_ tab: WKWebExtensionTab, from oldIndex: Int, in oldWindow: WKWebExtensionWindow) {
        controller?.didMoveTab(tab, from: UInt(oldIndex), in: oldWindow)
    }

    func didReplaceTab(_ oldTab: WKWebExtensionTab, with tab: WKWebExtensionTab) {
        controller?.didReplaceTab(oldTab, with: tab)
    }

    func didChangeTabProperties(_ properties: WKWebExtension.TabChangedProperties, for tab: WKWebExtensionTab) {
        controller?.didChangeTabProperties(properties, for: tab)
    }

}
