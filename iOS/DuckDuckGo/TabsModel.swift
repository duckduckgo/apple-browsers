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

    var count: Int {
        return tabs.count
    }

    var hasActiveTabs: Bool {
        guard !tabs.isEmpty else { return false }
        return tabs.count > 1 || tabs.last?.link != nil
    }

    func select(tabAt index: Int) {
        _currentIndex = index
    }

    func get(tabAt index: Int) -> Tab {
        return tabs[index]
    }

    func add(tab: Tab) {
        guard shouldCreateFireTabs == tab.fireTab else {
            assertionFailure("Wrong tab type for this tabs model")
            return
        }
        tabs.append(tab)
        _currentIndex = tabs.count - 1
    }

    func insert(tab: Tab, at index: Int) {
        guard shouldCreateFireTabs == tab.fireTab else {
            assertionFailure("Wrong tab type for this tabs model")
            return
        }
        tabs.insert(tab, at: max(0, index))
    }
    
    func moveTab(from sourceIndex: Int, to destIndex: Int) {
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

    func remove(at index: Int) {
        let selectedTab = safeGetTabAt(currentIndex)
        tabs.remove(at: index)
        if tabs.isEmpty && !allowsEmpty {
            tabs.append(Tab(fireTab: shouldCreateFireTabs))
        }
        setCurrentTab(selectedTab)
    }

    /// This *does not* add a new empty tab after removing the items.
    func remove(_ indexPaths: [IndexPath]) {
        let selectedTab = safeGetTabAt(currentIndex)
        let indexes = Set(indexPaths.map { $0.row })
        self.tabs = tabs.enumerated().filter { !indexes.contains($0.offset) }.map { $0.element }
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
}
