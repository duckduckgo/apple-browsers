//
//  TabCollection.swift
//
//  Copyright © 2020 DuckDuckGo. All rights reserved.
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

import AppKit
import Foundation
import Combine
import History

final class TabCollection: NSObject {

    /// When true, this collection is used by a popup window and must contain at most one tab
    let isPopup: Bool

    @Published private(set) var tabs: [AnyTab]

    var loadedTabs: [Tab] {
        tabs.compactMap {
            guard case .loaded(let tab) = $0 else { return nil }
            return tab
        }
    }

    var loadedTabsPublisher: AnyPublisher<[Tab], Never> {
        $tabs.map { tabs in
            tabs.compactMap {
                guard case .loaded(let tab) = $0 else { return nil }
                return tab
            }
        }.eraseToAnyPublisher()
    }

    let didRemoveTabPublisher = PassthroughSubject<(AnyTab, Int), Never>()

    init(tabs: [AnyTab] = [], isPopup: Bool = false) {
        assert(!isPopup || tabs.count <= 1, "Popup tab collections must contain at most one tab")
        self.isPopup = isPopup
        self.tabs = tabs
    }

    /// Convenience initializer accepting loaded tabs.
    convenience init(tabs: [Tab], isPopup: Bool = false) {
        self.init(tabs: tabs.map { .loaded($0) }, isPopup: isPopup)
    }

    deinit {
#if DEBUG
        // Only check loaded tabs — they hold expensive resources (WKWebView, extensions).
        // Unloaded tabs are lightweight data objects and don't inherit from NSObject
        // (which ensureObjectDeallocated requires).
        for tab in tabs {
            if case .loaded(let tab) = tab {
                tab.ensureObjectDeallocated(after: 1.0, do: .interrupt)
            }
        }
#endif
    }

    func contains(uuid: String) -> Bool {
        tabs.contains { $0.uuid == uuid }
    }

    func contains(tab: Tab) -> Bool {
        tabs.contains(.loaded(tab))
    }

    func firstIndex(of tab: Tab) -> Int? {
        tabs.firstIndex(of: .loaded(tab))
    }

    // MARK: - Append / Insert (Tab convenience wrappers)

    func append(tab: Tab) {
        append(tab: .loaded(tab))
    }

    func append(tab: AnyTab) {
        if isPopup, !tabs.isEmpty {
            assertionFailure("Popup tab collections must contain at most one tab")
            return
        }
        tabs.append(tab)

        if #available(macOS 15.4, *), case .loaded(let tab) = tab,
           let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
            webExtensionManager.eventsListener.didOpenTab(tab)
        }
    }

    func append(tabs newTabs: [AnyTab]) {
        if isPopup {
            assertionFailure("Popup tab collections must not receive batch appends")
            return
        }
        tabs.append(contentsOf: newTabs)

        if #available(macOS 15.4, *), let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
            for tab in newTabs {
                if case .loaded(let tab) = tab {
                    webExtensionManager.eventsListener.didOpenTab(tab)
                }
            }
        }
    }

    @discardableResult
    func insert(_ tab: Tab, at index: Int) -> Bool {
        insert(.loaded(tab), at: index)
    }

    @discardableResult
    func insert(_ tab: AnyTab, at index: Int) -> Bool {
        if isPopup, !tabs.isEmpty {
            assertionFailure("Popup tab collections must contain at most one tab")
            return false
        }
        guard index >= 0, index <= tabs.endIndex else {
            assertionFailure("TabCollection: Index out of bounds")
            return false
        }

        tabs.insert(tab, at: index)
        if #available(macOS 15.4, *), case .loaded(let tab) = tab,
           let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
            webExtensionManager.eventsListener.didOpenTab(tab)
        }
        return true
    }

    // MARK: - Remove

    @MainActor
    func removeTab(at index: Int, published: Bool = true, forced: Bool = false) -> Bool {
        guard tabs.indices.contains(index) else {
            assertionFailure("TabCollection: Index out of bounds")
            return false
        }

        let tab = tabs[index]
        tabWillClose(at: index, forced: forced)

        tabs.remove(at: index)
        if published {
            didRemoveTabPublisher.send((tab, index))
        }

        return true
    }

    // MARK: - Move

    func moveTab(at fromIndex: Int, to otherCollection: TabCollection, at toIndex: Int) -> Bool {
        guard let tab = tabs[safe: fromIndex],
              otherCollection.insert(tab, at: toIndex)
        else {
            assertionFailure("TabCollection: Index out of bounds")
            return false
        }

        tabs.remove(at: fromIndex)
        return true
    }

    func moveTab(at index: Int, to newIndex: Int) {
        guard tabs.indices.contains(index), tabs.indices.contains(newIndex) else {
            assertionFailure("TabCollection: Index out of bounds")
            return
        }

        if index == newIndex { return }
        if abs(index - newIndex) == 1 {
            tabs.swapAt(index, newIndex)
            return
        }

        var tabs = self.tabs
        tabs.insert(tabs.remove(at: index), at: newIndex)
        self.tabs = tabs
    }

    // MARK: - Bulk operations

    @MainActor
    func removeAll() {
        tabsWillClose(range: 0..<tabs.count)
        tabs = []
    }

    @MainActor
    func removeAll(andAppend tab: Tab) {
        tabsWillClose(range: 0..<tabs.count)
        tabs = [.loaded(tab)]
    }

    @MainActor
    func removeAll(andAppend tab: AnyTab) {
        tabsWillClose(range: 0..<tabs.count)
        tabs = [tab]
    }

    /// Clears tabViewModels and tabCollection after the tabs were moved to another collection
    func clearAfterMerge() {
        tabs.removeAll()
    }

    @MainActor
    func removeTabs(before index: Int) {
        tabsWillClose(range: 0..<index)
        tabs.removeSubrange(0..<index)
    }

    @MainActor
    func removeTabs(after index: Int) {
        tabsWillClose(range: (index + 1)..<tabs.count)
        tabs.removeSubrange((index + 1)...)
    }

    @MainActor
    func removeTabs(at indexSet: IndexSet) {
        guard !indexSet.contains(where: { index in
            index < 0 && index >= tabs.count
        }) else {
            assertionFailure("TabCollection: Index out of bounds")
            return
        }

        for i in indexSet {
            tabWillClose(at: i, forced: false)
        }
        tabs.remove(atOffsets: indexSet)
    }

    func reorderTabs(_ newOrder: [AnyTab]) {
        assert(tabs.count == newOrder.count && Set(tabs) == Set(newOrder), "tabs changed when reordering")
        tabs = newOrder
    }

    // MARK: - Replace

    @MainActor
    func replaceTab(at index: Int, with tab: AnyTab, suppressWebExtensionEvents: Bool = false, keepHistory: Bool = true) {
        guard tabs.indices.contains(index) else {
            assertionFailure("TabCollection: Index out of bounds")
            return
        }

        if keepHistory {
            keepLocalHistory(of: tabs[index])
        }
        let oldTab = tabs[index]
        tabs[index] = tab

        if !suppressWebExtensionEvents {
            if #available(macOS 15.4, *), let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
                switch (oldTab, tab) {
                case (.loaded(let oldLoadedTab), .loaded(let newLoadedTab)):
                    webExtensionManager.eventsListener.didReplaceTab(oldLoadedTab, with: newLoadedTab)
                case (.unloaded, .loaded(let newLoadedTab)):
                    webExtensionManager.eventsListener.didOpenTab(newLoadedTab)
                case (.loaded(let oldLoadedTab), .unloaded):
                    webExtensionManager.eventsListener.didCloseTab(oldLoadedTab, windowIsClosing: false)
                case (.unloaded, .unloaded):
                    break
                }
            }
        }
    }

    /// Convenience overload for replacing with a loaded Tab.
    @MainActor
    func replaceTab(at index: Int, with tab: Tab, keepHistory: Bool = true) {
        replaceTab(at: index, with: .loaded(tab), keepHistory: keepHistory)
    }

    // MARK: - Private

    @MainActor
    private func tabWillClose(at index: Int, forced: Bool) {
        if !forced {
            keepLocalHistory(of: tabs[index])
        }

        if #available(macOS 15.4, *), case .loaded(let tab) = tabs[index],
           let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
            webExtensionManager.eventsListener.didCloseTab(tab, windowIsClosing: false)
        }
    }

    @MainActor
    private func tabsWillClose(range: Range<Int>) {
        for i in range {
            keepLocalHistory(of: tabs[i])

            if #available(macOS 15.4, *), case .loaded(let tab) = tabs[i],
               let webExtensionManager = NSApp.delegateTyped.webExtensionManager {
                webExtensionManager.eventsListener.didCloseTab(tab, windowIsClosing: false)
            }
        }
    }

    // MARK: - Fire button

    // Visits of removed tabs used for fire button logic
    var localHistoryOfRemovedTabs = [Visit]()
    var removedTabDomains = Set<String>()

    @MainActor
    private func keepLocalHistory(of tab: AnyTab) {
        for visit in tab.localHistory where !localHistoryOfRemovedTabs.contains(visit) {
            localHistoryOfRemovedTabs.append(visit)
        }
        removedTabDomains.formUnion(tab.localHistoryDomains)
    }

}
