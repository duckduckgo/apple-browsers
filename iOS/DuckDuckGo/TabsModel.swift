//
//  TabsModel.swift
//  DuckDuckGo
//
//  Copyright © 2017 DuckDuckGo. All rights reserved.
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

import Foundation
import Core
import Combine

public class TabsModel: NSObject, NSCoding, TabsModelManaging {

    private struct NSCodingKeys {
        static let legacyIndex = "currentIndex"
        static let currentIndex = "currentIndex2"
        static let legacyTabs = "tabs"
        static let tabs = "tabs2"
        static let mode = "mode"
    }
    
    enum TabPlacement {
        case afterCurrentTab
        case atEnd
        case replacing(Tab)
    }

    let mode: BrowsingMode
    
    var currentIndex: Int? {
        if tabs.indices.contains(_currentIndex) {
            return _currentIndex
        }
        return nil
    }
    
    private var _currentIndex: Int
    @Published private(set) var tabs: [Tab]
    
    var shouldCreateFireTabs: Bool {
        mode == .fire
    }

    var allowsEmpty: Bool {
        mode.allowsEmpty
    }

    var tabsPublisher: AnyPublisher<[Tab], Never> {
        $tabs.eraseToAnyPublisher()
    }

    var hasUnread: Bool {
        return tabs.contains(where: { !$0.viewed })
    }
        
    public init(tabs: [Tab] = [], currentIndex: Int = 0, desktop: Bool, mode: BrowsingMode = .normal) {
        self.mode = mode
        let shouldCreateFireTabs = mode == .fire
        if tabs.isEmpty && !mode.allowsEmpty {
            self.tabs = [Tab(desktop: desktop, fireTab: shouldCreateFireTabs)]
        } else {
            self.tabs = tabs
        }
        self._currentIndex = currentIndex
    }

    public convenience required init?(coder decoder: NSCoder) {
        // we migrated tabs to support uid
        let storedTabs: [Tab]?
        if let legacyTabs = decoder.decodeObject(forKey: NSCodingKeys.legacyTabs) as? [Tab], !legacyTabs.isEmpty {
            storedTabs = legacyTabs
        } else {
            storedTabs = decoder.decodeObject(forKey: NSCodingKeys.tabs) as? [Tab]
        }
        
        guard let tabs = storedTabs else {
            return nil
        }

        // we migrated from an optional int to an actual int
        var currentIndex = 0
        if let storedIndex = decoder.decodeObject(forKey: NSCodingKeys.legacyIndex) as? Int {
            currentIndex = storedIndex
        } else {
            currentIndex = decoder.decodeInteger(forKey: NSCodingKeys.currentIndex)
        }
        
        // When tabs is empty (e.g. fire mode), this resets to 0. The computed
        // `currentIndex` property guards against out-of-bounds by returning nil.
        if currentIndex < 0 || currentIndex >= tabs.count {
            currentIndex = 0
        }

        let rawMode = decoder.containsValue(forKey: NSCodingKeys.mode)
            ? decoder.decodeInteger(forKey: NSCodingKeys.mode)
            : BrowsingMode.normal.rawValue
        let mode = BrowsingMode(rawValue: rawMode) ?? .normal

        self.init(tabs: tabs, currentIndex: currentIndex, desktop: UIDevice.current.userInterfaceIdiom == .pad, mode: mode)
    }

    public func encode(with coder: NSCoder) {
        coder.encode(tabs, forKey: NSCodingKeys.tabs)
        coder.encode(_currentIndex, forKey: NSCodingKeys.currentIndex)
        coder.encode(mode.rawValue, forKey: NSCodingKeys.mode)
    }

    var currentTab: Tab? {
        guard let index = currentIndex else {
            return nil
        }
        return tabs.indices.contains(index) ? tabs[index] : nil
    }
    
    /// The tab after the current tab, wrapping from the last tab back to the first.
    var nextTab: Tab? {
        guard !tabs.isEmpty, let currentIndex else { return nil }
        let nextIndex = currentIndex + 1 >= tabs.count ? 0 : currentIndex + 1
        return get(tabAt: nextIndex)
    }

    /// The tab before the current tab, wrapping from the first tab to the last.
    var previousTab: Tab? {
        guard !tabs.isEmpty, let currentIndex else { return nil }
        let previousIndex = currentIndex - 1 < 0 ? tabs.count - 1 : currentIndex - 1
        return get(tabAt: previousIndex)
    }

    /// The tab immediately before the current tab without wrapping. Returns `nil` when the current tab is first.
    var tabBefore: Tab? {
        guard let currentIndex, currentIndex > 0 else { return nil }
        return get(tabAt: currentIndex - 1)
    }

    var count: Int {
        return tabs.count
    }

    var hasActiveTabs: Bool {
        guard !tabs.isEmpty else { return false }
        return tabs.count > 1 || tabs.last?.link != nil
    }
    
    func select(tab: Tab) {
        guard validateTabMode(tab, operation: .select) else { return }
        guard let index = indexOf(tab: tab) else { return }
        _currentIndex = index
    }

    func get(tabAt index: Int?) -> Tab? {
        guard let index, tabs.indices.contains(index) else { return nil }
        return tabs[index]
    }
    
    func insert(tab: Tab, placement: TabsModel.TabPlacement, selectNewTab: Bool) {
        guard validateTabMode(tab, operation: .insert) else { return }
        var newTabIndex: Int?
        switch placement {
        case .afterCurrentTab:
            var newIndex: Int
            if let currentIndex {
                newIndex = currentIndex + 1
            } else {
                newIndex = 0
            }
            insert(tab: tab, at: newIndex)
            newTabIndex = newIndex
        case .atEnd:
            tabs.append(tab)
            newTabIndex = tabs.count - 1
        case .replacing(let oldTab):
            newTabIndex = replace(oldTab: oldTab, with: tab)
        }
        if selectNewTab, let newTabIndex {
            _currentIndex = newTabIndex
        }
    }

    private func insert(tab: Tab, at index: Int) {
        tabs.insert(tab, at: max(0, index))
    }
    
    
    /// Replaces a tab with another tab inplace
    /// - Parameters:
    ///   - oldTab: tab to remove
    ///   - newTab: tab to insert
    /// - Returns: Index of the new tab
    private func replace(oldTab: Tab, with newTab: Tab) -> Int? {
        guard let index = indexOf(tab: oldTab) else {
            return nil
        }
        let selectedTab = currentTab
        remove(tab: oldTab)
        insert(tab: newTab, at: index)
        setCurrentTab(selectedTab)
        return index
    }
    
    func move(tab: Tab, to destIndex: Int) {
        guard validateTabMode(tab, operation: .move) else { return }
        guard let sourceIndex = indexOf(tab: tab) else { return }
        moveTab(from: sourceIndex, to: destIndex)
    }
    
    private func moveTab(from sourceIndex: Int, to destIndex: Int) {
        guard sourceIndex >= 0, sourceIndex < tabs.count,
            destIndex >= 0, destIndex < tabs.count else {
                return
        }
        
        let previouslyCurrentTab = currentTab
        let tab = tabs.remove(at: sourceIndex)
        tabs.insert(tab, at: destIndex)
        
        if let reselectTab = previouslyCurrentTab {
            _currentIndex = indexOf(tab: reselectTab) ?? 0
        }
    }

    private func remove(at index: Int) {
        let selectedTab = get(tabAt: currentIndex)
        tabs.remove(at: index)
        if tabs.isEmpty && !allowsEmpty {
            tabs.append(Tab(fireTab: shouldCreateFireTabs))
        }
        setCurrentTab(selectedTab)
    }

    /// This *does not* add a new empty tab after removing the items.
    func removeTabs(_ tabsToBeRemoved: [Tab]) {
        let validTabs = tabsToBeRemoved.filter { validateTabMode($0, operation: .removeTabs) }
        let selectedTab = get(tabAt: currentIndex)
        self.tabs = tabs.filter { !validTabs.contains($0) }
        setCurrentTab(selectedTab)
    }

    private func setCurrentTab(_ tab: Tab?) {
        if let tab, let index = indexOf(tab: tab) {
            _currentIndex = index
        } else if tabs.isEmpty {
            _currentIndex = 0
        } else if _currentIndex >= tabs.count {
            _currentIndex = tabs.count - 1
        } else if _currentIndex > 0 {
            _currentIndex -= 1
        }
        // Else: don't adjust the index as it'll be the 'next' tab
    }
 
    func remove(tab: Tab) {
        guard validateTabMode(tab, operation: .remove) else { return }
        if let index = indexOf(tab: tab) {
            remove(at: index)
        }
    }

    func clearAll() {
        tabs.removeAll()
        if !allowsEmpty {
            tabs.append(Tab(fireTab: shouldCreateFireTabs))
        }
        _currentIndex = 0
    }
    
    func tabExists(withHost host: String) -> Bool {
        return tabs.contains { $0.link?.url.host == host }
    }
    
    func tabExists(tab: Tab) -> Bool {
        return tabs.contains { $0 === tab }
    }
}

private extension TabsModel {

    private enum Operation: String {
        case select
        case insert
        case move
        case remove
        case removeTabs
    }

    private func validateTabMode(_ tab: Tab, operation: Operation) -> Bool {
        guard tab.fireTab == shouldCreateFireTabs else {
            assertionFailure("Tab mode mismatch in \(operation): tab.fireTab=\(tab.fireTab), model.mode=\(mode)")
            Pixel.fire(pixel: .debugTabsModelCrossModeMismatch, withAdditionalParameters: [
                PixelParameters.tabsModelOperation: operation.rawValue
            ])
            return false
        }
        return true
    }
}
